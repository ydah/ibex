# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/configuration_inventory"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

class ConfigurationInventoryTest < Minitest::Test # rubocop:disable Metrics/ClassLength
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "test/fixtures/configuration/options-v1.yml")
  DOCUMENT = File.join(ROOT, "docs/declarative-configuration.md")
  WATCH_REGISTRATION =
    'options.on("--watch", "regenerate file outputs when grammar sources change") { @options[:watch] = true }'

  def test_repository_inventory_and_generated_document_are_current
    assert Ibex::Quality::ConfigurationInventory.new.verify!
  end

  def test_baseline_distinguishes_call_sites_runtime_registrations_and_spellings
    inventory = document
    entries = inventory.fetch("registrations")

    assert_equal 177, inventory.dig("scope", "call_site_count")
    assert_equal 186, inventory.dig("scope", "runtime_registration_count")
    assert_equal ["exe/*", "lib/**/*.rb"], inventory.dig("scope", "source_globs")
    assert_equal(205, entries.sum { |entry| entry.fetch("effective_spellings").length })

    fix = entries.select { |entry| entry.fetch("method") == "add_fix_budget_options" }
    imports = entries.select { |entry| entry.fetch("method") == "add_bison_import_budgets" }
    assert_equal 7, fix.length
    assert_equal 4, imports.length
    assert((fix + imports).all? { |entry| entry.fetch("declared_spellings") == ["--\#{name}=N"] })
    assert((fix + imports).all? { |entry| entry.fetch("context_sha256").match?(/\A[0-9a-f]{64}\z/) })
  end

  def test_aliases_and_first_wave_owner_decisions_share_canonical_concepts
    entries = document.fetch("registrations")
    debug = find_entry(entries, "generate", "--debug")
    obsolete_debug = find_entry(entries, "generate", "-g")
    assert_equal "build.debug", debug.fetch("canonical_key")
    assert_equal debug.fetch("canonical_key"), obsolete_debug.fetch("canonical_key")
    assert_equal "obsolete_alias", obsolete_debug.fetch("compatibility_status")

    save = find_entry(entries, "fuzz", "--save-regression")
    assert_equal %w[--save-regression --no-save-regression], save.fetch("effective_spellings")

    assert_contract(entries, "generate", "--mode=MODE", "grammar.mode", "staged_fixed_compatibility")
    assert_contract(entries, "generate", "--superclass=CLASS", "parser.superclass", "staged_fixed_compatibility")
    assert_contract(entries, "generate", "--no-omit-actions", "actions.omit_calls", "staged_fixed_compatibility")
    assert_contract(entries, "generate", "--algorithm=NAME", "parser.algorithm", "fixed")
    assert_contract(entries, "generate", "--entry-isolation", "parser.entries", "fixed")
    assert_contract(entries, "generate", "--cst-trivia=POLICY", "cst.trivia", "fixed")

    assert_equal "project_build_policy", find_entry(entries, "generate", "--table=FORMAT").fetch("owner_class")
    assert_equal "project_build_policy", find_entry(entries, "generate", "--embedded").fetch("owner_class")
    assert_equal "invocation_request", find_entry(entries, "generate", "--watch").fetch("owner_class")
    coverage = find_entry(entries, "test", "--coverage=PERCENT")
    assert_equal "invocation_request", coverage.fetch("owner_class")
    assert_equal "deferred_a5_minimum_undefined", coverage.fetch("grammar_admission")
  end

  def test_internal_compatibility_and_external_command_trust_are_explicit
    entries = document.fetch("registrations")
    assert_equal "compatibility.profiling", find_entry(entries, "generate", "-P").fetch("canonical_key")
    assert_equal "compatibility.debug_flags", find_entry(entries, "generate", "-D FLAGS").fetch("canonical_key")
    assert_includes find_entry(entries, "reduce", "--command=COMMAND").fetch("trust_implications"),
                    "bounded subprocess"
    assert_includes find_entry(entries, "fuzz", "--against=COMMAND").fetch("trust_implications"),
                    "bounded subprocess"
  end

  def test_semantic_domains_and_nonpersistent_invocation_controls_are_exact
    entries = document.fetch("registrations")
    emit = find_entry(entries, "generate", "--emit=FORMAT")
    assert_equal "string", emit.fetch("source_value_type")
    assert_equal "enum", emit.fetch("value_type")
    assert_equal "ast | sets | lexer-ir | grammar-ir | automaton-ir | ruby", emit.fetch("value_domain")

    language = find_entry(entries, "global", "--lang=LANG")
    assert_equal "enum", language.fetch("value_type")
    assert_equal "en | ja", language.fetch("value_domain")
    assert_includes language.fetch("default"), "normalized IBEX_LANG"
    assert_includes language.fetch("default"), "falling back to en"
    assert_includes language.fetch("trust_implications"), "non-reproducible"

    warnings = find_entry(entries, "generate", "--warnings=CATEGORIES")
    assert_equal "unset; warnings are neither displayed nor promoted to errors", warnings.fetch("default")

    counterexamples = find_entry(entries, "generate", "--counterexamples")
    assert_equal "excluded_x1_operation", counterexamples.fetch("grammar_admission")
    %w[equiv fuzz samples].each do |surface|
      seed = find_entry(entries, surface, "--seed=N")
      assert_equal "excluded_x1_operation", seed.fetch("grammar_admission")
      assert_equal "invocation_only", seed.fetch("override_algebra")
    end
  end

  def test_rejects_missing_duplicate_reordered_or_unclassified_records
    changed = document
    changed.fetch("registrations").pop
    assert_invalid(changed, "coverage drift")

    changed = document
    changed.fetch("registrations") << changed.fetch("registrations").first.dup
    changed.fetch("registrations").sort_by! { |entry| entry.fetch("id") }
    assert_invalid(changed, "duplicate registrations")

    changed = document
    changed.fetch("registrations").rotate!
    assert_invalid(changed, "deterministic id order")

    changed = document
    changed.fetch("registrations").first["canonical_key"] = "UNCLASSIFIED"
    assert_invalid(changed, "unclassified canonical key")
  end

  def test_rejects_source_alias_and_dynamic_expansion_drift_without_loading_cli
    with_repository_copy do |root|
      path = File.join(root, "lib/ibex/cli.rb")
      source = File.binread(path).sub('options.on("--watch",', 'options.on("-w", "--watch",')
      File.binwrite(path, source)
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/(?:coverage|declaration_sha256|declared_spellings) drift/, error.message)
    end

    with_repository_copy do |root|
      path = File.join(root, "lib/ibex/cli/fix.rb")
      source = File.binread(path).sub(
        '"max-candidates" => :max_candidates,',
        '"extra-budget" => :max_candidates, "max-candidates" => :max_candidates,'
      )
      File.binwrite(path, source)
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/runtime_registration_count drift/, error.message)
    end
  end

  def test_effective_aliases_boolean_forms_and_surfaces_are_source_bound
    changed = document
    debug = find_entry(changed.fetch("registrations"), "generate", "--debug")
    debug.fetch("effective_spellings").delete("-t")
    assert_invalid(changed, "effective_spellings drift")

    changed = document
    save = find_entry(changed.fetch("registrations"), "fuzz", "--save-regression")
    save["effective_spellings"] = ["--save-regression"]
    assert_invalid(changed, "effective_spellings drift")

    changed = document
    find_entry(changed.fetch("registrations"), "generate", "--watch")["surface"] = "global"
    assert_invalid(changed, "surface drift")
  end

  def test_every_optionparser_registration_api_is_detected
    Ibex::Quality::ConfigurationInventory::REGISTRATION_APIS.each do |api|
      with_watch_registration("options.#{api}(\"--watch\", \"changed\")") do |root|
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/(?:registration_api|declaration_sha256) drift/, error.message, api)
      end
    end
  end

  def test_receiver_and_argument_syntax_cannot_bypass_static_inventory
    variants = {
      "implicit parenthesized" => 'on("--watch", "changed")',
      "explicit nonparenthesized" => 'options.on "--watch", "changed"',
      "implicit nonparenthesized" => 'on "--watch", "changed"',
      "direct receiver" => 'OptionParser.new.on("--watch", "changed")'
    }
    variants.each do |label, replacement|
      with_watch_registration(replacement) do |root|
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/(?:declaration_sha256|declared_spellings) drift/, error.message, label)
      end
    end

    ["options.on(*switches)", "options.on(*[\"--watch\", \"changed\"])", "options.on(switches)"].each do |replacement|
      with_watch_registration(replacement) do |root|
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/(?:splat is statically unresolved|has no static spelling)/, error.message, replacement)
      end
    end
  end

  def test_unresolved_define_receivers_and_optionparser_subclasses_fail_closed
    with_repository_copy do |root|
      write_ruby(root, "lib/dynamic_options.rb", <<~RUBY)
        require "optparse"
        def dynamic_options(switch_name)
          unusual_receiver = OptionParser.new
          unusual_receiver.define(switch_name)
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/OptionParser define has no static spelling/, error.message)
    end

    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_options.rb", <<~RUBY)
        require "optparse"
        class SubclassOptions < OptionParser
          def add_dynamic(switch_name)
            define(switch_name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/OptionParser define has no static spelling/, error.message)
    end
  end

  def test_reflective_optionparser_registration_is_prohibited
    variants = {
      "send symbol" => 'options.send(:on, "--watch", "changed")',
      "public_send string" => 'options.public_send("define_tail", "--watch", "changed")',
      "public_send nonparenthesized" => 'options.public_send :on_tail, "--watch", "changed"',
      "method call" => 'options.method(:def_option).call("--watch", "changed")',
      "implicit method call" => 'method(:on).call("--watch", "changed")',
      "unresolved send" => "options.send(registration_api, switch_name)",
      "unresolved method call" => "options.method(registration_api).call(switch_name)",
      "direct constructor" => 'OptionParser.new.public_send(:on_head, "--hidden")'
    }
    variants.each do |label, registration|
      with_watch_registration(registration) do |root|
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/reflective OptionParser registration .* is prohibited/, error.message, label)
      end
    end
  end

  def test_unrelated_event_and_definition_dsls_are_not_registrations
    with_repository_copy do |root|
      write_ruby(root, "lib/unrelated_dsls.rb", <<~RUBY)
        def subscribe(stream, event_name)
          stream.on("data")
          stream.on(event_name)
        end

        def define_record(schema, name)
          schema.define("record")
          schema.define(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_source_proven_optionparser_receivers_reject_dynamic_spellings
    variants = {
      "local" => <<~RUBY,
        parser = OptionParser.new
        parser.on(switch_name)
      RUBY
      "local alias" => <<~RUBY,
        original = OptionParser.new
        parser = original
        parser.define(switch_name)
      RUBY
      "block parameter" => <<~RUBY
        OptionParser.new do |registry|
          registry.def_tail_option(switch_name)
        end
      RUBY
    }
    variants.each do |label, registration|
      with_repository_copy do |root|
        write_ruby(root, "lib/dynamic_option_parser.rb", <<~RUBY)
          require "optparse"
          def dynamic_option_parser(switch_name)
            #{registration}
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/OptionParser .* has no static spelling/, error.message, label)
      end
    end
  end

  def test_closed_owner_and_compatibility_policy_rejects_cross_field_contradictions
    mutate_entry("generate", "--watch", "grammar_admission", "admitted_a1_a8", "invocation request fields")
    mutate_entry("generate", "--watch", "manifest_presence", "current", "invocation request fields")
    mutate_entry("generate", "--table=FORMAT", "ir_presence", "grammar_ir_v2_current", "project build policy")
    mutate_entry("generate", "--table=FORMAT", "grammar_admission", "excluded_x1_operation", "project build policy")
    mutate_entry("generate", "--algorithm=NAME", "manifest_presence", "not_applicable", "manifest state")
    mutate_entry("generate", "--mode=MODE", "ir_presence", "cst_contract_gap", "persistence is inconsistent")
    mutate_entry("generate", "--manifest[=FILE]", "manifest_presence", "current", "project build policy")
    mutate_entry("generate", "--mode=MODE", "compatibility_status", "current", "staged fixed override")
    mutate_entry("generate", "--watch", "compatibility_status", "internal_compatibility", "internal compatibility")
    mutate_entry("generate", "-P", "compatibility_status", "current", "must remain internal compatibility")

    changed = document
    find_entry(changed.fetch("registrations"), "generate", "--debug")["compatibility_status"] = "obsolete_alias"
    assert_invalid(changed, "must point to a canonical registration")

    changed = document
    coverage = find_entry(changed.fetch("registrations"), "test", "--coverage=PERCENT")
    coverage["owner_class"] = "grammar_minimum"
    coverage["override_algebra"] = "minimum"
    assert_invalid(changed, "grammar minimum policy fields")
  end

  def test_new_optionparser_registration_without_classification_fails
    with_repository_copy do |root|
      path = "lib/new_command.rb"
      write_ruby(root, path, <<~RUBY)
        require "optparse"
        module Ibex
          module NewCommand
            def new_options(parser)
              parser.on "--new-option", "must be classified"
            end
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/no reviewed command surface mapping/, error.message)
    end
  end

  def test_document_rendering_is_deterministic_and_staleness_fails
    inventory = Ibex::Quality::ConfigurationInventory.new
    assert_equal inventory.render, inventory.render

    Dir.mktmpdir("ibex-configuration-document") do |directory|
      changed = File.join(directory, "declarative-configuration.md")
      File.binwrite(changed, "stale\n")
      error = assert_raises(RuntimeError) do
        Ibex::Quality::ConfigurationInventory.new(document: changed).verify!
      end
      assert_match(/documentation is stale/, error.message)
    end
  end

  private

  def document
    JSON.parse(JSON.generate(YAML.safe_load_file(REGISTRY, aliases: false)))
  end

  def find_entry(entries, surface, spelling)
    entries.find do |entry|
      entry.fetch("surface") == surface && entry.fetch("effective_spellings").include?(spelling)
    end || flunk("missing #{surface} #{spelling}")
  end

  def assert_contract(entries, surface, spelling, key, algebra)
    entry = find_entry(entries, surface, spelling)
    assert_equal key, entry.fetch("canonical_key")
    assert_equal "grammar_contract", entry.fetch("owner_class")
    assert_equal "admitted_a1_a8", entry.fetch("grammar_admission")
    assert_equal algebra, entry.fetch("override_algebra")
  end

  def assert_invalid(changed, message)
    Dir.mktmpdir("ibex-configuration-inventory") do |directory|
      registry = File.join(directory, "options.yml")
      File.binwrite(registry, YAML.dump(JSON.parse(JSON.generate(changed))))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::ConfigurationInventory.new(registry: registry).verify!
      end
      assert_includes error.message, message
    end
  end

  def mutate_entry(surface, spelling, field, value, message)
    changed = document
    find_entry(changed.fetch("registrations"), surface, spelling)[field] = value
    assert_invalid(changed, message)
  end

  def with_watch_registration(replacement)
    with_repository_copy do |root|
      path = File.join(root, "lib/ibex/cli.rb")
      source = File.binread(path)
      raise "watch registration fixture drift" unless source.include?(WATCH_REGISTRATION)

      File.binwrite(path, source.sub(WATCH_REGISTRATION, replacement))
      yield root
    end
  end

  def write_ruby(root, relative, source)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
  end

  def with_repository_copy
    Dir.mktmpdir("ibex-configuration-source") do |root|
      FileUtils.mkdir_p(File.join(root, "lib/ibex"))
      FileUtils.cp(File.join(ROOT, "lib/ibex/cli.rb"), File.join(root, "lib/ibex/cli.rb"))
      FileUtils.cp_r(File.join(ROOT, "lib/ibex/cli"), File.join(root, "lib/ibex/cli"))
      FileUtils.mkdir_p(File.join(root, "test/fixtures/configuration"))
      FileUtils.cp(REGISTRY, File.join(root, "test/fixtures/configuration/options-v1.yml"))
      FileUtils.mkdir_p(File.join(root, "docs"))
      FileUtils.cp(DOCUMENT, File.join(root, "docs/declarative-configuration.md"))
      yield root
    end
  end

  def inventory_for(root)
    Ibex::Quality::ConfigurationInventory.new(root: root)
  end
end
