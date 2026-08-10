# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"

class IRRuleDocumentationTest < Minitest::Test
  def test_rule_documentation_populates_symbols_and_each_user_production
    grammar = documented_value_grammar
    symbol = grammar.symbol("value")
    productions = grammar.productions.select { |production| production.lhs == symbol.id }
    assert_equal "Parses a value.\nSupports two token forms.", symbol.documentation
    assert_equal [symbol.documentation, symbol.documentation], productions.map(&:documentation)
    assert_predicate symbol.documentation, :frozen?
  end

  def test_rule_documentation_serializes_in_current_ir
    grammar = documented_value_grammar
    symbol = grammar.symbol("value")
    grammar.productions.select { |production| production.lhs == symbol.id }
    serialized = Ibex::IR::Serialize.dump(grammar)
    document = JSON.parse(serialized)
    serialized_symbol = document.fetch("symbols").find { |entry| entry.fetch("name") == "value" }
    assert_equal symbol.documentation, serialized_symbol.fetch("doc")
    assert_equal(
      [symbol.documentation, symbol.documentation],
      document.fetch("productions").last(2).map { |production| production.fetch("doc") }
    )
    validated = Ibex::IR::Validator.validate(serialized)
    raise "expected grammar IR" unless validated.is_a?(Ibex::IR::Grammar)

    assert_equal symbol.documentation, validated.symbol("value").documentation
  end

  def test_repeated_rule_uses_first_nonnil_documentation_and_accepts_same_text
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      value: FIRST
      ## Shared value.
      value: SECOND
      ## Shared value.
      value: THIRD
      end
    GRAMMAR

    symbol = grammar.symbol("value")
    productions = grammar.productions.select { |production| production.lhs == symbol.id }
    assert_equal "Shared value.", symbol.documentation
    assert_equal [nil, "Shared value.", "Shared value."], productions.map(&:documentation)
  end

  def test_repeated_rule_rejects_a_different_later_documentation_at_that_rule
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        rule
        ## First meaning.
        value: FIRST
        ## Different meaning.
        value: SECOND
        end
      GRAMMAR
    end

    assert_equal "documentation.y:6:1: conflicting documentation for rule value", error.message
  end

  def test_included_fragment_documentation_survives_resolution_and_deep_freeze
    Dir.mktmpdir("ibex-rule-doc") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.write(root, "class P\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.write(fragment, "fragment\nrule\n## Included helper.\nhelper: TOKEN\nend\n")

      resolution = Ibex::Frontend::Resolver.new(root, mode: :extended).resolve
      rule = resolution.root.rules.find { |candidate| candidate.lhs == "helper" }
      assert_equal "Included helper.", rule.documentation
      assert_predicate rule.documentation, :frozen?

      grammar = Ibex::Normalizer.new(resolution, mode: :extended).normalize
      assert_equal "Included helper.", grammar.symbol("helper").documentation
      production = grammar.productions.find { |candidate| candidate.lhs == grammar.symbol("helper").id }
      assert_equal "Included helper.", production.documentation
    end
  end

  private

  def documented_value_grammar
    normalize(<<~GRAMMAR)
      class P
      rule
      ## Parses a value.
      ## Supports two token forms.
      value: FIRST | SECOND
      end
    GRAMMAR
  end

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "documentation.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end
end
