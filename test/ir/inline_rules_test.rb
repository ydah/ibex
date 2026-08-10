# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"

class IRInlineRulesTest < Minitest::Test
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)

  def test_flattens_plain_parameterized_nested_and_repeated_uses
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A B
      rule
      %inline atom(X): X
      %inline pair: atom(A) B
      start: pair pair
      end
    GRAMMAR

    assert_nil grammar.symbol("atom")
    assert_nil grammar.symbol("pair")
    refute(grammar.symbols.any? { |symbol| symbol.name.start_with?("$parameter_") })
    production = grammar.productions.find { |candidate| grammar.symbol_by_id(candidate.lhs).name == "start" }
    assert_equal(%w[A B A B], production.rhs.map { |id| grammar.symbol_by_id(id).name })
    assert_equal({ rule: "pair" }, production.expansion.fetch(:inline))
    assert_equal({ rule: "atom", arguments: ["A"] }, production.expansion.fetch(:parameter))
    assert_equal 5, production.action.composition.dig(:plan, :steps).length
  end

  def test_cartesian_expansion_is_deterministic_and_bounded
    source = <<~GRAMMAR
      class P
      pragma extended
      token A B
      rule
      %inline choice: A | B
      start: choice choice choice
      end
    GRAMMAR
    first = normalize(source)
    second = normalize(source)
    assert_equal Ibex::IR::Serialize.dump(first), Ibex::IR::Serialize.dump(second)
    assert_equal 8, first.productions.length

    error = assert_raises(Ibex::Error) { normalize(source, max_inline_expansions: 7) }
    assert_equal "inline.y:6:8: inline expansion limit of 7 exceeded", error.message
  end

  def test_default_start_skips_inline_definitions
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A
      rule
      %inline helper: A
      start: helper
      end
    GRAMMAR

    assert_equal "start", grammar.start
  end

  def test_preserves_explicit_precedence
    inline = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A B
      preclow
      left A
      left B
      prechigh
      rule
      %inline helper: A = B
      start: helper
      end
    GRAMMAR
    production = inline.productions.find { |candidate| inline.symbol_by_id(candidate.lhs).name == "start" }
    assert_equal inline.symbol("B").id, production.precedence_override
  end

  def test_reduces_states_and_unresolved_conflicts_for_inline_operator
    ordinary_automaton = automaton(<<~GRAMMAR)
      class P
      token NUM
      preclow
      left '+'
      prechigh
      start expression
      rule
      operator: '+'
      expression: NUM | expression operator expression
      end
    GRAMMAR
    inline_automaton = Ibex::LALR::Builder.new(normalize(<<~GRAMMAR)).build
      class P
      pragma extended
      token NUM
      preclow
      left '+'
      prechigh
      start expression
      rule
      %inline operator: '+'
      expression: NUM | expression operator expression
      end
    GRAMMAR
    assert_operator inline_automaton.states.length, :<, ordinary_automaton.states.length
    assert_equal 1, ordinary_automaton.conflict_summary.fetch(:sr)
    assert_equal 0, inline_automaton.conflict_summary.fetch(:sr)
  end

  def test_current_round_trip_retains_executable_plan
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A
      type A "Integer"
      type helper "Integer"
      type start "String"
      rule
      %inline helper: A:value { result = value }
      start: helper { result = val[0].to_s }
      end
    GRAMMAR
    dumped = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Validator.validate(dumped)
    plan = loaded.productions.first.action.composition.fetch(:plan)
    assert_equal 1, plan.fetch(:version)
    assert_equal 1, plan.fetch(:physical)
    result_types = plan.fetch(:steps).map { |step| step[:result_type] }
    assert_equal %w[Integer String], result_types
    assert_schema_valid(JSON.parse(dumped))

  end

  def test_current_validator_rejects_composition_slots_that_are_not_yet_available
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A
      rule
      %inline helper: A
      start: helper
      end
    GRAMMAR
    document = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    step = document.fetch("productions").first.dig("action", "composition", "plan", "steps").first
    step.fetch("inputs")[0] = 99

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_includes error.message, "must reference an available slot"
  end

  def test_current_validator_accepts_missing_result_type_as_optional
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token A
      type A "Integer"
      type helper "Integer"
      type start "String"
      rule
      %inline helper: A { result = val[0] }
      start: helper { result = val[0].to_s }
      end
    GRAMMAR
    document = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    steps = document.fetch("productions").first.dig("action", "composition", "plan", "steps")
    result_types_present = steps.all? { |step| step.key?("result_type") }
    assert result_types_present
    step = steps.first
    step.delete("result_type")

    loaded = Ibex::IR::Validator.validate(JSON.generate(document))
    loaded_step = loaded.productions.first.action.composition.dig(:plan, :steps).first
    refute loaded_step.key?(:result_type)
    assert_schema_valid(JSON.parse(Ibex::IR::Serialize.dump(loaded)))
    signature = Ibex::Codegen::RBS.new(Ibex::LALR::Builder.new(loaded).build).generate
    assert_includes signature, "private def _ibex_inline_fragment_0_0: ([Integer], Array[untyped], [untyped], " \
                               "Array[untyped], Ibex::Runtime::LocationSpan?) -> untyped"
    assert_includes signature, "private def _ibex_inline_fragment_0_1: ([untyped], Array[untyped], [untyped], " \
                               "Array[untyped], Ibex::Runtime::LocationSpan?) -> String"
  end

  def test_inline_type_is_retained_for_composition_but_eliminated_display_is_rejected
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        pragma extended
        display helper "unused label"
        rule
        %inline helper: A
        start: helper
        end
      GRAMMAR
    end

    assert_includes error.message, "display declaration references undefined symbol helper"
  end

  private

  def normalizer(source, **options)
    ast = Ibex::Frontend::Parser.new(source, file: "inline.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended, **options)
  end

  def normalize(source, **options)
    normalizer(source, **options).normalize
  end

  def automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "ordinary.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def assert_schema_valid(document)
    foundation = JSON.parse(File.read(File.join(SCHEMA_ROOT, "grammar-ir-foundation.schema.json")))
    extensions = JSON.parse(File.read(File.join(SCHEMA_ROOT, "grammar-ir-extensions.schema.json")))
    current = JSON.parse(File.read(File.join(SCHEMA_ROOT, "grammar-ir.schema.json")))
    schemer = JSONSchemer.schema(
      current,
      ref_resolver: lambda do |uri|
        { foundation.fetch("$id") => foundation, extensions.fetch("$id") => extensions, current.fetch("$id") => current }[uri.to_s]
      end
    )
    assert_empty schemer.validate(document).to_a
  end
end
