# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class IRParserContractTest < Minitest::Test
  def test_unspecified_contract_has_no_configuration_values_or_locations
    contract = Ibex::IR::ParserContract.new

    assert_equal({}, contract.configuration_values)
    assert_equal({}, contract.configuration_locations)
    contract.to_h.each_value do |entry|
      assert_equal({ value: nil, explicit: false, loc: nil }, entry)
    end
  end

  def test_explicit_contract_maps_to_typed_configuration_keys
    location = Ibex::Location.new(file: "contract.y", line: 4, column: 2)
    contract = Ibex::IR::ParserContract.new(
      algorithm: Ibex::IR::ParserContract::Entry.new(
        :algorithm, value: :ielr, location: location, explicit: true
      ),
      entries: Ibex::IR::ParserContract::Entry.new(
        :entries, value: :isolated, location: location, explicit: true
      )
    )

    assert_equal({ "parser.algorithm" => :ielr, "parser.entries" => :isolated }, contract.configuration_values)
    assert_equal(
      { "parser.algorithm" => location, "parser.entries" => location },
      contract.configuration_locations
    )
  end

  def test_unspecified_entry_rejects_a_value_even_when_it_is_the_builtin
    error = assert_raises(ArgumentError) do
      Ibex::IR::ParserContract::Entry.new(:algorithm, value: :lalr)
    end

    assert_equal "unspecified algorithm cannot carry a value", error.message
  end

  def test_explicit_entry_requires_a_source_location
    error = assert_raises(ArgumentError) do
      Ibex::IR::ParserContract::Entry.new(:entries, value: :shared, explicit: true)
    end

    assert_equal "explicit entries requires a source location with a file", error.message
  end

  def test_current_factories_are_the_public_constructors
    grammar_parameters = Ibex::IR::Grammar.instance_method(:initialize).parameters.map(&:last)
    automaton_parameters = Ibex::IR::Automaton.instance_method(:initialize).parameters.map(&:last)

    assert_includes grammar_parameters, :parser_contract
    assert_includes automaton_parameters, :entry_construction
    refute Ibex::IR::Grammar.respond_to?(:v3)
    refute Ibex::IR::Automaton.respond_to?(:v3)
  end

  def test_current_automaton_rejects_a_mismatched_grammar_digest
    automaton = automaton_fixture("automaton.json")

    error = assert_raises(Ibex::Error) do
      rebuild_automaton(automaton, grammar_digest: "sha256:#{'0' * 64}")
    end

    assert_match(/\A\(ir\):1:1: \$\.grammar_digest does not match the embedded grammar/, error.message)
  end

  def test_current_automaton_rejects_unknown_entry_construction
    automaton = automaton_fixture("automaton.json")

    error = assert_raises(Ibex::Error) do
      rebuild_automaton(automaton, entry_construction: "unknown")
    end

    assert_equal "entry construction must be shared or isolated", error.message
  end

  private

  def automaton_fixture(name)
    path = File.expand_path("../fixtures/ir/#{name}", __dir__)
    Ibex::IR::Validator.validate(File.binread(path))
  end

  def rebuild_automaton(automaton, entry_construction: automaton.entry_construction, grammar_digest: nil)
    Ibex::IR::Automaton.new(
      grammar: automaton.grammar, states: automaton.states, conflict_summary: automaton.conflict_summary,
      algorithm: automaton.algorithm, grammar_digest: grammar_digest,
      entry_states: automaton.entry_states, entry_construction: entry_construction
    )
  end
end
