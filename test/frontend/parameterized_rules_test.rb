# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"
require "tmpdir"

class FrontendParameterizedRulesTest < Minitest::Test
  def test_parses_definition_nested_call_named_reference_and_suffix
    ast = parse(<<~GRAMMAR)
      class P
      pragma extended
      rule
      pair(Left, Right): Left Right
      start: pair(ITEM, pair(A, B)):value+
      end
    GRAMMAR

    template, start = ast.rules
    assert_equal %w[Left Right], template.parameters
    assert_empty start.parameters
    plus = start.alternatives.first.items.first
    assert_instance_of Ibex::Frontend::AST::Plus, plus
    call = plus.item
    assert_instance_of Ibex::Frontend::AST::ParameterizedReference, call
    assert_equal "pair", call.name
    assert_equal "value", call.named_reference
    assert_instance_of Ibex::Frontend::AST::ParameterizedReference, call.arguments.last
    assert_equal %w[A B], call.arguments.last.arguments.map(&:name)
    assert_includes template.to_h, :parameters
    assert_includes call.to_h, :arguments
  end

  def test_byte_adjacency_disambiguates_calls_from_symbols_followed_by_groups
    ast = parse(<<~GRAMMAR)
      class P
      pragma extended
      rule
      template(X): X
      start: ITEM (A | B) template(C)
      end
    GRAMMAR
    items = ast.rules.last.alternatives.first.items

    assert_instance_of Ibex::Frontend::AST::SymbolReference, items[0]
    assert_instance_of Ibex::Frontend::AST::Group, items[1]
    assert_instance_of Ibex::Frontend::AST::ParameterizedReference, items[2]

    error = assert_raises(Ibex::Error) do
      parse("class P\npragma extended\nrule\ntemplate (X): X\nstart: X\nend\n")
    end
    assert_equal "parameter.y:4:10: parameter list must immediately follow rule name", error.message
  end

  def test_parameterized_rules_are_extended_only_but_pragma_enables_them
    source = "class P\nrule\nlist(X): X\nstart: list(NUM)\nend\n"
    error = assert_raises(Ibex::Error) { parse(source, mode: :racc) }
    assert_equal "parameter.y:3:5: parameterized rules require extended mode", error.message

    source = "class P\npragma extended\nrule\nlist(X): X\nstart: list(NUM)\nend\n"
    assert_equal ["X"], parse(source, mode: :racc).rules.first.parameters
  end

  def test_bootstrap_and_generated_frontends_agree
    source = File.read(File.expand_path("../fixtures/grammar/parameterized.y", __dir__))
    generated = parse(source, mode: :extended)
    bootstrap = Ibex::Frontend::BootstrapParser.new(
      source, file: "parameter.y", mode: :extended
    ).parse

    assert_equal generated.to_h, bootstrap.to_h
  end

  def test_end_is_an_identifier_inside_nested_parameter_and_group_delimiters
    source = <<~GRAMMAR
      class P
      pragma extended
      token end
      rule
      wrap(X): X
      start: wrap((end | wrap(end)))
      end
    GRAMMAR
    generated = parse(source, mode: :extended)
    bootstrap = Ibex::Frontend::BootstrapParser.new(
      source, file: "parameter.y", mode: :extended
    ).parse

    assert_equal generated.to_h, bootstrap.to_h
    grammar = Ibex::Normalizer.new(generated, mode: :extended).normalize
    assert(grammar.productions.any? { |production| production.rhs.include?(grammar.symbol("end").id) })
  end

  def test_rule_constructor_defaults_omitted_parameters_for_legacy_keyword_and_hash_callers
    location = Ibex::Frontend::Location.new(file: "legacy.rb", line: 1, column: 1)
    keyword_rule = Ibex::Frontend::AST::Rule.new(lhs: "start", alternatives: [], loc: location)
    hash_rule = Ibex::Frontend::AST::Rule.new({ lhs: "start", alternatives: [], loc: location })
    nil_keyword_rule = Ibex::Frontend::AST::Rule.new(
      lhs: "start", parameters: nil, alternatives: [], loc: location
    )
    nil_hash_rule = Ibex::Frontend::AST::Rule.new(
      { lhs: "start", parameters: nil, alternatives: [], loc: location }
    )

    assert_empty keyword_rule.parameters
    assert_empty hash_rule.parameters
    assert_empty nil_keyword_rule.parameters
    assert_empty nil_hash_rule.parameters
    assert_raises(ArgumentError) do
      Ibex::Frontend::AST::Rule.new(lhs: "start", alternatives: [], loc: location, unknown: true)
    end
    assert_raises(ArgumentError) do
      Ibex::Frontend::AST::Rule.new({ lhs: "start", alternatives: [], loc: location, unknown: true })
    end
  end

  def test_documentation_and_resolver_freezing_preserve_parameters
    Dir.mktmpdir("ibex-parameters") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.write(root, <<~GRAMMAR)
        class P
        pragma extended
        include "fragment.y"
        rule
        start: list(NUM)
        end
      GRAMMAR
      File.write(fragment, <<~GRAMMAR)
        fragment
        rule
        ## Included list.
        list(X): X
        end
      GRAMMAR

      resolution = Ibex::Frontend::Resolver.new(root).resolve
      template = resolution.root.rules.find { |rule| rule.lhs == "list" }
      assert_equal ["X"], template.parameters
      assert_equal "Included list.", template.documentation
      assert_predicate template.parameters, :frozen?
      assert_predicate template.parameters.first, :frozen?
      assert_raises(FrozenError) { template.parameters << "Y" }
    end
  end

  private

  def parse(source, mode: :extended)
    Ibex::Frontend::Parser.new(source, file: "parameter.y", mode: mode).parse
  end
end
