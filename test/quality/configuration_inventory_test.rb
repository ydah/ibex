# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/configuration_inventory"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

class ConfigurationInventoryTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "test/fixtures/configuration/options-v1.yml")
  DOCUMENT = File.join(ROOT, "docs/declarative-configuration.md")

  def test_repository_inventory_and_generated_document_are_current
    assert Ibex::Quality::ConfigurationInventory.new.verify!
  end

  def test_baseline_distinguishes_call_sites_runtime_registrations_and_spellings
    inventory = document
    entries = inventory.fetch("registrations")

    assert_equal 177, inventory.dig("scope", "call_site_count")
    assert_equal 186, inventory.dig("scope", "runtime_registration_count")
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

  def test_new_optionparser_registration_without_classification_fails
    with_repository_copy do |root|
      path = File.join(root, "lib/ibex/cli/new_command.rb")
      File.binwrite(path, <<~RUBY)
        module Ibex
          module NewCommand
            def new_options(parser)
              parser.on "--new-option", "must be classified"
            end
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/call_site_count drift/, error.message)
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
