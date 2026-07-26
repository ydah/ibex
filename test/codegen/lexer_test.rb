# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "strscan"

class GeneratedLexerTest < Minitest::Test
  def test_uses_longest_match_then_declaration_order
    parser = build(<<~GRAMMAR).new
      class LongestLexer
      pragma extended
      token KW IDENT FIRST SECOND
      lexer
        skip /\s+/
        KW /if/
        FIRST /b+/
        SECOND /b+/
        IDENT /[a-z]+/
      end
      rule
      start: IDENT KW FIRST { result = val }
      end
    GRAMMAR

    assert_equal %w[ifx if bbb], parser.parse("ifx if bbb")
  end

  def test_longest_match_contract_holds_for_generated_cases
    parser = build(<<~GRAMMAR).new
      class PropertyLexer
      pragma extended
      token AWORD ABWORD BWORD
      lexer
        AWORD /a+/
        ABWORD /a+b/
        BWORD /b+/
      end
      rule
      start: AWORD | ABWORD | BWORD
      end
    GRAMMAR
    random = Random.new(19_840_117)
    patterns = [[:AWORD, /\Aa+/], [:ABWORD, /\Aa+b/], [:BWORD, /\Ab+/]]

    100.times do
      source = Array.new(random.rand(1..8)) { random.rand(2).zero? ? "a" : "b" }.join
      candidates = patterns.filter_map.with_index do |(token, regexp), index|
        match = regexp.match(source)
        [token, match[0], index] if match
      end
      next if candidates.empty?

      expected = candidates.max_by { |_token, lexeme, index| [lexeme.bytesize, -index] }
      token, value, = parser.lex(source).next_token
      assert_equal [expected.fetch(0), expected.fetch(1)], [token, value]
    end
  end

  def test_actions_manage_states_and_convert_values
    parser = build(<<~'GRAMMAR').new
      class StatefulLexer
      pragma extended
      token NUM STR_BEGIN STR_END CHUNK
      lexer
        skip /\s+/
        NUM /\d+/ { |text| Integer(text, 10) }
        state STRING do
          on '"' { pop_state; emit :STR_END }
          CHUNK /[^"\\]+/
        end
        on '"' { push_state :STRING; emit :STR_BEGIN }
      end
      rule
      start: NUM STR_BEGIN CHUNK STR_END { result = [val[0], val[2]] }
      end
    GRAMMAR

    assert_equal [12, "hello"], parser.parse('12 "hello"')
    assert_equal :INITIAL, parser.lexer_state
  end

  def test_parser_actions_can_select_the_official_lexer_state
    parser = build(<<~GRAMMAR).new
      class FeedbackLexer
      pragma extended
      token OPEN WORD
      lexer
        OPEN /</
        state BODY do
          WORD /[a-z]+/
        end
      end
      rule
      start: OPEN switch WORD { result = val[2] }
      switch: %empty { self.lexer_state = :BODY }
      end
    GRAMMAR

    assert_equal "content", parser.parse("<content")
    assert_equal :BODY, parser.lexer_state
  end

  def test_io_and_fiber_chunks_may_split_tokens
    parser_class = build(streaming_source)
    io = Class.new(StringIO) do
      def read(_size) = super(2)
    end.new("12345 world")
    fiber = Fiber.new do
      Fiber.yield("12")
      Fiber.yield("345 wo")
      "rld"
    end
    fiber.define_singleton_method(:respond_to?) do |name, include_all = false|
      name == :alive? ? false : super(name, include_all)
    end

    assert_equal [12_345, "world"], parser_class.new.parse(io)
    assert_equal [12_345, "world"], parser_class.new.parse(fiber)
  end

  def test_fiber_errors_from_the_source_are_not_hidden
    fiber = Fiber.new { raise FiberError, "source failed" }
    fiber.define_singleton_method(:respond_to?) do |name, include_all = false|
      name == :alive? ? false : super(name, include_all)
    end
    input = Ibex::Runtime::LexerInput.new(fiber)

    error = assert_raises(FiberError) { input.read_more? }
    assert_equal "source failed", error.message
  end

  def test_unicode_locations_report_grapheme_and_byte_coordinates
    parser = build(<<~GRAMMAR).new
      class UnicodeLexer
      pragma extended
      token WORD BANG
      lexer
        WORD /[\\p{L}\\p{M}]+/
        BANG /!/
      end
      rule
      start: WORD BANG { result = [loc(1), loc(2)] }
      end
    GRAMMAR
    word, bang = parser.parse("e\u0301猫!", file: "unicode.txt")

    assert_equal 1, word.fetch(:column)
    assert_equal 3, word.fetch(:end_grapheme_column)
    assert_equal 6, word.fetch(:end_byte)
    assert_equal 3, bang.fetch(:column)
    assert_equal 7, bang.fetch(:byte_column)
    assert_equal 7, bang.fetch(:end_byte)
  end

  def test_generated_locations_match_a_handwritten_lexer_contract
    source = "12\nword"
    generated = build(streaming_source).new.lex(source, file: "same.txt")
    actual = 2.times.map { location_projection(generated.next_token.fetch(2)) }

    assert_equal handwritten_locations(source), actual
  end

  def test_generated_rbs_publishes_lexer_contract
    automaton = automaton(streaming_source)
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature, "LEXER_RULES_BY_STATE"
    assert_includes signature, "def parse: (String | IO | Fiber source"
    assert_includes signature, "private def _ibex_lexer_action_1"
  end

  private

  def streaming_source
    <<~GRAMMAR
      class StreamingLexer
      pragma extended
      token NUM WORD
      lexer
        skip /\\s+/
        NUM /\\d+/ { |s| Integer(s, 10) }
        WORD /[a-z]+/
      end
      rule
      start: NUM WORD { result = val }
      end
    GRAMMAR
  end

  def build(source)
    generated = Ibex::Codegen::Ruby.new(automaton(source)).generate
    container = Module.new
    container.module_eval(generated, "generated_lexer.rb")
    class_name = source[/\Aclass\s+([A-Za-z0-9_:]+)/, 1]
    container.const_get(class_name)
  end

  def automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "lexer_codegen.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def handwritten_locations(source)
    scanner = StringScanner.new(source)
    %i[NUM WORD].map do |_token|
      scanner.skip(/\s+/)
      start = scanner.pos
      scanner.scan(/\d+|[a-z]+/) || raise("handwritten lexer failed")
      finish = scanner.pos
      start_prefix = source.byteslice(0, start)
      finish_prefix = source.byteslice(0, finish)
      line = start_prefix.count("\n") + 1
      end_line = finish_prefix.count("\n") + 1
      {
        file: "same.txt", line: line, column: start_prefix.rpartition("\n").last.length + 1,
        end_line: end_line, end_column: finish_prefix.rpartition("\n").last.length + 1,
        start_byte: start, end_byte: finish, source_line: source.lines.fetch(line - 1).chomp
      }
    end
  end

  def location_projection(location)
    location.slice(:file, :line, :column, :end_line, :end_column, :start_byte, :end_byte, :source_line)
  end
end
