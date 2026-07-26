# frozen_string_literal: true

require_relative "../test_helper"

class RactorShareabilityCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class ShareableParser
    token VALUE
    rule
    start: VALUE { result = val[0] }
    end
  GRAMMAR

  def test_plain_compact_and_embedded_parser_tables_are_shareable
    skip "Ractor shareability is unavailable" unless defined?(Ractor) && Ractor.respond_to?(:shareable?)

    [{ table: :plain, embedded: false }, { table: :compact, embedded: false },
     { table: :plain, embedded: true }, { table: :compact, embedded: true }].each do |options|
      parser_class = generate_parser(**options)
      assert Ractor.shareable?(parser_class::PARSER_TABLES), "unshareable tables for #{options.inspect}"
    end
  end

  def test_distinct_instances_parse_concurrently_in_threads
    parser_class = generate_parser
    threads = 8.times.map do |value|
      Thread.new do
        parser = parser_class.new
        parser.push(:VALUE, value)
        parser.finish
      end
    end

    assert_equal (0...8).to_a, threads.map(&:value)
  end

  def test_distinct_instances_parse_in_ractors_with_shared_tables
    skip "Ractor is unavailable" unless defined?(Ractor) && Ractor.respond_to?(:shareable?)

    parser_class = generate_parser
    ractors = 2.times.map do |value|
      Ractor.new(parser_class, value) do |klass, input|
        parser = klass.new
        parser.push(:VALUE, input)
        parser.finish
      end
    end

    results = ractors.map { |ractor| ractor.respond_to?(:value) ? ractor.value : ractor.take }
    assert_equal [0, 1], results
  end

  def test_thread_conversion_does_not_make_parser_loading_fail
    source = <<~GRAMMAR
      class ThreadTokenParser
      token VALUE
      convert
      VALUE 'Thread.current'
      end
      rule
      start: VALUE
      end
    GRAMMAR

    generated = generate(source: source)
    refute_includes generated, "Ractor.make_shareable(PARSER_TABLES)"
    parser_class = evaluate(generated, class_name: :ThreadTokenParser)

    assert_equal 2, parser_class::TOKEN_IDS.fetch(Thread.current)
  end

  def test_conversion_does_not_freeze_an_external_token_object
    source = <<~GRAMMAR
      class ExternalTokenParser
      token VALUE
      convert
      VALUE 'ExternalToken'
      end
      rule
      start: VALUE
      end
    GRAMMAR
    external_token = Object.new
    namespace = Module.new
    namespace.const_set(:ExternalToken, external_token)

    generated = generate(source: source)
    evaluate(generated, class_name: :ExternalTokenParser, namespace: namespace)

    refute_predicate external_token, :frozen?
  end

  private

  def generate_parser(table: :compact, embedded: false, source: SOURCE, class_name: :ShareableParser,
                      namespace: Module.new)
    evaluate(generate(table: table, embedded: embedded, source: source), class_name: class_name, namespace: namespace)
  end

  def generate(table: :compact, embedded: false, source: SOURCE)
    ast = Ibex::Frontend::Parser.new(source, file: "shareable.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, table: table, embedded: embedded).generate
  end

  def evaluate(generated, class_name:, namespace: Module.new)
    namespace.module_eval(generated, "shareable.rb")
    namespace.const_get(class_name)
  end
end
