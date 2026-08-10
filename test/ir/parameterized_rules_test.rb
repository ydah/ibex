# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"
require "tmpdir"

class IRParameterizedRulesTest < Minitest::Test
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)

  def test_specializes_once_per_canonical_call_and_omits_standalone_template
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      rule
      list(X): X | list(X) X
      start: list(NUM) list(NUM)
      end
    GRAMMAR
    helpers = grammar.nonterminals.select { |symbol| symbol.name.start_with?("$parameter_") }
    assert_equal 1, helpers.length
    assert_nil grammar.symbol("list")

    productions = grammar.productions.select { |production| production.lhs == helpers.first.id }
    assert_equal 2, productions.length
    productions.each do |production|
      assert_equal({ rule: "list", arguments: ["NUM"] }, production.expansion.fetch(:parameter))
      assert_empty production.expansion.fetch(:include_chain)
    end
  end

  def test_direct_and_mutual_recursion_terminate_through_the_memo
    direct = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      rule
      list(X): X | list(X) X
      start: list(NUM)
      end
    GRAMMAR
    direct_helpers = direct.nonterminals.select { |symbol| symbol.name.start_with?("$parameter_") }
    assert_equal 1, direct_helpers.length

    mutual = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      rule
      left(X): right(X)
      right(X): left(X) | X
      start: left(NUM)
      end
    GRAMMAR
    mutual_helpers = mutual.nonterminals.select { |symbol| symbol.name.start_with?("$parameter_") }
    assert_equal 2, mutual_helpers.length
    rules = mutual.productions.filter_map { |production| production.expansion&.dig(:parameter, :rule) }
    assert_equal({ "left" => 1, "right" => 2 }, rules.tally)
  end

  def test_nested_calls_and_ebnf_substitute_structurally
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      rule
      inner(X): X+
      outer(X): (X | inner(X))?
      start: outer(inner(NUM))
      end
    GRAMMAR
    parameter_rules = grammar.productions.filter_map { |production| production.expansion&.dig(:parameter, :rule) }
    assert_includes parameter_rules, "outer"
    assert_includes parameter_rules, "inner"
    origins = grammar.productions.map { |production| production.origin[:kind] }
    assert_includes origins, :group_expansion
    assert_includes origins, :optional_expansion
    assert_includes origins, :plus_expansion
  end

  def test_preserves_actions_named_refs_precedence_types_docs_and_locations
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM PLUS
      preclow
      left PLUS
      prechigh
      display list "number list"
      type list "Array[Integer]"
      rule
      ## Builds numbers.
      list(X): X:value { result = [value] } = PLUS
      start: list(NUM):items { result = items }
      end
    GRAMMAR
    helper = grammar.nonterminals.find { |symbol| symbol.name.start_with?("$parameter_") }
    production = grammar.productions.find { |candidate| candidate.lhs == helper.id }
    start = grammar.productions.find { |candidate| grammar.symbol_by_id(candidate.lhs).name == "start" }

    assert_specialized_metadata(grammar, helper, production, start)
  end

  def assert_specialized_metadata(grammar, helper, production, start)
    assert_equal "number list", helper.display_name
    assert_equal "Array[Integer]", helper.semantic_type
    assert_equal "Builds numbers.", helper.documentation
    assert_equal "Builds numbers.", production.documentation
    assert_equal [{ name: "value", index: 0 }], production.action.named_refs
    assert_equal [{ name: "items", index: 0 }], start.action.named_refs
    assert_equal grammar.symbol("PLUS").id, production.precedence_override
    assert_equal({ file: "parameter.y", line: 11, column: 10 }, production.origin.fetch(:loc))
    assert_equal({ file: "parameter.y", line: 12, column: 8 }, helper.location)
  end

  def test_formal_precedence_resolves_for_one_plain_symbol_argument
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      preclow
      left NUM
      prechigh
      rule
      select(X): X = X
      start: select(NUM)
      end
    GRAMMAR
    helper = grammar.nonterminals.find { |symbol| symbol.name.start_with?("$parameter_") }
    production = grammar.productions.find { |candidate| candidate.lhs == helper.id }

    assert_equal grammar.symbol("NUM").id, production.precedence_override
  end

  def test_include_chain_and_documentation_survive_serialization_and_schema_validation
    Dir.mktmpdir("ibex-parameter-ir") do |directory|
      root, fragment = write_parameter_fixture(directory)
      resolution = Ibex::Frontend::Resolver.new(root).resolve
      grammar = Ibex::Normalizer.new(resolution, mode: :extended).normalize
      assert_included_parameter_metadata(grammar, fragment)
      assert_parameter_serialization(grammar)
    end
  end

  def test_output_is_deterministic_and_parameter_work_is_bounded
    source = <<~GRAMMAR
      class P
      pragma extended
      token NUM
      rule
      grow(X): grow((X))
      start: grow(NUM)
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) do
      normalize(source, max_parameter_specializations: 3)
    end
    assert_equal "parameter.y:5:10: cyclic parameter specialization grow -> grow", error.message

    finite = source.sub("grow((X))", "X | grow(X)")
    assert_equal(
      Ibex::IR::Serialize.dump(normalize(finite)),
      Ibex::IR::Serialize.dump(normalize(finite))
    )
  end

  private

  def normalize(source, **options)
    ast = Ibex::Frontend::Parser.new(source, file: "parameter.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended, **options).normalize
  end

  def assert_schema_valid(document)
    v1 = JSON.parse(File.read(File.join(SCHEMA_ROOT, "grammar-ir-v1.schema.json")))
    v2 = JSON.parse(File.read(File.join(SCHEMA_ROOT, "grammar-ir-v2.schema.json")))
    schemer = JSONSchemer.schema(v2, ref_resolver: ->(uri) { v1 if uri.to_s == v1.fetch("$id") })
    assert_empty schemer.validate(document).to_a
  end

  def write_parameter_fixture(directory)
    root = File.join(directory, "root.y")
    fragment = File.join(directory, "fragment.y")
    File.write(root, <<~GRAMMAR)
      class P
      pragma extended
      include "fragment.y"
      token NUM
      rule
      start: list(NUM)
      end
    GRAMMAR
    File.write(fragment, <<~GRAMMAR)
      fragment
      type list "Array[Integer]"
      rule
      ## Included list.
      list(X): X
      end
    GRAMMAR
    [root, fragment]
  end

  def assert_included_parameter_metadata(grammar, fragment)
    helper = grammar.nonterminals.find { |symbol| symbol.name.start_with?("$parameter_") }
    production = grammar.productions.find { |candidate| candidate.lhs == helper.id }
    chain = production.expansion.fetch(:include_chain).map { |entry| entry[:file] }
    assert_equal "Included list.", production.documentation
    assert_equal [File.realpath(fragment)], chain
    assert_equal File.realpath(fragment), production.origin.dig(:loc, :file)
  end

  def assert_parameter_serialization(grammar)
    serialized = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Validator.validate(serialized)
    assert_equal serialized, Ibex::IR::Serialize.dump(loaded)
    assert_schema_valid(JSON.parse(serialized))
  end
end
