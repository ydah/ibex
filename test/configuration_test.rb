# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class ConfigurationTest < Minitest::Test # rubocop:disable Metrics/ClassLength -- one closed model contract.
  Configuration = Ibex::Configuration

  def test_registry_is_closed_and_records_required_generation_concepts
    expected = %w[
      actions.omit_calls build.debug build.executable build.frozen_strings cst.trivia grammar.mode
      parser.algorithm parser.entries parser.superclass runtime.embedded source.line_mapping table.representation
    ]

    assert_equal expected, Configuration::Registry.keys.map(&:name).sort
    assert_equal :lalr, Configuration::Registry.fetch("parser.algorithm").default
    assert_equal :shared, Configuration::Registry.fetch("parser.entries").default
    assert_equal :leading, Configuration::Registry.fetch("cst.trivia").default
    assert_raises(ArgumentError) { Configuration::Registry.fetch("parser.unknown") }
  end

  def test_builtins_are_implicit_canonical_typed_values
    configuration = Configuration::Resolver.new
    algorithm = configuration.fetch("parser.algorithm")

    assert_equal :lalr, algorithm.value
    assert_equal :grammar_contract, algorithm.key.owner
    assert_equal :fixed, algorithm.key.policy
    assert_equal :builtin, algorithm.origin.kind
    refute algorithm.explicit
    assert algorithm.canonical
    assert configuration.frozen?
    assert configuration.values.frozen?
  end

  def test_fixed_grammar_contract_accepts_matching_cli_and_retains_declaration_origin
    location = Ibex::Location.new(file: "grammar.y", line: 6, column: 3)
    configuration = Configuration::Resolver.new(
      grammar: { "parser.algorithm" => :ielr },
      cli: { "parser.algorithm" => :ielr },
      locations: { grammar: { "parser.algorithm" => location } }
    )
    algorithm = configuration.fetch("parser.algorithm")

    assert_equal :ielr, algorithm.value
    assert_equal :grammar, algorithm.origin.kind
    assert_equal location, algorithm.origin.location
    assert algorithm.explicit
    assert algorithm.canonical
  end

  def test_fixed_grammar_contract_rejects_conflicting_cli
    error = assert_raises(Configuration::Conflict) do
      Configuration::Resolver.new(
        grammar: { "parser.algorithm" => :ielr }, cli: { "parser.algorithm" => :lr1 }
      )
    end

    assert_equal "parser.algorithm", error.key.name
    assert_equal :ielr, error.declared.value
    assert_equal :lr1, error.requested.value
    assert_match(/grammar selected :ielr/, error.message)
    assert_match(/cli requested :lr1/, error.message)
  end

  def test_fixed_contract_without_grammar_rejects_project_cli_disagreement
    error = assert_raises(Configuration::Conflict) do
      Configuration::Resolver.new(
        project: { "parser.algorithm" => :ielr }, cli: { "parser.algorithm" => :lr1 }
      )
    end

    assert_equal :project, error.declared.origin.kind
    assert_equal :cli, error.requested.origin.kind
  end

  def test_fixed_contract_without_declaration_uses_cli
    configuration = Configuration::Resolver.new(cli: { "parser.algorithm" => :slr })

    assert_equal :slr, configuration.value("parser.algorithm")
    assert_equal :cli, configuration.fetch("parser.algorithm").origin.kind
  end

  def test_minimum_merge_strengthens_and_rejects_weakening
    key = Configuration::Key.new(
      "test.production_coverage", type: :integer, default: 0,
                                  owner: :grammar_minimum, policy: :minimum
    )
    configuration = Configuration::Resolver.new(
      keys: [key], grammar: { key.name => 60 }, project: { key.name => 70 }, cli: { key.name => 80 }
    )

    assert_equal 80, configuration.value(key.name)
    assert_equal :cli, configuration.fetch(key.name).origin.kind
    error = assert_raises(Configuration::Conflict) do
      Configuration::Resolver.new(keys: [key], grammar: { key.name => 60 }, cli: { key.name => 59 })
    end
    assert_equal 60, error.declared.value
    assert_equal 59, error.requested.value
  end

  def test_analysis_override_is_explicit_noncanonical_and_reports_both_values
    configuration = Configuration::Resolver.new(
      grammar: { "parser.algorithm" => :ielr }, analysis_overrides: { "parser.algorithm" => :lr1 }
    )
    algorithm = configuration.fetch("parser.algorithm")
    evidence = algorithm.to_h

    assert_equal :lr1, algorithm.value
    assert_equal :analysis_override, algorithm.origin.kind
    assert algorithm.explicit
    refute algorithm.canonical
    assert_equal(
      {
        "declared" => "ielr", "selected" => "lr1", "override" => true,
        "canonical_generation" => false
      },
      evidence.fetch("analysis")
    )
  end

  def test_evidence_json_is_deterministic_and_sorted_by_canonical_key
    first = Configuration::Resolver.new(
      cli: { "table.representation" => :plain, "parser.algorithm" => :lr1 }
    )
    second = Configuration::Resolver.new(
      cli: { "parser.algorithm" => :lr1, "table.representation" => :plain }
    )
    document = JSON.parse(first.dump)

    assert_equal first.dump, second.dump
    assert_equal(
      Configuration::Registry.keys.map(&:name).sort,
      document.fetch("configuration").map { |entry| entry.fetch("key") }
    )
    assert first.dump.end_with?("\n")
  end

  def test_evidence_includes_source_location_with_string_keys
    location = Ibex::Location.new(file: "grammar.y", line: 7, column: 5, end_line: 7, end_column: 9)
    configuration = Configuration::Resolver.new(
      grammar: { "parser.entries" => :isolated },
      locations: { grammar: { "parser.entries" => location } }
    )
    origin = configuration.fetch("parser.entries").to_h.fetch("origin")

    assert_equal "grammar", origin.fetch("kind")
    assert_equal(
      { "file" => "grammar.y", "line" => 7, "column" => 5, "end_line" => 7, "end_column" => 9 },
      origin.fetch("location")
    )
  end

  def test_invalid_key_and_origin_metadata_are_rejected
    assert_raises(ArgumentError) do
      Configuration::Key.new("Algorithm", type: :symbol, default: :lalr,
                                          owner: :grammar_contract, policy: :fixed)
    end
    assert_raises(ArgumentError) do
      Configuration::Key.new("parser.valid", type: :symbol, default: :lalr,
                                             owner: :grammar_contract, policy: :build)
    end
    assert_raises(ArgumentError) { Configuration::Origin.new(:environment) }
    assert_raises(ArgumentError) { Configuration::Origin.new(:grammar, location: "grammar.y:1:1") }
    assert_raises(ArgumentError) do
      Configuration::Origin.new(:cli, location: Ibex::Location.new(line: 1, column: 1))
    end
  end

  def test_value_constructor_rejects_untyped_provenance_fields
    key = Configuration::Registry.fetch("parser.algorithm")
    builtin = Configuration::Origin.new(:builtin)

    assert_raises(ArgumentError) do
      Configuration::Value.new("parser.algorithm", :lalr, origin: builtin, explicit: false, canonical: true)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: :builtin, explicit: false, canonical: true)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: builtin, explicit: "no", canonical: true)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: builtin, explicit: false, canonical: nil)
    end
  end

  def test_value_constructor_rejects_incoherent_origin_and_explicitness
    key = Configuration::Registry.fetch("parser.algorithm")
    builtin = Configuration::Origin.new(:builtin)
    cli = Configuration::Origin.new(:cli)
    override = Configuration::Origin.new(:analysis_override)

    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: builtin, explicit: true, canonical: true)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: cli, explicit: false, canonical: true)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lalr, origin: override, explicit: true, canonical: true)
    end
  end

  def test_value_constructor_requires_coherent_declared_evidence
    key = Configuration::Registry.fetch("parser.algorithm")
    cli = Configuration::Origin.new(:cli)
    override = Configuration::Origin.new(:analysis_override)

    assert_raises(ArgumentError) do
      Configuration::Value.new(
        key, :lr1, origin: cli, explicit: true, canonical: false, declared_value: :lalr
      )
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(key, :lr1, origin: override, explicit: true, canonical: false)
    end
    assert_raises(ArgumentError) do
      Configuration::Value.new(
        key, :lalr, origin: cli, explicit: true, canonical: true, declared_value: nil
      )
    end

    build_key = Configuration::Registry.fetch("table.representation")
    assert_raises(ArgumentError) do
      Configuration::Value.new(
        build_key, :plain, origin: override, explicit: true, canonical: false, declared_value: :compact
      )
    end
  end

  def test_noncanonical_optional_nil_declaration_is_present_in_evidence
    value = Configuration::Resolver.new(
      analysis_overrides: { "parser.superclass" => "ExperimentParser" }
    ).fetch("parser.superclass")

    assert_nil value.declared_value
    assert_nil value.to_h.fetch("analysis").fetch("declared")
    assert_equal "ExperimentParser", value.to_h.fetch("analysis").fetch("selected")
  end

  def test_value_and_resolver_enforce_owner_source_combinations
    build_key = Configuration::Registry.fetch("table.representation")
    assert_raises(ArgumentError) do
      Configuration::Value.new(
        build_key, :plain, origin: Configuration::Origin.new(:grammar), explicit: true, canonical: true
      )
    end

    invocation_key = Configuration::Key.new(
      "test.output_mode", type: :symbol, default: :normal,
                          owner: :invocation, policy: :invocation, allowed_values: %i[normal quiet]
    )
    assert_raises(ArgumentError) do
      Configuration::Value.new(
        invocation_key, :quiet, origin: Configuration::Origin.new(:project), explicit: true, canonical: true
      )
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(keys: [invocation_key], project: { invocation_key.name => :quiet })
    end
  end

  def test_invalid_values_locations_and_overrides_are_rejected
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(cli: { "parser.algorithm" => "lalr" })
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(cli: { "parser.algorithm" => :unknown })
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(cli: { "unknown.key" => true })
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(locations: { environment: {} })
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(
        locations: { grammar: { "parser.algorithm" => Ibex::Location.new(line: 1, column: 1) } }
      )
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(analysis_overrides: { "table.representation" => :plain })
    end
    assert_raises(ArgumentError) do
      Configuration::Resolver.new(analysis_overrides: { "parser.algorithm" => :lalr })
    end
  end

  def test_duplicate_key_definitions_are_rejected
    key = Configuration::Registry.fetch("parser.algorithm")

    assert_raises(ArgumentError) { Configuration::Resolver.new(keys: [key, key]) }
  end

  def test_strings_and_adapter_inputs_are_defensively_copied
    superclass = +"BaseParser"
    options = { superclass: superclass }
    explicit = [:superclass]
    adapter = Configuration::CLIAdapter.new(options, explicit_keys: explicit)
    superclass.replace("Changed")
    options[:superclass] = "Other"
    explicit.clear
    value = adapter.resolve.fetch("parser.superclass").value

    assert_equal "BaseParser", value
    assert value.frozen?
  end

  def test_cli_adapter_normalizes_legacy_internal_shapes
    configuration = Configuration::CLIAdapter.new(
      {
        entry_isolation: true, cst_trivia: :attach, line_convert: true, line_convert_all: true,
        algorithm: :ielr, mode: :extended
      }
    ).resolve

    assert_equal :isolated, configuration.value("parser.entries")
    assert_equal :leading, configuration.value("cst.trivia")
    assert_equal :all, configuration.value("source.line_mapping")
    assert_equal :ielr, configuration.value("parser.algorithm")
    assert_equal :extended, configuration.value("grammar.mode")
  end

  def test_cli_adapter_resolves_persisted_grammar_contract_with_locations
    location = Ibex::Location.new(file: "contract.y", line: 3, column: 5)
    configuration = Configuration::CLIAdapter.new({ algorithm: :ielr }).resolve(
      grammar: { "parser.algorithm" => :ielr },
      locations: { "parser.algorithm" => location }
    )

    algorithm = configuration.fetch("parser.algorithm")
    assert_equal :ielr, algorithm.value
    assert_equal :grammar, algorithm.origin.kind
    assert_equal location, algorithm.origin.location
  end

  def test_cli_adapter_rejects_a_cli_conflict_with_persisted_grammar_contract
    error = assert_raises(Configuration::Conflict) do
      Configuration::CLIAdapter.new({ algorithm: :lr1 }).resolve(
        grammar: { "parser.algorithm" => :ielr }
      )
    end

    assert_equal :ielr, error.declared.value
    assert_equal :lr1, error.requested.value
  end

  def test_cli_adapter_accepts_line_convert_all_without_synthetic_line_convert
    configuration = Configuration::CLIAdapter.new({ line_convert_all: true }).resolve

    assert_equal :all, configuration.value("source.line_mapping")
    assert_equal :cli, configuration.fetch("source.line_mapping").origin.kind
    assert configuration.fetch("source.line_mapping").explicit
  end

  def test_cli_adapter_validates_every_explicit_line_conversion_shape
    assert_equal(
      :actions,
      Configuration::CLIAdapter.new({ line_convert_all: false }).resolve.value("source.line_mapping")
    )
    assert_equal(
      :none,
      Configuration::CLIAdapter.new({ line_convert: false, line_convert_all: false })
                               .resolve.value("source.line_mapping")
    )
    assert_raises(ArgumentError) do
      Configuration::CLIAdapter.new({ line_convert: false, line_convert_all: true }).resolve
    end
    assert_raises(ArgumentError) do
      Configuration::CLIAdapter.new({ line_convert: "yes" }).resolve
    end
    assert_raises(ArgumentError) do
      Configuration::CLIAdapter.new({ line_convert_all: "yes" }).resolve
    end
  end

  def test_cli_adapter_rejects_invalid_boolean_shapes
    assert_raises(ArgumentError) do
      Configuration::CLIAdapter.new({ entry_isolation: "yes" }).resolve
    end
    assert_raises(ArgumentError) do
      Configuration::CLIAdapter.new({ line_convert: true, line_convert_all: "yes" }).resolve
    end
  end

  def test_cli_defaults_are_implicit_even_though_the_legacy_hash_contains_them
    cli = Ibex::CLI.new(stdout: StringIO.new, stderr: StringIO.new)
    configuration = cli.__send__(:effective_configuration)

    %w[grammar.mode table.representation source.line_mapping].each do |name|
      assert_equal :builtin, configuration.fetch(name).origin.kind
      refute configuration.fetch(name).explicit
    end
  end

  def test_legacy_line_mapping_defaults_remain_implicit
    configuration = Configuration::CLIAdapter.new(
      { line_convert: true }, explicit_keys: []
    ).resolve.fetch("source.line_mapping")

    assert_equal :actions, configuration.value
    assert_equal :builtin, configuration.origin.kind
    refute configuration.explicit
  end

  def test_explicit_cli_default_is_not_mistaken_for_an_implicit_default
    cli = Ibex::CLI.new(stdout: StringIO.new, stderr: StringIO.new)
    parser = cli.__send__(:option_parser)
    parser.parse(["--mode=default", "--table=compact"])
    configuration = cli.__send__(:effective_configuration)

    assert_equal :cli, configuration.fetch("grammar.mode").origin.kind
    assert_equal :cli, configuration.fetch("table.representation").origin.kind
    assert configuration.fetch("grammar.mode").explicit
    assert configuration.fetch("table.representation").explicit
  end

  def test_configuration_resolution_does_not_read_or_execute_user_code
    File.stub(:binread, ->(*) { flunk("configuration must not read source files") }) do
      Kernel.stub(:load, ->(*) { flunk("configuration must not load user code") }) do
        assert_equal :lalr, Configuration::CLIAdapter.new({}).resolve.value("parser.algorithm")
      end
    end
  end
end
