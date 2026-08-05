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

  def test_v3_factories_do_not_expand_the_frozen_constructors
    grammar_constructor = Ibex::IR::Grammar.instance_method(:initialize).parameters.map(&:last)
    automaton_constructor = Ibex::IR::Automaton.instance_method(:initialize).parameters.map(&:last)
    grammar_factory = Ibex::IR::Grammar.method(:v3).parameters.map(&:last)
    automaton_factory = Ibex::IR::Automaton.method(:v3).parameters.map(&:last)

    refute_includes grammar_constructor, :parser_contract
    refute_includes automaton_constructor, :entry_construction
    assert_includes grammar_factory, :parser_contract
    assert_includes automaton_factory, :entry_construction
  end

  def test_v3_automaton_factory_rejects_unknown_entry_construction_without_migration_history
    migrated = automaton_fixture("automaton-v2-migrated-v3.json")
    grammar_document = JSON.parse(Ibex::IR::Serialize.dump(migrated.grammar))
    grammar_document.delete("migration")
    native_grammar = Ibex::IR::Serialize.load(JSON.generate(grammar_document))

    error = assert_raises(Ibex::Error) do
      rebuild_v3_automaton(migrated, grammar: native_grammar, entry_construction: "unknown")
    end

    assert_equal(
      "(ir):1:1: $.entry_construction may be unknown only for migrated unavailable history",
      error.message
    )
  end

  def test_v3_automaton_factory_rejects_a_mismatched_grammar_digest
    automaton = automaton_fixture("automaton-v3.json")

    error = assert_raises(Ibex::Error) do
      rebuild_v3_automaton(automaton, grammar_digest: "sha256:#{'0' * 64}")
    end

    assert_match(/\A\(ir\):1:1: \$\.grammar_digest does not match the embedded grammar/, error.message)
  end

  private

  def automaton_fixture(name)
    path = File.expand_path("../fixtures/ir/#{name}", __dir__)
    value = Ibex::IR::Validator.validate(File.binread(path))
    value.is_a?(Ibex::IR::Automaton) ? value : raise("expected Automaton IR fixture")
  end

  def rebuild_v3_automaton(automaton, grammar: automaton.grammar,
                           entry_construction: automaton.entry_construction, grammar_digest: nil)
    Ibex::IR::Automaton.v3(
      grammar: grammar, states: automaton.states, conflict_summary: automaton.conflict_summary,
      algorithm: automaton.algorithm, grammar_digest: grammar_digest,
      entry_states: automaton.entry_states, entry_construction: entry_construction
    )
  end
end
