# frozen_string_literal: true

require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- the mutation matrix shares one document-construction harness.
class VerifyVerifierTest < Minitest::Test
  GALLERY_ALGORITHMS = %i[slr lalr ielr lr1].freeze
  FAULTS = %i[
    add_lookahead
    remove_item
    remove_lookahead
    move_item_dot
    remove_transition
    redirect_transition
    remove_action
    redirect_shift
    replace_reduction
    remove_goto
    redirect_goto
    add_default
    remove_default
    remove_error_mask
    remove_conflict
    duplicate_conflict
    redirect_conflict_shift
    change_conflict_choice
    add_unreachable_state
    epsilon_cycle
  ].freeze

  def test_all_gallery_automata_pass_default_and_strict_verification
    Dir.glob(File.expand_path("../../gallery/*/grammar.y", __dir__)).each do |path|
      grammar = normalize(File.binread(path), file: path)
      GALLERY_ALGORITHMS.each do |algorithm|
        automaton = Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build

        [false, true].each do |strict|
          result = Ibex::Verify::Verifier.new(automaton, strict: strict).verify
          assert result.valid?,
                 "#{path} #{algorithm} strict=#{strict}: #{result.violations.map(&:to_h).inspect}"
        end
      end
    end
  end

  def test_twenty_structurally_valid_fault_types_are_all_detected
    assert_equal 20, FAULTS.length

    FAULTS.each do |fault|
      document = fault == :epsilon_cycle ? epsilon_document : calculator_document
      inject_fault(document, fault)
      automaton = Ibex::IR::Validator.validate(JSON.generate(document))
      assert_instance_of Ibex::IR::Automaton, automaton, fault

      result = Ibex::Verify::Verifier.new(automaton, strict: true).verify
      refute result.valid?, "#{fault} escaped verification"
    end
  end

  def test_epsilon_cycle_is_reported_as_a_termination_violation
    document = epsilon_document
    inject_fault(document, :epsilon_cycle)
    automaton = Ibex::IR::Validator.validate(JSON.generate(document))

    result = Ibex::Verify::Verifier.new(automaton).verify

    assert_includes result.violations.map(&:id), "V7"
  end

  def test_unreachable_state_is_reported
    document = calculator_document
    inject_fault(document, :add_unreachable_state)
    automaton = Ibex::IR::Validator.validate(JSON.generate(document))

    result = Ibex::Verify::Verifier.new(automaton).verify

    assert_includes result.violations.map(&:id), "V6"
  end

  def test_reference_implementation_does_not_reference_the_builder
    root = File.expand_path("../../lib/ibex/verify", __dir__)
    source = Dir.glob("#{root}/**/*.rb").map { |path| File.binread(path) }.join

    refute_includes source, "LALR::Builder"
    refute_includes source, "lalr/builder"
  end

  def test_multiple_entries_and_isolated_entries_preserve_augmented_item_identity
    grammar = normalize(<<~GRAMMAR, file: "entries.y")
      class EntriesParser
      pragma extended
      start program expression
      rule
      program: A B
      expression: A
      end
    GRAMMAR

    GALLERY_ALGORITHMS.product([false, true]).each do |algorithm, entry_isolation|
      automaton = Ibex::LALR::Builder.new(
        grammar, algorithm: algorithm, entry_isolation: entry_isolation
      ).build
      result = Ibex::Verify::Verifier.new(automaton, strict: true).verify

      assert result.valid?,
             "#{algorithm} entry_isolation=#{entry_isolation}: #{result.violations.map(&:to_h).inspect}"
    end
  end

  def test_reference_collection_has_explicit_state_and_item_budgets
    automaton = build_calculator

    assert_raises(Ibex::Verify::BudgetExceeded) do
      Ibex::Verify::Verifier.new(automaton, max_states: 1).verify
    end
    assert_raises(Ibex::Verify::BudgetExceeded) do
      Ibex::Verify::Verifier.new(automaton, max_items: 1).verify
    end
  end

  private

  def calculator_document
    JSON.parse(Ibex::IR::Serialize.dump(build_calculator))
  end

  def epsilon_document
    grammar = normalize(<<~GRAMMAR, file: "epsilon.y")
      class EpsilonParser
      pragma extended
      rule
      start: optional
      optional: %empty
              | TOKEN
      end
    GRAMMAR
    JSON.parse(Ibex::IR::Serialize.dump(Ibex::LALR::Builder.new(grammar).build))
  end

  def build_calculator
    path = File.expand_path("../../gallery/calc/grammar.y", __dir__)
    Ibex::LALR::Builder.new(normalize(File.binread(path), file: path)).build
  end

  def normalize(source, file:)
    ast = Ibex::Frontend::Parser.new(source, file: file, mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize -- explicit mutation inventory is auditable.
  def inject_fault(document, fault)
    case fault
    when :add_lookahead then add_lookahead(document)
    when :remove_item then state_with(document, "items")["items"].shift
    when :remove_lookahead then item_with(document) { |item| item["lookaheads"].length > 1 }["lookaheads"].shift
    when :move_item_dot then move_item_dot(document)
    when :remove_transition then state_with(document, "transitions")["transitions"].shift
    when :redirect_transition then redirect_map_value(document, "transitions")
    when :remove_action then state_with_action(document, "shift")["actions"].shift
    when :redirect_shift then redirect_action(document, "shift", "state", state_count(document))
    when :replace_reduction then redirect_action(document, "reduce", "production", production_count(document))
    when :remove_goto then state_with(document, "gotos")["gotos"].shift
    when :redirect_goto then redirect_map_value(document, "gotos")
    when :add_default then add_default(document)
    when :remove_default then state_with_default(document)["default_action"] = nil
    when :remove_error_mask then remove_error_mask(document)
    when :remove_conflict then state_with(document, "conflicts")["conflicts"].shift
    when :duplicate_conflict then duplicate_conflict(document)
    when :redirect_conflict_shift then redirect_conflict_shift(document)
    when :change_conflict_choice then change_conflict_choice(document)
    when :add_unreachable_state then add_unreachable_state(document)
    when :epsilon_cycle then add_epsilon_cycle(document)
    else raise "unknown fault #{fault}"
    end
    refresh_conflict_summary(document) if %i[remove_conflict duplicate_conflict].include?(fault)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/AbcSize

  def state_with(document, field)
    document.fetch("states").find { |state| !state.fetch(field).empty? } || raise("missing #{field}")
  end

  def state_with_action(document, type)
    document.fetch("states").find do |state|
      state.fetch("default_action").nil? &&
        state.fetch("actions").any? { |_name, action| action.fetch("type") == type }
    end || raise("missing #{type} action")
  end

  def item_with(document, &block)
    document.fetch("states").each do |state|
      item = state.fetch("items").find(&block)
      return item if item
    end
    raise "missing item"
  end

  def move_item_dot(document)
    productions = document.fetch("grammar").fetch("productions")
    item = item_with(document) do |candidate|
      id = candidate.fetch("production")
      id >= 0 && candidate.fetch("dot") < productions.fetch(id).fetch("rhs").length
    end
    item["dot"] += 1
  end

  def add_lookahead(document)
    terminals = document.fetch("grammar").fetch("symbols").filter_map do |symbol|
      symbol.fetch("name") if symbol.fetch("kind") == "terminal"
    end
    item = item_with(document) { |candidate| (terminals - candidate.fetch("lookaheads")).any? }
    item.fetch("lookaheads") << (terminals - item.fetch("lookaheads")).first
  end

  def redirect_map_value(document, field)
    state = state_with(document, field)
    key, target = state.fetch(field).first
    state.fetch(field)[key] = (target + 1) % state_count(document)
  end

  def redirect_action(document, type, field, modulus)
    state = state_with_action(document, type)
    _name, action = state.fetch("actions").find { |_token, value| value.fetch("type") == type }
    action.store(field, (action.fetch(field) + 1) % modulus)
  end

  def add_default(document)
    state = document.fetch("states").find { |candidate| candidate.fetch("default_action").nil? } || raise
    state["default_action"] = { "type" => "reduce", "production" => 0 }
  end

  def state_with_default(document)
    document.fetch("states").find { |state| state.fetch("default_action") } || raise("missing default")
  end

  def remove_error_mask(document)
    state = state_with_default(document)
    name, = state.fetch("actions").find { |_token, action| action.fetch("type") == "error" }
    raise "missing error mask" unless name

    state.fetch("actions").delete(name)
  end

  def duplicate_conflict(document)
    state = state_with(document, "conflicts")
    state.fetch("conflicts") << Marshal.load(Marshal.dump(state.fetch("conflicts").first))
  end

  def redirect_conflict_shift(document)
    conflict = conflict(document)
    conflict["shift_to"] = (conflict.fetch("shift_to") + 1) % state_count(document)
  end

  def change_conflict_choice(document)
    resolution = conflict(document).fetch("resolution")
    resolution["chose"] = resolution.fetch("chose") == "shift" ? "reduce" : "shift"
  end

  def conflict(document)
    state_with(document, "conflicts").fetch("conflicts").find do |candidate|
      candidate.fetch("type") == "shift_reduce"
    end || raise("missing shift/reduce conflict")
  end

  def add_unreachable_state(document)
    document.fetch("states") << {
      "id" => state_count(document), "items" => [], "transitions" => {},
      "actions" => {}, "gotos" => {}, "default_action" => nil, "conflicts" => []
    }
  end

  def add_epsilon_cycle(document)
    production = document.fetch("grammar").fetch("productions").find { |candidate| candidate.fetch("rhs").empty? }
    raise "missing epsilon production" unless production

    lhs = document.fetch("grammar").fetch("symbols").fetch(production.fetch("lhs")).fetch("name")
    state = document.fetch("states").first
    state["default_action"] = { "type" => "reduce", "production" => production.fetch("id") }
    state.fetch("gotos")[lhs] = state.fetch("id")
  end

  def refresh_conflict_summary(document)
    conflicts = document.fetch("states").flat_map { |state| state.fetch("conflicts") }
    shifts = conflicts.select { |conflict_value| conflict_value.fetch("type") == "shift_reduce" }
    summary = document.fetch("conflict_summary")
    summary["sr"] = shifts.count { |value| value.dig("resolution", "by") == "default_shift" }
    summary["resolved_sr"] = shifts.length - summary.fetch("sr")
    summary["rr"] = conflicts.count { |value| value.fetch("type") == "reduce_reduce" }
    summary["expectation_met"] = summary.fetch("sr") == summary.fetch("expected_sr")
  end

  def state_count(document) = document.fetch("states").length

  def production_count(document) = document.fetch("grammar").fetch("productions").length
end
# rubocop:enable Metrics/ClassLength
