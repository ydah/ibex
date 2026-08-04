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
  REVIEWER_MUTATIONS = {
    "__send__" => [<<~RUBY, /reflective OptionParser registration/],
      require "optparse"
      def hidden_option
        parser = OptionParser.new
        parser.__send__(:on,"--unclassified")
      end
    RUBY
    "bound method assignment" => [<<~RUBY, /reflective OptionParser registration/],
      require "optparse"
      def hidden_option
        parser = OptionParser.new
        register=parser.method(:on); register.call("--unclassified")
      end
    RUBY
    "constant" => [<<~RUBY, /has no static spelling/],
      require "optparse"
      PARSER=OptionParser.new
      def hidden_option(dynamic_name)
        PARSER.on(dynamic_name)
      end
    RUBY
    "instance variable" => [<<~RUBY, /has no static spelling/],
      require "optparse"
      class HiddenOptions
        def initialize
          @parser=OptionParser.new
        end
        def hidden_option(dynamic_name)
          @parser.on(dynamic_name)
        end
      end
    RUBY
    "ambiguous helper parameter" => [<<~RUBY, /has no static spelling/],
      require "optparse"
      def add_options(parser,dynamic_name); parser.on(dynamic_name); end
    RUBY
    "dup constructor chain" => [<<~RUBY, /has no static spelling/],
      require "optparse"
      def hidden_option(dynamic_name)
        OptionParser.new.dup.on(dynamic_name)
      end
    RUBY
    "clone constructor chain" => [<<~RUBY, /has no static spelling/]
      require "optparse"
      def hidden_option(dynamic_name)
        OptionParser.new.clone.define(dynamic_name)
      end
    RUBY
  }.freeze
  SOURCE_PROVEN_REGISTRATIONS = {
    "local" => <<~RUBY,
      parser = OptionParser.new
      parser.on(switch_name)
    RUBY
    "local alias" => <<~RUBY,
      original = OptionParser.new
      parser = original
      parser.define(switch_name)
    RUBY
    "block parameter" => <<~RUBY,
      OptionParser.new do |registry|
        registry.def_tail_option(switch_name)
      end
    RUBY
    "class alias and constructor chain" => <<~RUBY,
      parser_class = OptionParser
      parser = parser_class.new.freeze
      parser.on_head(switch_name)
    RUBY
    "instance variable or assignment" => <<~RUBY,
      @registry ||= OptionParser.new
      @registry.on_tail(switch_name)
    RUBY
    "class variable alias" => <<~RUBY,
      @@registry = OptionParser.new
      alias_registry = @@registry
      alias_registry.define_head(switch_name)
    RUBY
    "global alias" => <<~RUBY
      $option_registry ||= OptionParser.new
      alias_registry = $option_registry
      alias_registry.define_tail(switch_name)
    RUBY
  }.freeze
  LEXICAL_PROVENANCE_MUTATIONS = {
    "qualified nested class reopen" => <<~RUBY,
      require "optparse"
      module A
        module B; end
        class B::C
          def initialize
            @parser = OptionParser.new
          end
        end
      end
      module A
        class B::C
          def add_hidden(name)
            @parser.on(name)
          end
        end
      end
    RUBY
    "singleton class reopen" => <<~RUBY,
      require "optparse"
      class A; end
      class << A
        def install_parser
          @parser = OptionParser.new
        end
      end
      class << A
        def add_hidden(name)
          @parser.on(name)
        end
      end
    RUBY
    "inherited constant" => <<~RUBY,
      require "optparse"
      class BaseOptions
        PARSER = OptionParser.new
      end
      class ChildOptions < BaseOptions
        def add_hidden(name)
          PARSER.on(name)
        end
      end
    RUBY
    "inherited class variable" => <<~RUBY
      require "optparse"
      class BaseOptions
        @@parser = OptionParser.new
      end
      class ChildOptions < BaseOptions
        def add_hidden(name)
          @@parser.on(name)
        end
      end
    RUBY
  }.freeze
  NAMESPACE_REOPEN_MUTATION = <<~RUBY
    require_relative "%<namespace>s"
    module A
      class B::C
        def add_hidden(name)
          @parser.on(name)
        end
      end
    end
  RUBY
  NAMESPACE_DEFINITION_MUTATION = <<~RUBY
    require "optparse"
    module A
      module B
        class C
          def initialize
            @parser = OptionParser.new
          end
        end
      end
    end
  RUBY
  BLOCK_PARAMETER_SHADOWING_MUTATION = <<~RUBY
    require "optparse"
    def subscribe(event)
      required_receiver = OptionParser.new
      optional_receiver = OptionParser.new
      rest_receiver = OptionParser.new
      post_receiver = OptionParser.new
      keyword_receiver = OptionParser.new
      keyword_optional_receiver = OptionParser.new
      keyword_rest_receiver = OptionParser.new
      block_receiver = OptionParser.new
      block_local_receiver = OptionParser.new
      Object.new.then do |required_receiver, optional_receiver = nil, *rest_receiver, post_receiver,
                          keyword_receiver:, keyword_optional_receiver: nil, **keyword_rest_receiver,
                          &block_receiver; block_local_receiver|
        required_receiver.on(event)
        optional_receiver.on(event)
        rest_receiver.on(event)
        post_receiver.on(event)
        keyword_receiver.on(event)
        keyword_optional_receiver.on(event)
        keyword_rest_receiver.on(event)
        block_receiver.on(event)
        block_local_receiver.on(event)
      end
    end
  RUBY
  IDENTITY_ALIAS_MUTATION = <<~RUBY
    module Registry; end
    ParserRegistry = Registry
  RUBY
  IDENTITY_CLASS_MUTATION = <<~RUBY
    require "optparse"
    require_relative "m_identity_alias"
    class %<owner>s::Handler
      def initialize
        @parser = OptionParser.new
      end
    end
  RUBY
  IDENTITY_REOPEN_MUTATION = <<~RUBY
    require_relative "m_identity_alias"
    class %<owner>s::Handler
      def add_hidden(name)
        @parser.on(name)
      end
    end
  RUBY

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
      "__send__" => 'options.__send__(:define_head, "--watch", "changed")',
      "method call" => 'options.method(:def_option).call("--watch", "changed")',
      "implicit method call" => 'method(:on).call("--watch", "changed")',
      "public method lookup" => "options.public_method(:on)",
      "singleton method lookup" => "options.singleton_method(:on)",
      "unbound method lookup" => "OptionParser.instance_method(:on)",
      "public unbound method lookup" => 'OptionParser.public_instance_method("on")',
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

  def test_reviewer_optionparser_mutations_fail_without_inventory_updates
    REVIEWER_MUTATIONS.each do |label, (source, message)|
      with_repository_copy do |root|
        write_ruby(root, "lib/reviewer_mutation.rb", source)
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(message, error.message, label)
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

  def test_cross_file_constant_and_global_provenance_fails_closed
    variants = {
      "top-level constant" => {
        "lib/registry.rb" => "require \"optparse\"\nSHARED_PARSER = OptionParser.new\n",
        "lib/use_registry.rb" => "def use_registry(name); SHARED_PARSER.on(name); end\n"
      },
      "qualified constant" => {
        "lib/registry.rb" => "require \"optparse\"\nmodule Registry\nPARSER = OptionParser.new\nend\n",
        "lib/use_registry.rb" => "def use_registry(name); Registry::PARSER.on(name); end\n"
      },
      "qualified constant assignment" => {
        "lib/registry.rb" => "require \"optparse\"\nmodule Registry; end\nRegistry::PARSER = OptionParser.new\n",
        "lib/use_registry.rb" => "def use_registry(name); Registry::PARSER.on(name); end\n"
      },
      "global fixed-point alias" => {
        "lib/registry.rb" => "require \"optparse\"\n$shared_parser ||= OptionParser.new\n",
        "lib/registry_alias.rb" => "$shared_alias = $shared_parser\n",
        "lib/use_registry.rb" => "def use_registry(name); $shared_alias.on(name); end\n"
      }
    }
    variants.each do |label, sources|
      with_repository_copy do |root|
        sources.each { |relative, source| write_ruby(root, relative, source) }
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_class_reopen_shares_ivar_provenance_across_files
    with_repository_copy do |root|
      write_ruby(root, "lib/shared_options.rb", <<~RUBY)
        require "optparse"
        class SharedOptions
          def initialize
            @parser = OptionParser.new
          end
        end
      RUBY
      write_ruby(root, "lib/shared_options_reopen.rb", <<~RUBY)
        class SharedOptions
          def add_hidden(name)
            @parser.on(name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_ivar_and_local_provenance_do_not_leak_across_lexical_scopes
    with_repository_copy do |root|
      write_ruby(root, "lib/isolated_receivers.rb", <<~RUBY)
        require "optparse"
        class A
          def initialize
            @parser = OptionParser.new
          end
        end
        class B
          def subscribe(event)
            @parser.on(event)
          end
        end

        def outer_subscription(stream, event)
          def nested_parser
            stream = OptionParser.new
          end
          stream.on(event)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_nearest_lexical_constant_shadows_optionparser_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/shadowed_parser.rb", <<~RUBY)
        require "optparse"
        PARSER = OptionParser.new
        module Shadow
          PARSER = Object.new
          def self.subscribe(event)
            PARSER.on(event)
          end
        end

        module Left; end
        module Right
          PARSER = Object.new
          def self.subscribe(event)
            PARSER.on(event)
          end
        end
        Left::PARSER = OptionParser.new
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_absolute_constant_path_preserves_root_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/absolute_parser.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module X
          module Registry
            PARSER = Object.new
          end
          def self.add_hidden(name)
            ::Registry::PARSER.on(name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_relative_constant_path_uses_nearest_lexical_namespace
    with_repository_copy do |root|
      write_ruby(root, "lib/relative_parser.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module X
          module Registry
            PARSER = Object.new
          end
          def self.subscribe(name)
            Registry::PARSER.on(name)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_qualified_namespace_reopen_is_independent_of_file_name_order
    [%w[a_reopen.rb z_namespace.rb], %w[z_reopen.rb a_namespace.rb]].each do |reopen_file, namespace_file|
      with_repository_copy do |root|
        namespace_basename = File.basename(namespace_file, ".rb")
        write_ruby(root, "lib/#{reopen_file}", format(NAMESPACE_REOPEN_MUTATION, namespace: namespace_basename))
        write_ruby(root, "lib/#{namespace_file}", NAMESPACE_DEFINITION_MUTATION)
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, "#{reopen_file} / #{namespace_file}")
      end
    end
  end

  def test_namespace_singleton_and_inherited_provenance_fail_closed
    LEXICAL_PROVENANCE_MUTATIONS.each do |label, source|
      with_repository_copy do |root|
        write_ruby(root, "lib/lexical_provenance.rb", source)
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_block_parameters_and_locals_shadow_without_leaking
    with_repository_copy do |root|
      write_ruby(root, "lib/block_shadowing.rb", <<~RUBY)
        require "optparse"
        def block_shadowing(event)
          parser = OptionParser.new
          [Object.new].each do |parser|
            parser.on(event)
          end

          OptionParser.new do |yielded_parser|
          end
          [Object.new].each do
            yielded_parser.on(event)
          end

          [Object.new].each do
            local_parser = OptionParser.new
          end
          [Object.new].each do
            local_parser.on(event)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_optionparser_yielded_parameter_is_proven_inside_its_block
    with_repository_copy do |root|
      write_ruby(root, "lib/block_option_parser.rb", <<~RUBY)
        require "optparse"
        def add_hidden(dynamic_name)
          OptionParser.new do |parser|
            parser.on(dynamic_name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_optionparser_subclass_context_applies_only_to_implicit_self
    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_scope.rb", <<~RUBY)
        require "optparse"
        class ParserOptions < OptionParser
          def subscribe(stream, event)
            stream.on(event)
          end
          class Nested
            def subscribe(event)
              on(event)
            end
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end

    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_scope.rb", <<~RUBY)
        require "optparse"
        class ParserOptions < OptionParser
          def add_hidden(dynamic_name)
            on(dynamic_name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_optionparser_subclass_explicit_self_is_an_instance_registration
    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_explicit_self.rb", <<~RUBY)
        require "optparse"
        class ParserOptions < OptionParser
          def add_hidden(dynamic_name)
            self.on(dynamic_name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_optionparser_subclass_singleton_calls_are_not_instance_registrations
    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_singleton.rb", <<~RUBY)
        require "optparse"
        class ParserOptions < OptionParser
          def self.on(event); end
          def self.subscribe(event)
            on(event)
            self.on(event)
          end
          class << self
            def subscribe_again(event)
              on(event)
              self.on(event)
            end
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_all_block_parameter_forms_and_block_locals_shadow_outer_bindings
    with_repository_copy do |root|
      write_ruby(root, "lib/block_parameter_shadowing.rb", BLOCK_PARAMETER_SHADOWING_MUTATION)
      assert inventory_for(root).verify!
    end
  end

  def test_optional_and_keyword_parameter_defaults_seed_provenance
    {
      "optional" => "registry = OptionParser.new",
      "keyword" => "registry: OptionParser.new"
    }.each do |label, parameter|
      with_repository_copy do |root|
        write_ruby(root, "lib/#{label}_default.rb", <<~RUBY)
          require "optparse"
          def add_hidden(dynamic_name, #{parameter})
            registry.on(dynamic_name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_optional_and_keyword_block_defaults_seed_provenance
    {
      "optional" => "registry = OptionParser.new",
      "keyword" => "registry: OptionParser.new"
    }.each do |label, parameter|
      with_repository_copy do |root|
        write_ruby(root, "lib/#{label}_block_default.rb", <<~RUBY)
          require "optparse"
          def add_hidden(dynamic_name)
            [].each do |#{parameter}|
              registry.on(dynamic_name)
            end
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_block_local_optionparser_assignment_does_not_leak_to_later_blocks
    with_repository_copy do |root|
      write_ruby(root, "lib/block_local_scope.rb", <<~RUBY)
        require "optparse"
        def subscribe(event)
          [Object.new].each do |; block_registry|
            block_registry = OptionParser.new
          end
          [Object.new].each do
            block_registry.on(event)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_block_local_optionparser_assignment_is_proven_inside_its_block
    with_repository_copy do |root|
      write_ruby(root, "lib/block_local_provenance.rb", <<~RUBY)
        require "optparse"
        def add_hidden(dynamic_name)
          [Object.new].each do |; block_registry|
            block_registry = OptionParser.new
            block_registry.on(dynamic_name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_implicit_optionparser_block_parameters_fail_closed
    { "numbered" => "_1", "ruby 3.4 it" => "it" }.each do |label, parameter|
      with_repository_copy do |root|
        write_ruby(root, "lib/#{label.tr(' ', '_')}_block.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new { #{parameter}.on(name) }
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_implicit_optionparser_block_parameters_do_not_leak
    { "numbered" => "_1", "ruby 3.4 it" => "it" }.each do |label, parameter|
      with_repository_copy do |root|
        write_ruby(root, "lib/#{label.tr(' ', '_')}_scope.rb", <<~RUBY)
          require "optparse"
          def subscribe(name)
            OptionParser.new { #{parameter}.to_s }
            [Object.new].each { #{parameter}.on(name) }
          end
        RUBY
        assert inventory_for(root).verify!, label
      end
    end
  end

  def test_proven_instance_identity_chains_fail_closed
    variants = {
      "local itself" => "def add_hidden(name); parser = OptionParser.new; parser.itself.on(name); end",
      "local dup" => "def add_hidden(name); parser = OptionParser.new; parser.dup.on(name); end",
      "constant clone" => "PARSER = OptionParser.new\ndef add_hidden(name); PARSER.clone.on(name); end",
      "ivar clone" => "class ParserOwner\n" \
                      "def initialize; @parser = OptionParser.new; end\n" \
                      "def add_hidden(name); @parser.clone.on(name); end\nend",
      "local freeze" => "def add_hidden(name); parser = OptionParser.new; parser.freeze.on(name); end",
      "local tap" => "def add_hidden(name); parser = OptionParser.new; parser.tap {}.on(name); end"
    }
    variants.each do |label, source|
      with_repository_copy do |root|
        write_ruby(root, "lib/identity_#{label.tr(' ', '_')}.rb", "require \"optparse\"\n#{source}\n")
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_optionparser_builder_blocks_fail_closed
    {
      "then explicit" => "OptionParser.new.then { |parser| parser.on(name) }",
      "yield self numbered" => "OptionParser.new.yield_self { _1.on(name) }"
    }.each do |label, expression|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            #{expression}
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_builder_block_provenance_joins_instance_fixed_point
    with_repository_copy do |root|
      write_ruby(root, "lib/a_builder_use.rb", <<~RUBY)
        require_relative "z_builder_registry"
        def add_hidden(name)
          BUILDER_REGISTRY.then { |parser| parser.on(name) }
        end
      RUBY
      write_ruby(root, "lib/z_builder_registry.rb", <<~RUBY)
        require "optparse"
        BUILDER_REGISTRY = OptionParser.new
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_block_parameters_do_not_leak
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_block_scope.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then { |parser| parser.to_s }
          [Object.new].each { |parser| parser.on(name) }
          OptionParser.new.yield_self { _1.to_s }
          [Object.new].each { _1.on(name) }
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_only_first_builder_positional_parameter_receives_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_first_parameter.rb", <<~RUBY)
        require "optparse"
        def add_hidden(name)
          OptionParser.new.then { |parser, event_bus| parser.on(name) }
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_second_and_rest_parameters_are_not_parser_proven
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_extra_parameters.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then { |parser, event_bus| event_bus.on(name) }
          OptionParser.new.yield_self { |parser, *event_buses| event_buses.on(name) }
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_builder_extra_parameter_forms_shadow_without_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_parameter_forms.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then do |parser, event_bus = Object.new, *events, post_event,
                                    keyword_event:, optional_event: Object.new, **keyword_events,
                                    &callback; block_event|
            event_bus.on(name)
            events.on(name)
            post_event.on(name)
            keyword_event.on(name)
            optional_event.on(name)
            keyword_events.on(name)
            callback.on(name)
            block_event.on(name)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_builder_extra_parameter_is_proven_after_separate_assignment
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_assigned_extra_parameter.rb", <<~RUBY)
        require "optparse"
        def add_hidden(name)
          OptionParser.new.then do |parser, event_bus|
            event_bus = OptionParser.new
            event_bus.on(name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_local_first_truthy_conditional_stays_generic
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_generic_conditional.rb", <<~RUBY)
        require "optparse"
        class EventBus; end
        def subscribe(name)
          OptionParser.new.then do |parser|
            result ||= EventBus.new
            result ||= parser
            result
          end.on(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_builder_local_parser_conditional_is_not_overwritten
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_parser_conditional.rb", <<~RUBY)
        require "optparse"
        def add_hidden(name)
          OptionParser.new.then do |parser|
            result ||= parser
            result ||= Object.new
            result
          end.on(name)
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_local_falsey_conditional_becomes_parser
    %w[nil false ((nil)) ((false))].each_with_index do |falsey, index|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_falsey_conditional_#{index}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new.yield_self do |parser|
              result = #{falsey}
              result ||= parser
              ((result))
            end.on(name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, falsey)
      end
    end
  end

  def test_builder_call_site_reassignment_kills_yielded_parser
    {
      "event bus" => "parser = EventBus.new; parser.on(name)",
      "object" => "parser = Object.new; parser.on(name)",
      "alias reassigned" => "alias_parser = parser; alias_parser = EventBus.new; alias_parser.on(name)",
      "restore after call" => "parser = EventBus.new; parser.on(name); parser = OptionParser.new"
    }.each do |label, statements|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_call_kill_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          class EventBus; end
          def subscribe(name)
            OptionParser.new.then { |parser| #{statements} }
          end
        RUBY
        assert inventory_for(root).verify!, label
      end
    end
  end

  def test_builder_call_site_uses_state_before_later_reassignment
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_call_before_kill.rb", <<~RUBY)
        require "optparse"
        class EventBus; end
        def add_hidden(name)
          OptionParser.new.then do |parser|
            parser.on(name)
            parser = EventBus.new
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_call_site_reassignment_back_to_parser_restores_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_call_restore.rb", <<~RUBY)
        require "optparse"
        class EventBus; end
        def add_hidden(name)
          OptionParser.new.then do |parser|
            yielded_parser = parser
            parser = EventBus.new
            parser = yielded_parser
            parser.on(name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_builder_assignment_rhs_does_not_restore_killed_parser_provenance
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_killed_rhs_alias.rb", <<~RUBY)
        require "optparse"
        class EventBus; end
        def subscribe(name)
          OptionParser.new.then do |parser|
            parser = EventBus.new
            receiver = parser
            receiver.on(name)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_builder_assignment_rhs_propagates_live_parser_aliases
    {
      "direct" => "receiver = parser",
      "parenthesized" => "receiver = ((parser))",
      "identity" => "receiver = ((parser.itself))"
    }.each do |label, assignment|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_live_rhs_alias_#{label}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new.then do |parser|
              #{assignment}
              receiver.on(name)
            end
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_assignment_rhs_registration_precedes_the_local_write
    {
      "same binding" => "parser = parser.on(name)",
      "parenthesized" => "parser = ((parser.on(name)))",
      "alias receiver" => "receiver = parser; parser = ((receiver.on(name)))"
    }.each do |label, statements|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_assignment_rhs_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new.then { |parser| #{statements} }
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_conditional_assignment_skips_registration_for_known_truthy_lhs
    {
      "yielded parser" => "parser ||= parser.on(name)",
      "true" => "result = true; result ||= parser.on(name)",
      "object" => "result = Object.new; result ||= ((parser.on(name)))"
    }.each do |label, statements|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_truthy_guard_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          def subscribe(name)
            OptionParser.new.then { |parser| #{statements} }
          end
        RUBY
        assert inventory_for(root).verify!, label
      end
    end
  end

  def test_conditional_assignment_executes_registration_for_known_falsey_lhs
    {
      "nil" => "result = nil; result ||= parser.on(name)",
      "false" => "result = false; result ||= parser.on(name)",
      "parenthesized alias" => "receiver = parser; result = ((nil)); result ||= ((receiver.on(name)))"
    }.each do |label, statements|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_falsey_guard_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new.then { |parser| #{statements} }
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_optional_first_builder_parameter_ignores_its_default
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_optional_first.rb", <<~RUBY)
        require "optparse"
        def add_hidden(name)
          OptionParser.new.then { |parser = Object.new| parser.on(name) }
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_optional_extra_builder_parameter_uses_non_parser_default
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_optional_extra_generic.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then { |parser, event_bus = Object.new| event_bus.on(name) }
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_optional_extra_builder_parameter_can_be_independently_proven
    with_repository_copy do |root|
      write_ruby(root, "lib/builder_optional_extra_parser.rb", <<~RUBY)
        require "optparse"
        def add_hidden(name)
          OptionParser.new.then { |parser, extra_parser = OptionParser.new| extra_parser.on(name) }
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_parenthesized_receivers_retain_provenance
    variants = {
      "local" => "parser = OptionParser.new\n((parser)).on(name)",
      "constant" => "PARSER = OptionParser.new\ndef add_hidden(name); ((PARSER)).on(name); end",
      "self" => "class WrappedParser < OptionParser\n" \
                "def add_hidden(name); ((self)).on(name); end\nend"
    }
    variants.each do |label, body|
      with_repository_copy do |root|
        write_ruby(root, "lib/parenthesized_#{label}.rb", "require \"optparse\"\n#{body}\n")
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_constant_alias_qualifies_optionparser_instance
    { "direct" => "ParserRegistry", "fixed point" => "FinalRegistry" }.each do |label, receiver|
      with_repository_copy do |root|
        write_ruby(root, "lib/aliased_registry.rb", <<~RUBY)
          require "optparse"
          module Registry
            PARSER = OptionParser.new
          end
          ParserRegistry = Registry
          FinalRegistry = ParserRegistry
          def add_hidden(name)
            #{receiver}::PARSER.on(name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_constant_aliases_preserve_nearest_lexical_shadowing
    with_repository_copy do |root|
      write_ruby(root, "lib/lexical_alias.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module X
          module Registry
            PARSER = Object.new
          end
          ParserRegistry = Registry
          def self.subscribe(name)
            ParserRegistry::PARSER.on(name)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_absolute_constant_alias_path_ignores_lexical_shadowing
    with_repository_copy do |root|
      write_ruby(root, "lib/absolute_alias.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        ParserRegistry = Registry
        module X
          module ParserRegistry
            PARSER = Object.new
          end
          def self.add_hidden(name)
            ::ParserRegistry::PARSER.on(name)
          end
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_namespace_identity_alias_reopens_are_direction_and_order_independent
    directions = [%w[ParserRegistry Registry], %w[Registry ParserRegistry]]
    orders = [%w[a_create.rb z_reopen.rb], %w[z_create.rb a_reopen.rb]]
    directions.product(orders).each do |(created_as, reopened_as), (create_file, reopen_file)|
      with_repository_copy do |root|
        write_identity_alias_fixture(root, created_as, reopened_as, create_file, reopen_file)
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        label = "#{created_as} -> #{reopened_as}, #{create_file} -> #{reopen_file}"
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_superclass_alias_preserves_indirect_optionparser_subclass_context
    with_repository_copy do |root|
      write_ruby(root, "lib/a_aliased_child.rb", <<~RUBY)
        require_relative "z_aliased_base"
        class ChildParser < BaseAlias
          def add_hidden(name)
            on(name)
          end
        end
      RUBY
      write_ruby(root, "lib/z_aliased_base.rb", <<~RUBY)
        require "optparse"
        class BaseParser < OptionParser; end
        BaseAlias = BaseParser
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_conditional_constant_alias_qualifies_optionparser_instance
    with_repository_copy do |root|
      write_ruby(root, "lib/conditional_alias.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        ParserRegistry ||= Registry
        def add_hidden(name)
          ParserRegistry::PARSER.on(name)
        end
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_conditional_constant_alias_fixed_point_is_file_order_independent
    with_repository_copy do |root|
      write_ruby(root, "lib/a_conditional_alias_use.rb", <<~RUBY)
        require_relative "m_conditional_alias"
        def add_hidden(name)
          FinalRegistry::PARSER.on(name)
        end
      RUBY
      write_ruby(root, "lib/m_conditional_alias.rb", <<~RUBY)
        require_relative "z_conditional_registry"
        FinalRegistry ||= ParserRegistry
      RUBY
      write_ruby(root, "lib/z_conditional_registry.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        ParserRegistry ||= Registry
      RUBY
      error = assert_raises(RuntimeError) { inventory_for(root).verify! }
      assert_match(/has no static spelling/, error.message)
    end
  end

  def test_conditional_constant_alias_does_not_override_existing_identity
    with_repository_copy do |root|
      write_ruby(root, "lib/conditional_alias_shadow.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module OtherRegistry
          PARSER = Object.new
        end
        ParserRegistry = OtherRegistry
        ParserRegistry ||= Registry
        def subscribe(name)
          ParserRegistry::PARSER.on(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_conditional_constant_alias_uses_nearest_lexical_target
    with_repository_copy do |root|
      write_ruby(root, "lib/conditional_alias_lexical.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module X
          module Registry
            PARSER = Object.new
          end
          ParserRegistry ||= Registry
          def self.subscribe(name)
            ParserRegistry::PARSER.on(name)
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_conditional_alias_first_truthy_identity_wins_in_source_order
    targets = {
      "parser first" => [%w[Registry OtherRegistry], true],
      "other first" => [%w[OtherRegistry Registry], false]
    }
    targets.each do |label, (order, detects_parser)|
      with_repository_copy do |root|
        write_ruby(root, "lib/ordered_conditional_alias.rb", ordered_conditional_alias_source(order))
        if detects_parser
          error = assert_raises(RuntimeError) { inventory_for(root).verify! }
          assert_match(/has no static spelling/, error.message, label)
        else
          assert inventory_for(root).verify!, label
        end
      end
    end
  end

  def test_conditional_alias_generic_and_parser_order_is_not_overwritten
    {
      "generic first" => ["Object.new", "Registry", false],
      "parser first" => ["Registry", "Object.new", true]
    }.each do |label, (first, second, detects_parser)|
      with_repository_copy do |root|
        write_ruby(root, "lib/conditional_generic_order.rb", <<~RUBY)
          require "optparse"
          module Registry
            PARSER = OptionParser.new
          end
          ParserRegistry ||= #{first}
          ParserRegistry ||= #{second}
          def add_hidden(name)
            ParserRegistry::PARSER.on(name)
          end
        RUBY
        if detects_parser
          error = assert_raises(RuntimeError) { inventory_for(root).verify! }
          assert_match(/has no static spelling/, error.message, label)
        else
          assert inventory_for(root).verify!, label
        end
      end
    end
  end

  def test_explicit_falsey_value_permits_later_conditional_alias
    %w[false nil].each do |falsey|
      with_repository_copy do |root|
        write_ruby(root, "lib/conditional_after_#{falsey}.rb", <<~RUBY)
          require "optparse"
          module Registry
            PARSER = OptionParser.new
          end
          ParserRegistry = #{falsey}
          ParserRegistry ||= Registry
          def add_hidden(name)
            ParserRegistry::PARSER.on(name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, falsey)
      end
    end
  end

  def test_parenthesized_falsey_value_permits_later_conditional_alias
    %w[((false)) ((nil))].each_with_index do |falsey, index|
      with_repository_copy do |root|
        write_ruby(root, "lib/parenthesized_falsey_#{index}.rb", <<~RUBY)
          require "optparse"
          module Registry
            PARSER = OptionParser.new
          end
          ParserRegistry = #{falsey}
          ParserRegistry ||= Registry
          def add_hidden(name)
            ParserRegistry::PARSER.on(name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, falsey)
      end
    end
  end

  def test_parenthesized_truthy_value_blocks_later_conditional_alias
    ["((Object.new))", "((true))", '(("set"))', "((OtherRegistry))"].each_with_index do |truthy, index|
      with_repository_copy do |root|
        write_ruby(root, "lib/parenthesized_truthy_#{index}.rb", <<~RUBY)
          require "optparse"
          module Registry
            PARSER = OptionParser.new
          end
          module OtherRegistry
            PARSER = Object.new
          end
          ParserRegistry = #{truthy}
          ParserRegistry ||= Registry
          def subscribe(name)
            ParserRegistry::PARSER.on(name)
          end
        RUBY
        assert inventory_for(root).verify!, truthy
      end
    end
  end

  def test_conflicting_cross_file_conditional_aliases_remain_unproven
    with_repository_copy do |root|
      write_ruby(root, "lib/a_parser_alias.rb", "ParserRegistry ||= Registry\n")
      write_ruby(root, "lib/z_other_alias.rb", "ParserRegistry ||= OtherRegistry\n")
      write_ruby(root, "lib/m_alias_targets.rb", <<~RUBY)
        require "optparse"
        module Registry
          PARSER = OptionParser.new
        end
        module OtherRegistry
          PARSER = Object.new
        end
        def subscribe(name)
          ParserRegistry::PARSER.on(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_optionparser_subclass_self_identity_chains_fail_closed
    {
      "itself" => "self.itself.on(name)",
      "freeze" => "self.freeze.on(name)",
      "tap" => "self.tap {}.on(name)",
      "dup" => "self.dup.on(name)",
      "clone" => "self.clone.on(name)",
      "then builder" => "self.then { |parser| parser.on(name) }",
      "yield self builder" => "self.yield_self { _1.on(name) }"
    }.each do |label, expression|
      with_repository_copy do |root|
        write_ruby(root, "lib/subclass_self_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          class ParserOptions < OptionParser
            def add_hidden(name)
              #{expression}
            end
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_optionparser_subclass_singleton_self_chains_remain_unproven
    with_repository_copy do |root|
      write_ruby(root, "lib/subclass_singleton_self_chain.rb", <<~RUBY)
        require "optparse"
        class ParserOptions < OptionParser
          def self.subscribe(name)
            self.itself.on(name)
            self.freeze.on(name)
            self.dup.on(name)
            self.clone.on(name)
            self.then { |parser| parser.on(name) }
            self.yield_self { _1.on(name) }
          end
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_identity_returning_then_and_yield_self_chains_fail_closed
    {
      "explicit" => "OptionParser.new.then { |parser| parser }.on(name)",
      "numbered parenthesized" => "OptionParser.new.yield_self { ((_1)) }.on(name)",
      "it parenthesized" => "OptionParser.new.then { ((it)) }.on(name)"
    }.each do |label, expression|
      with_repository_copy do |root|
        write_ruby(root, "lib/identity_return_#{label.tr(' ', '_')}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            #{expression}
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_builder_return_local_alias_identity_chains_fail_closed
    {
      "itself" => "alias_parser.itself",
      "freeze" => "alias_parser.freeze",
      "tap" => "alias_parser.tap {}",
      "dup" => "alias_parser.dup",
      "clone" => "alias_parser.clone"
    }.each do |label, returned|
      with_repository_copy do |root|
        write_ruby(root, "lib/builder_alias_#{label}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            OptionParser.new.then do |parser|
              alias_parser = parser
              ((#{returned}))
            end.on(name)
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_implicit_builder_return_local_aliases_fail_closed
    {
      "numbered" => "OptionParser.new.yield_self " \
                    "{ alias_parser = _1; final_parser = alias_parser; ((final_parser)) }.on(name)",
      "it" => "OptionParser.new.then { alias_parser = it; ((alias_parser.clone)) }.on(name)"
    }.each do |label, expression|
      with_repository_copy do |root|
        write_ruby(root, "lib/implicit_builder_alias_#{label}.rb", <<~RUBY)
          require "optparse"
          def add_hidden(name)
            #{expression}
          end
        RUBY
        error = assert_raises(RuntimeError) { inventory_for(root).verify! }
        assert_match(/has no static spelling/, error.message, label)
      end
    end
  end

  def test_transformed_or_reassigned_builder_alias_returns_remain_unproven
    with_repository_copy do |root|
      write_ruby(root, "lib/transformed_builder_alias_return.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then { |parser| alias_parser = parser; alias_parser = Object.new; alias_parser }.on(name)
          OptionParser.new.then { |parser| alias_parser = parser.to_s; alias_parser }.on(name)
          OptionParser.new.yield_self { alias_parser = _1; alias_parser.to_s }.on(name)
          OptionParser.new.then { |parser| alias_parser = parser; alias_parser.then { Object.new } }.on(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_transformed_then_and_yield_self_returns_remain_unproven
    with_repository_copy do |root|
      write_ruby(root, "lib/transformed_builder_return.rb", <<~RUBY)
        require "optparse"
        def subscribe(name)
          OptionParser.new.then { |parser| parser.to_s }.on(name)
          OptionParser.new.yield_self { Object.new }.on(name)
          OptionParser.new.then { |parser| parser = Object.new; parser }.on(name)
        end
      RUBY
      assert inventory_for(root).verify!
    end
  end

  def test_source_proven_optionparser_receivers_reject_dynamic_spellings
    SOURCE_PROVEN_REGISTRATIONS.each do |label, registration|
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

  def write_identity_alias_fixture(root, created_as, reopened_as, create_file, reopen_file)
    write_ruby(root, "lib/m_identity_alias.rb", IDENTITY_ALIAS_MUTATION)
    write_ruby(root, "lib/#{create_file}", format(IDENTITY_CLASS_MUTATION, owner: created_as))
    write_ruby(root, "lib/#{reopen_file}", format(IDENTITY_REOPEN_MUTATION, owner: reopened_as))
  end

  def ordered_conditional_alias_source(order)
    assignments = order.map { |target| "ParserRegistry ||= #{target}" }.join("\n")
    <<~RUBY
      require "optparse"
      module Registry
        PARSER = OptionParser.new
      end
      module OtherRegistry
        PARSER = Object.new
      end
      #{assignments}
      def add_hidden(name)
        ParserRegistry::PARSER.on(name)
      end
    RUBY
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
