# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"

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

  def test_closed_contract_definitions_are_deeply_frozen
    definitions = Ibex::IR::ParserContract::DEFINITIONS
    algorithm = definitions.fetch(:algorithm)

    assert definitions.frozen?
    assert algorithm.frozen?
    assert algorithm.fetch(:configuration).frozen?
    assert algorithm.fetch(:values).frozen?
    assert_raises(FrozenError) { algorithm[:future] = true }
    assert_raises(FrozenError) { algorithm.fetch(:configuration) << ".changed" }
    assert_raises(FrozenError) { algorithm.fetch(:values) << :future }
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

  def test_v3_grammar_factory_rejects_forged_current_schema_migration
    grammar = automaton_fixture("automaton-v2-migrated-v3.json").grammar
    forged = { from_schema_version: 3, unavailable: ["effective_parser_entries"] }

    error = assert_raises(Ibex::Error) { rebuild_v3_grammar(grammar, migration: forged) }

    assert_equal "(ir):1:1: $.migration.from_schema_version must be 1 or 2", error.message
  end

  def test_v3_grammar_factory_preserves_valid_migration_metadata
    grammar = automaton_fixture("automaton-v2-migrated-v3.json").grammar

    rebuilt = rebuild_v3_grammar(grammar, migration: grammar.migration)
    validated = Ibex::IR::Validator.validate(Ibex::IR::Serialize.dump(rebuilt))

    assert_equal grammar.migration, rebuilt.migration
    assert_equal grammar.migration, validated.migration
  end

  def test_direct_grammar_ir_require_preserves_migration_validation
    script = <<~RUBY
      require "ibex/ir/grammar_ir"

      begin
        Ibex::IR::Grammar.v3(
          class_name: "Parser", superclass: nil, start: "start", expect: 0,
          options: { result_var: false, omit_action_call: false }, symbols: [], productions: [],
          user_code: {}, conversions: {}, warnings: [],
          migration: { from_schema_version: 3, unavailable: ["effective_parser_entries"] }
        )
      rescue Ibex::Error => error
        puts error.message
      end
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", "-e", script
    )

    assert_predicate status, :success?, stderr
    assert_equal "(ir):1:1: $.migration.from_schema_version must be 1 or 2\n", stdout
  end

  def test_direct_migration_require_loads_the_shared_inventory
    script = <<~RUBY
      require "ibex/ir/migration"
      puts Ibex::IR::Migration::UNAVAILABLE_V1_METADATA.first
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", "-e", script
    )

    assert_predicate status, :success?, stderr
    assert_equal "source_provenance\n", stdout
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

  def rebuild_v3_grammar(grammar, migration: grammar.migration)
    Ibex::IR::Grammar.v3(
      class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
      expect: grammar.expect, options: grammar.options, symbols: grammar.symbols,
      productions: grammar.productions, user_code: grammar.user_code, conversions: grammar.conversions,
      warnings: grammar.warnings, expect_rr: grammar.expect_rr, user_code_chunks: grammar.user_code_chunks,
      source_provenance: grammar.source_provenance, migration: migration,
      parser_parameters: grammar.parser_parameters, value_printers: grammar.value_printers,
      grammar_tests: grammar.grammar_tests, recovery: grammar.recovery, lexer: grammar.lexer,
      mode: grammar.mode, starts: grammar.starts, parser_contract: grammar.parser_contract
    )
  end
end
