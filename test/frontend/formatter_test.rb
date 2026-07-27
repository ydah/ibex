# frozen_string_literal: true

require_relative "../test_helper"

class FrontendFormatterTest < Minitest::Test
  def test_formats_a_root_and_is_idempotent
    source = "class   Demo :: Parser< Base token A B rule first:A|B ; second: end"
    expected = <<~GRAMMAR
      class Demo::Parser < Base
      token A B
      rule
        first : A
          | B;
        second :
      end
    GRAMMAR

    formatted = format(source)

    assert_equal expected, formatted
    assert_equal formatted, format(formatted)
  end

  def test_formats_extended_fragment_adjacency_inline_and_nested_groups
    source = "fragment token A B rule %inline pair(X):(X|A); value:pair(pair(A)):items (A (B|A)?)+ end"
    expected = <<~GRAMMAR
      fragment
      token A B
      rule
        %inline pair(X) : (X | A);
        value : pair(pair(A)):items (A (B | A)?)+
      end
    GRAMMAR

    assert_equal expected, format(source, mode: :extended)
    document = Ibex::Frontend::Parser.new(expected, file: "fragment.y", mode: :extended).parse_source_document
    assert_instance_of Ibex::Frontend::AST::Fragment, document.ast
  end

  def test_formats_import_as_a_declaration
    source = "class P import \"tokens.y\" token A rule start:A end"
    expected = "class P\nimport \"tokens.y\"\ntoken A\nrule\n  start : A\nend\n"

    assert_equal expected, format(source, mode: :extended)
    assert_equal expected, format(expected, mode: :extended)
  end

  def test_preserves_comments_actions_heredocs_and_user_code_byte_for_byte
    source = <<~'GRAMMAR'
      class   P
      token A # token comment
      rule
        /* before */ value:A { text = <<~"END } MARK"
      #{ { brace: "}" } }
      END } MARK
      result = text }
      end
      ---- header
      # header stays exactly here
      ---- inner
      def helper = "{ }"
    GRAMMAR

    formatted = format(source)

    assert_equal protected_segments(source), protected_segments(formatted)
    assert_includes formatted, <<~'ACTION'.chomp
      { text = <<~"END } MARK"
      #{ { brace: "}" } }
      END } MARK
      result = text }
    ACTION
    assert_equal formatted, format(formatted)
  end

  def test_preserves_a_user_code_section_that_terminates_rules
    source = "class P\nrule\nstart:TOKEN\n---- inner\ndef helper = true\n"
    formatted = format(source)

    assert_equal "class P\nrule\n  start : TOKEN\n---- inner\ndef helper = true\n", formatted
    assert_equal formatted, format(formatted)
  end

  def test_treats_every_supported_heredoc_delimiter_as_opaque
    source = <<~'GRAMMAR'
      class P
      rule
      bare: X { text = <<TEXT
      }
      TEXT
      result = text }
      single: X { text = <<-'TEXT'
      }
      TEXT
      result = text }
      double: X { text = <<~"END } MARK"
      #{ { brace: "}" } }
      END } MARK
      result = text }
      command: X { text = <<-`SHELL`
      }
      SHELL
      result = text }
      end
    GRAMMAR

    formatted = format(source)
    document = Ibex::Frontend::Parser.new(formatted).parse_source_document
    action_count = document.cst.count { |segment| segment.kind == :action }

    assert_equal protected_segments(source), protected_segments(formatted)
    assert_equal 4, action_count
    assert_equal formatted, format(formatted)
  end

  def test_preserves_documentation_attachment
    source = <<~GRAMMAR
      class P
      rule
       ## First.
          ## Second.
      value:A
      end
    GRAMMAR

    formatted = format(source)
    document = Ibex::Frontend::Parser.new(formatted, file: "format.y").parse_source_document

    assert_includes formatted, "  ## First.\n  ## Second.\n  value : A"
    assert_equal "First.\nSecond.", document.ast.rules.fetch(0).documentation
  end

  def test_preserves_existing_mixed_newline_bytes
    source = "class  P\r\ntoken A\nrule\r\nvalue:A\nend\r\n"

    formatted = format(source)

    assert_equal ["\r\n", "\n", "\r\n", "\n", "\r\n"], formatted.scan(/\r\n|\n/)
    assert_equal formatted, format(formatted)
  end

  def test_uses_the_first_newline_inside_an_opaque_action_for_new_boundaries
    source = "class P rule value:A { result = (\r\n  1\r\n) } end"

    formatted = format(source)

    assert_equal ["\r\n"] * 6, formatted.scan(/\r\n|\n/)
    assert_includes formatted, "{ result = (\r\n  1\r\n) }"
  end

  def test_semantic_comparison_is_stack_safe_for_deep_extended_ebnf
    depth = 1_000
    nested = "#{'(' * depth}A#{')' * depth}"
    source = "class P\npragma extended\nrule\nvalue: #{nested}\nend\n"

    formatted = format(source, mode: :extended)

    assert_equal formatted, format(formatted, mode: :extended)
    assert_includes formatted, nested
  end

  def test_rejects_invalid_source_without_mutating_the_input
    source = +"class P\nrule\nbroken: (\nend\n"
    original = source.dup

    error = assert_raises(Ibex::Error) { format(source) }

    assert_match(/format\.y:/, error.message)
    assert_equal original, source
  end

  def test_semantic_projection_guard_rejects_a_parseable_change
    formatter_class = Class.new(Ibex::Frontend::Formatter) do
      private

      def render(document)
        document.source.sub("A", "B")
      end
    end
    source = "class P\nrule\nvalue: A\nend\n"

    error = assert_raises(Ibex::Error) { formatter_class.new.format(source, file: "guard.y") }

    assert_equal "guard.y: formatting would change grammar semantics", error.message
  end

  def test_all_shipped_grammar_fixtures_are_semantically_stable_and_idempotent
    paths = (
      Dir.glob(File.expand_path("../fixtures/grammar/**/*.y", __dir__)) +
      Dir.glob(File.expand_path("../../examples/**/*.y", __dir__))
    ).sort
    refute_empty paths

    paths.each do |path|
      source = File.binread(path)
      mode = path.include?("/fixtures/grammar/") ? :extended : :default
      formatted = Ibex::Frontend::Formatter.format(source, file: path, mode: mode)

      assert_equal formatted, Ibex::Frontend::Formatter.format(formatted, file: path, mode: mode), path
    end
  end

  private

  def format(source, mode: :default)
    Ibex::Frontend::Formatter.format(source, file: "format.y", mode: mode)
  end

  def protected_segments(source)
    document = Ibex::Frontend::Lexer.new(source, file: "format.y").tokenize_document
    document.cst.reject { |segment| %i[whitespace newline eof].include?(segment.kind) }
                .map { |segment| [segment.kind, segment.text] }
  end
end
