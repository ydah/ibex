# frozen_string_literal: true

require "digest"
require "ripper"
require "yaml"

module Ibex
  module Quality
    # rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/PredicateMethod
    # One closed scanner/validator owns source binding, policy validation, and the deterministic public projection.
    # Statically binds every production OptionParser registration to an owner decision.
    class ConfigurationInventory
      ROOT = File.expand_path("../..", __dir__)
      REGISTRY = "test/fixtures/configuration/options-v1.yml"
      DOCUMENT = "docs/declarative-configuration.md"
      SOURCE_GLOBS = ["exe/*", "lib/**/*.rb"].freeze
      REGISTRATION_APIS = %w[
        on on_head on_tail define define_head define_tail def_option def_head_option def_tail_option
      ].freeze
      REFLECTIVE_SEND_APIS = %w[send public_send __send__].freeze
      BOUND_METHOD_APIS = %w[method public_method singleton_method].freeze
      UNBOUND_METHOD_APIS = %w[instance_method public_instance_method].freeze
      SURFACES = {
        ["lib/ibex/cli.rb", "add_compatibility_options"] => "generate",
        ["lib/ibex/cli.rb", "add_information_options"] => "generate",
        ["lib/ibex/cli.rb", "add_output_options"] => "generate",
        ["lib/ibex/cli.rb", "add_pipeline_options"] => "generate",
        ["lib/ibex/cli.rb", "add_signature_output_options"] => "generate",
        ["lib/ibex/cli/ambiguity.rb", "ambiguity_option_parser"] => "check-ambiguity",
        ["lib/ibex/cli/analysis.rb", "analysis_options"] => "diff-or-metrics",
        ["lib/ibex/cli/bison_import.rb", "add_bison_import_budgets"] => "import-bison",
        ["lib/ibex/cli/bison_import.rb", "bison_import_option_parser"] => "import-bison",
        ["lib/ibex/cli/counterexample_options.rb", "add_counterexample_options"] => "generate",
        ["lib/ibex/cli/coverage.rb", "coverage_check_options"] => "coverage-check",
        ["lib/ibex/cli/coverage.rb", "coverage_output_options"] => "coverage-collect-or-merge",
        ["lib/ibex/cli/debug.rb", "debug_options"] => "debug",
        ["lib/ibex/cli/diagnostics.rb", "diagnostics_option_parser"] => "diagnostics",
        ["lib/ibex/cli/documentation.rb", "documentation_option_parser"] => "doc",
        ["lib/ibex/cli/equiv.rb", "add_equiv_search_options"] => "equiv",
        ["lib/ibex/cli/equiv.rb", "equiv_options"] => "equiv",
        ["lib/ibex/cli/error_messages.rb", "error_messages_option_parser"] => "error-messages",
        ["lib/ibex/cli/explain.rb", "add_explain_search_options"] => "explain",
        ["lib/ibex/cli/explain.rb", "explain_option_parser"] => "explain",
        ["lib/ibex/cli/fix.rb", "add_fix_budget_options"] => "fix",
        ["lib/ibex/cli/fix.rb", "add_fix_target_options"] => "fix",
        ["lib/ibex/cli/fix.rb", "fix_options"] => "fix",
        ["lib/ibex/cli/formatting.rb", "formatting_option_parser"] => "formatting",
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_execution_options"] => "fuzz",
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_external_options"] => "fuzz",
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_generation_options"] => "fuzz",
        ["lib/ibex/cli/fuzz.rb", "fuzz_option_parser"] => "fuzz",
        ["lib/ibex/cli/generation_error_messages.rb", "add_error_messages_generation_option"] => "generate",
        ["lib/ibex/cli/grammar_tests.rb", "grammar_test_option_parser"] => "test",
        ["lib/ibex/cli/ir_tools.rb", "migrate_ir_options"] => "migrate-ir",
        ["lib/ibex/cli/lsp.rb", "lsp_option_parser"] => "lsp",
        ["lib/ibex/cli/racc_migration.rb", "migrate_check_options"] => "migrate-check",
        ["lib/ibex/cli/racc_migration.rb", "migrate_harness_options"] => "migrate-harness",
        ["lib/ibex/cli/reduce.rb", "reduce_option_parser"] => "reduce",
        ["lib/ibex/cli/samples.rb", "add_sample_generation_options"] => "samples",
        ["lib/ibex/cli/samples.rb", "add_sample_input_options"] => "samples",
        ["lib/ibex/cli/samples.rb", "samples_option_parser"] => "samples",
        ["lib/ibex/cli/verify.rb", "verify_options"] => "verify"
      }.freeze
      REVIEWED_OPTION_PARSER_PARAMETER_POSITIONS = {
        ["lib/ibex/cli.rb", "add_compatibility_options"] => [0],
        ["lib/ibex/cli.rb", "add_information_options"] => [0],
        ["lib/ibex/cli.rb", "add_output_options"] => [0],
        ["lib/ibex/cli.rb", "add_pipeline_options"] => [0],
        ["lib/ibex/cli.rb", "add_signature_output_options"] => [0],
        ["lib/ibex/cli/bison_import.rb", "add_bison_import_budgets"] => [0],
        ["lib/ibex/cli/counterexample_options.rb", "add_counterexample_options"] => [0],
        ["lib/ibex/cli/equiv.rb", "add_equiv_search_options"] => [0],
        ["lib/ibex/cli/explain.rb", "add_explain_search_options"] => [0],
        ["lib/ibex/cli/fix.rb", "add_fix_budget_options"] => [0],
        ["lib/ibex/cli/fix.rb", "add_fix_target_options"] => [0],
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_execution_options"] => [0],
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_external_options"] => [0],
        ["lib/ibex/cli/fuzz.rb", "add_fuzz_generation_options"] => [0],
        ["lib/ibex/cli/generation_error_messages.rb", "add_error_messages_generation_option"] => [0],
        ["lib/ibex/cli/samples.rb", "add_sample_generation_options"] => [0],
        ["lib/ibex/cli/samples.rb", "add_sample_input_options"] => [0]
      }.freeze
      SURFACE_OVERRIDES = {
        "lib/ibex/cli.rb#add_information_options#--lang=LANG" => "global"
      }.freeze
      GRAMMAR_CONTRACT_PERSISTENCE = {
        "grammar.mode" => %w[grammar_ir_v2_current current],
        "parser.superclass" => %w[grammar_ir_v2_current current],
        "actions.omit_calls" => %w[grammar_ir_v2_current current],
        "parser.algorithm" => %w[automaton_ir_v2_only_contract_gap current],
        "parser.entries" => %w[starts_current_strategy_gap current],
        "cst.trivia" => %w[cst_contract_gap current_gap]
      }.freeze
      OWNER_CLASSES = %w[grammar_contract grammar_minimum project_build_policy invocation_request].freeze
      ADMISSION_RESULTS = %w[
        admitted_a1_a8
        deferred_a5_minimum_undefined
        excluded_x1_operation
        excluded_x2_path_or_destination
        excluded_x3_presentation
        excluded_x4_caller_budget
        excluded_x5_packaging_or_deployment
        excluded_x6_environment_or_secret
        excluded_x7_diagnostic_suppression
      ].freeze
      OVERRIDE_ALGEBRAS = %w[
        fixed staged_fixed_compatibility minimum analysis_override project_selection invocation_only
      ].freeze
      IR_PRESENCE = %w[
        grammar_ir_v2_current
        automaton_ir_v2_only_contract_gap
        starts_current_strategy_gap
        cst_contract_gap
        not_persisted
      ].freeze
      MANIFEST_PRESENCE = %w[current current_gap not_applicable].freeze
      COMPATIBILITY_STATES = %w[current obsolete_alias staged_compatibility internal_compatibility].freeze
      SEMANTIC_VALUE_TYPES = %w[
        boolean integer float string path enum set_of_enums optional_path_or_boolean optional_string_or_boolean
      ].freeze
      ROOT_KEYS = %w[schema_version scope registrations].freeze
      SCOPE_KEYS = %w[source_globs call_site_count runtime_registration_count].freeze
      ENTRY_KEYS = %w[
        id source method line registration_api declaration_sha256 context_sha256 surface declared_spellings
        effective_spellings canonical_key source_value_type value_type value_domain default affected_stages
        public_contract_effect owner_class grammar_admission override_algebra ir_presence manifest_presence
        trust_implications compatibility_status
      ].freeze
      SHA256 = /\A[0-9a-f]{64}\z/
      KEY = /\A[a-z][a-z0-9]*(?:\.[a-z][a-z0-9_]*)+\z/

      Declaration = Struct.new(
        :id, :source, :method_name, :line, :registration_api, :declaration_sha256, :context_sha256, :surface,
        :declared_spellings, :spellings, :source_value_type,
        keyword_init: true
      )

      def initialize(root: ROOT, registry: nil, document: nil)
        @root = File.expand_path(root)
        @registry = registry || path(REGISTRY)
        @document = document || path(DOCUMENT)
      end

      def verify!
        inventory = load_inventory
        exact_keys!(inventory, ROOT_KEYS, "inventory")
        raise "configuration inventory schema_version must be 1" unless inventory.fetch("schema_version") == 1

        scope = inventory.fetch("scope")
        exact_keys!(scope, SCOPE_KEYS, "scope")
        unless scope.fetch("source_globs") == SOURCE_GLOBS
          raise "configuration inventory source_globs must match the reviewed production CLI scope"
        end

        declarations = declarations()
        call_site_count = declarations.map { |entry| [entry.source, entry.method_name, entry.line] }.uniq.length
        unless scope.fetch("call_site_count") == call_site_count
          raise "configuration inventory call_site_count drift: expected #{call_site_count}"
        end
        unless scope.fetch("runtime_registration_count") == declarations.length
          raise "configuration inventory runtime_registration_count drift: expected #{declarations.length}"
        end

        entries = inventory.fetch("registrations")
        raise "configuration inventory registrations must be an array" unless entries.is_a?(Array)

        expected_order = entries.sort_by { |entry| entry.fetch("id", "") }
        raise "configuration inventory registrations must use deterministic id order" unless entries == expected_order

        verify_exact_coverage(entries, declarations)
        verify_entries(entries, declarations.to_h { |declaration| [declaration.id, declaration] })
        verify_aliases(entries)
        verify_document!(entries)
        true
      end

      def render(entries = load_inventory.fetch("registrations"))
        counts = entries.group_by { |entry| entry.fetch("owner_class") }.transform_values(&:length)
        call_site_groups = entries.group_by do |entry|
          [entry.fetch("source"), entry.fetch("method"), entry.fetch("line")]
        end
        ordinary_count = call_site_groups.count { |_site, records| records.one? }
        expanded_groups = call_site_groups.values.reject(&:one?).sort_by do |records|
          [records.first.fetch("surface"), records.first.fetch("method")]
        end
        expansion_summary = expanded_groups.map do |records|
          "#{records.length} `#{records.first.fetch('surface')}` budget variants"
        end.join(" and ")
        spelling_count = entries.sum { |entry| entry.fetch("effective_spellings").length }
        lines = [
          "# Declarative configuration inventory",
          "",
          "<!-- Generated by tool/quality/configuration_inventory.rb; edit options-v1.yml and regenerate. -->",
          "",
          "This inventory classifies every production `OptionParser` registration API call under `exe/` and `lib/` " \
          "without loading Ibex or user code.",
          "The closed API family is `on`, `on_head`, `on_tail`, `define`, `define_head`, `define_tail`,",
          "`def_option`, `def_head_option`, and `def_tail_option` in explicit or implicit call forms.",
          "Unresolved registrations and splats fail closed; every source method has a reviewed command surface.",
          "Reflective registration through `send`, `public_send`, `__send__`, or bound methods is prohibited",
          "at method lookup time, before assignment or `call` can hide it.",
          "A parser/options-style helper parameter and a static literal beginning with `-` are conservative",
          "OptionParser signals; unrelated receivers must avoid option-like spellings or receive explicit review.",
          "The admission decision follows `.idea/ibex-declarative-configuration-policy.md`: grammar-owned settings",
          "must pass A1-A8 and every X1-X7 exclusion remains outside grammar syntax.",
          "",
          "The static baseline is #{call_site_groups.length} source call sites and " \
          "#{entries.length} runtime registrations:",
          "#{ordinary_count} ordinary call sites plus #{expansion_summary}.",
          "Those registrations expose #{spelling_count} effective spelling records after aliases and",
          "`--[no-]save-regression` are expanded; optional-argument notation remains one option pattern.",
          "",
          "Verification: `bundle exec rake quality:configuration_inventory`.",
          "Regeneration: `bundle exec ruby tool/quality/configuration_inventory.rb render`.",
          "",
          "## Decision rules",
          "",
          "This D001 artifact is inventory-only: it adds neither grammar syntax " \
          "nor the D002 effective-configuration model.",
          "`grammar_contract` is reserved for parser meaning/public contract and requires A1-A8, fixed semantics,",
          "root-only composition, provenance, and IR persistence. `project_build_policy` covers " \
          "representation and packaging.",
          "It also covers source mapping and companion artifacts rejected by X5.",
          "`invocation_request` covers operations, paths, presentation, caller budgets,",
          "and warning execution policy rejected by X1-X4, X6, or X7.",
          "No current registration is classified as `grammar_minimum`: `test --coverage` remains an invocation request",
          "with admission deferred until user-production coverage and monotone merge are defined.",
          "",
          "| First-wave concept | Owner | Algebra | Current persistence status |",
          "|---|---|---|---|",
          markdown_row(["`grammar.mode`, `parser.superclass`, `actions.omit_calls`", "Grammar Contract",
                        "staged fixed compatibility", "Grammar IR v2; legacy CLI override needs D008"]),
          markdown_row(["`parser.algorithm`", "Grammar Contract", "fixed generation / explicit analysis override",
                        "Automaton IR only; grammar-contract persistence gap"]),
          markdown_row(["`parser.entries`", "Grammar Contract", "fixed generation / explicit analysis override",
                        "start symbols persist; isolation strategy gap"]),
          markdown_row(["`cst.trivia`", "Grammar Contract", "fixed", "IR and generation-manifest gaps"]),
          markdown_row(["table/runtime/debug/source mapping/companions", "Project Build Policy", "project selection",
                        "manifest records current generation choices"]),
          markdown_row(["emit/path/watch/report/budget/locale/help/warnings", "Invocation Request", "invocation only",
                        "excluded from Grammar IR"]),
          "",
          "Fixed means a future grammar declaration may be matched but not silently contradicted by generation CLI.",
          "Analysis commands may choose a different value only as an explicit noncanonical analysis override.",
          "The inventory records present compatibility gaps; it does not claim that later D002-D008 work is complete.",
          "",
          "## Owner summary",
          "",
          "| Owner class | Registrations |",
          "|---|---:|"
        ]
        OWNER_CLASSES.each { |owner| lines << "| `#{owner}` | #{counts.fetch(owner, 0)} |" }
        lines.push(
          "",
          "## Decisions",
          "",
          markdown_row([
                         "Surface", "CLI spelling / aliases", "Canonical concept", "Source / semantic type",
                         "Domain / default", "Stages", "Public-contract effect", "Owner", "Admission", "Override",
                         "IR / manifest", "Trust", "Compatibility", "Source"
                       ]),
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
        )
        entries.each do |entry|
          lines << "| #{cell(entry.fetch('surface'))} " \
                   "| #{cell(entry.fetch('effective_spellings').join(', '))} " \
                   "| `#{entry.fetch('canonical_key')}` " \
                   "| #{cell("#{entry.fetch('source_value_type')} / #{entry.fetch('value_type')}")} " \
                   "| #{cell("#{entry.fetch('value_domain')} / #{entry.fetch('default')}")} " \
                   "| #{cell(entry.fetch('affected_stages').join(', '))} " \
                   "| #{cell(entry.fetch('public_contract_effect'))} " \
                   "| `#{entry.fetch('owner_class')}` " \
                   "| `#{entry.fetch('grammar_admission')}` " \
                   "| `#{entry.fetch('override_algebra')}` " \
                   "| `#{entry.fetch('ir_presence')}` / `#{entry.fetch('manifest_presence')}` " \
                   "| #{cell(entry.fetch('trust_implications'))} " \
                   "| `#{entry.fetch('compatibility_status')}` " \
                   "| `#{entry.fetch('source')}:#{entry.fetch('line')}` |"
        end
        "#{lines.join("\n")}\n"
      end

      def write_document!
        File.binwrite(@document, render)
      end

      def declarations
        values = source_paths.flat_map { |relative| scan(relative) }.sort_by(&:id)
        used_surfaces = values.map { |item| [item.source, item.method_name] }.uniq
        stale_surfaces = SURFACES.keys - used_surfaces
        unless stale_surfaces.empty?
          raise "reviewed command surface mappings are stale: #{stale_surfaces.map { |item| item.join('#') }.join(',')}"
        end

        stale_overrides = SURFACE_OVERRIDES.keys - values.map(&:id)
        raise "reviewed command surface overrides are stale: #{stale_overrides.join(',')}" unless stale_overrides.empty?

        stale_parameters = REVIEWED_OPTION_PARSER_PARAMETER_POSITIONS.keys - used_surfaces
        unless stale_parameters.empty?
          raise "reviewed OptionParser parameter mappings are stale: " \
                "#{stale_parameters.map { |item| item.join('#') }.join(',')}"
        end

        values
      end

      private

      def path(relative)
        File.join(@root, relative)
      end

      def source_paths
        SOURCE_GLOBS.flat_map { |glob| Dir.glob(path(glob)) }
                    .select { |absolute| File.file?(absolute) }
                    .uniq.sort.map { |absolute| absolute.delete_prefix("#{@root}/") }
      end

      def scan(relative)
        source = File.binread(path(relative))
        sexp = Ripper.sexp(source)
        raise "cannot parse production Ruby source #{relative}" unless sexp

        calls = []
        walk(sexp, nil, nil, calls, false)
        calls.each { |call| call[:source_node] = sexp }
        calls.select { |call| registration_candidate?(relative, call) }
             .flat_map { |call| declarations_for_call(relative, call) }
      end

      def declarations_for_call(relative, call)
        if call.fetch(:reflective, false)
          api = call[:api] || "unresolved method"
          raise "#{relative}:#{call.fetch(:line)} reflective OptionParser registration (#{api}) is prohibited"
        end
        if call.fetch(:splat)
          raise "#{relative}:#{call.fetch(:line)} OptionParser #{call.fetch(:api)} splat is statically unresolved"
        end

        spellings = option_spellings(call.fetch(:arguments))
        if spellings.empty?
          raise "#{relative}:#{call.fetch(:line)} OptionParser #{call.fetch(:api)} has no static spelling"
        end
        unless call[:method] && call[:method_node]
          raise "#{relative}:#{call.fetch(:line)} OptionParser registration outside a named method is unsupported"
        end

        dynamic_context = dynamic?(spellings) ? dynamic_loop(call.fetch(:method_node), call.fetch(:line)) : nil
        expand_dynamic_spellings(spellings, dynamic_context).map do |effective_spellings|
          declaration(relative, call, spellings, effective_spellings, dynamic_context)
        end
      end

      def declaration(relative, call, spellings, effective_spellings, dynamic_context)
        source_primary = spellings.first
        primary = dynamic?(spellings) ? effective_spellings.first : source_primary
        identifier = "#{relative}##{call.fetch(:method)}##{primary}"
        surface = SURFACE_OVERRIDES.fetch(identifier) { SURFACES[[relative, call.fetch(:method)]] }
        raise "#{identifier} has no reviewed command surface mapping" unless surface

        Declaration.new(
          id: identifier,
          source: relative,
          method_name: call.fetch(:method),
          line: call.fetch(:line),
          registration_api: call.fetch(:api),
          declaration_sha256: digest_ast(call.fetch(:arguments)),
          context_sha256: dynamic_context ? digest_ast(dynamic_context) : nil,
          surface: surface,
          declared_spellings: spellings,
          spellings: expand_boolean_spellings(effective_spellings),
          source_value_type: argument_value_type(call.fetch(:arguments), spellings)
        )
      end

      def walk(node, current_method, method_node, calls, option_parser_scope)
        return unless node.is_a?(Array)

        if node.first == :class
          nested_scope = option_parser_scope || contains_constant?(node[2], "OptionParser")
          node.drop(3).each { |child| walk(child, current_method, method_node, calls, nested_scope) }
          return
        end

        if node.first == :def
          name = node.fetch(1).fetch(1)
          node.drop(2).each { |child| walk(child, name, node, calls, option_parser_scope) }
          return
        end

        call = reflective_registration_call(node) || registration_call(node)
        if call && (call.fetch(:reflective, false) || REGISTRATION_APIS.include?(call.fetch(:api)))
          calls << call.merge(
            method: current_method, method_node: method_node, option_parser_scope: option_parser_scope
          )
        end
        node.each do |child|
          walk(child, current_method, method_node, calls, option_parser_scope) if child.is_a?(Array)
        end
      end

      def registration_call(node)
        case node.first
        when :method_add_arg
          call_target(node[1], node.dig(2, 1))
        when :command_call
          build_call(node[3], node[1], node[4], false)
        when :command
          build_call(node[1], nil, node[2], true)
        when :vcall
          build_call(node[1], nil, nil, true)
        end
      end

      def reflective_registration_call(node)
        call = registration_call(node)
        return unless call

        return reflective_send_call(call) if REFLECTIVE_SEND_APIS.include?(call.fetch(:api))
        return reflective_method_reference(call) if BOUND_METHOD_APIS.include?(call.fetch(:api))
        return reflective_method_reference(call, unbound: true) if UNBOUND_METHOD_APIS.include?(call.fetch(:api))
        return unless call.fetch(:api) == "call"

        reference = registration_call(call[:receiver])
        return unless reference && BOUND_METHOD_APIS.include?(reference.fetch(:api))

        reflective_call(reference, call.fetch(:arguments), call.fetch(:splat))
      end

      def reflective_send_call(call)
        selector = call.fetch(:arguments).first
        api = static_reflective_name(selector)
        return if api && !REGISTRATION_APIS.include?(api)

        reflective_call(call, call.fetch(:arguments).drop(1), call.fetch(:splat), api: api)
      end

      def reflective_method_reference(call, unbound: false)
        api = static_reflective_name(call.fetch(:arguments).first)
        return if api && !REGISTRATION_APIS.include?(api)

        call.merge(api: api, arguments: [], reflective: true, unbound: unbound)
      end

      def reflective_call(reference, arguments, splat, api: nil)
        selector = reference.fetch(:arguments).first
        api ||= static_reflective_name(selector)
        return if api && !REGISTRATION_APIS.include?(api)

        reference.merge(api: api, arguments: arguments, splat: splat || reference.fetch(:splat), reflective: true)
      end

      def static_reflective_name(node)
        return render_string(node) if node&.first == :string_literal
        return unless node&.first == :symbol_literal

        token = node.dig(1, 1)
        token[1] if token.is_a?(Array) && token.first.to_s.start_with?("@")
      end

      def call_target(target, arguments_node)
        return unless target.is_a?(Array)

        case target.first
        when :call
          build_call(target[3], target[1], arguments_node, false)
        when :fcall
          build_call(target[1], nil, arguments_node, true)
        end
      end

      def build_call(method_token, receiver, arguments_node, implicit)
        return unless method_token.is_a?(Array) && method_token.first == :@ident

        arguments = static_arguments(arguments_node)
        {
          api: method_token[1], line: method_token.dig(2, 0), receiver: receiver, implicit: implicit,
          arguments: arguments, splat: contains_node?(arguments_node, :args_add_star)
        }
      end

      def static_arguments(node)
        return [] unless node.is_a?(Array)
        return node[1] if node.first == :args_add_block && node[1].is_a?(Array) && node[1].first.is_a?(Array)

        []
      end

      def registration_candidate?(relative, call)
        return true unless option_spellings(call.fetch(:arguments)).empty?
        return true if call.fetch(:option_parser_scope)
        return true if call.fetch(:implicit) && SURFACES.key?([relative, call[:method]])
        return receiver_option_parser_class?(relative, call) if call.fetch(:unbound, false)

        receiver_option_parser?(relative, call)
      end

      def constant_path_name(node)
        return unless node.is_a?(Array)

        case node.first
        when :var_ref
          node.dig(1, 1) if node.dig(1, 0) == :@const
        when :top_const_ref
          node.dig(1, 1)
        when :const_path_ref
          parent = constant_path_name(node[1])
          child = node.dig(2, 1)
          [parent, child].compact.join("::")
        end
      end

      def receiver_option_parser?(relative, call)
        receiver = call[:receiver]
        return false unless receiver.is_a?(Array)

        class_bindings, instance_bindings = option_parser_bindings(relative, call)
        return true if option_parser_instance_expression?(receiver, class_bindings)

        binding = receiver_binding_name(receiver)
        binding && instance_bindings.include?(binding)
      end

      def receiver_option_parser_class?(relative, call)
        receiver = call[:receiver]
        return false unless receiver.is_a?(Array)

        class_bindings, = option_parser_bindings(relative, call)
        class_bindings.include?(receiver_binding_name(receiver))
      end

      def option_parser_bindings(relative, call)
        assignments = binding_assignments(call)
        classes = option_parser_class_bindings(assignments)
        instances = option_parser_parameter_bindings(relative, call)
        instances.concat(option_parser_block_parameters(call[:method_node], classes).map { |name| "local:#{name}" })
        loop do
          previous = instances.length
          assignments.each do |target, value|
            source = receiver_binding_name(value)
            if (source && instances.include?(source)) || option_parser_instance_expression?(value, classes)
              instances << target
            end
          end
          instances.uniq!
          return [classes, instances] if previous == instances.length
        end
      end

      def option_parser_class_bindings(assignments)
        classes = ["constant:OptionParser"]
        loop do
          previous = classes.length
          assignments.each do |target, value|
            source = receiver_binding_name(value)
            classes << target if source && classes.include?(source)
          end
          classes.uniq!
          return classes if previous == classes.length
        end
      end

      def option_parser_parameter_bindings(relative, call)
        names = method_parameter_names(call[:method_node])
        positions = REVIEWED_OPTION_PARSER_PARAMETER_POSITIONS.fetch([relative, call[:method]], [])
        reviewed = positions.filter_map { |position| names[position] }
        ambiguous = names.grep(/\A(?:option_parser|options?|opts?|parser)\z/)
        (reviewed + ambiguous).uniq.map { |name| "local:#{name}" }
      end

      def method_parameter_names(node)
        parameters = node&.dig(2)
        parameters = parameters[1] if parameters&.first == :paren
        required_parameter_names(parameters)
      end

      def binding_assignments(call)
        method_assignments = collect_binding_assignments(call[:method_node]).select do |target, _value|
          target.start_with?("local:")
        end
        source_assignments = collect_binding_assignments(call[:source_node])
        source_assignments.reject! { |target, _value| target.start_with?("local:") } if call[:method_node]
        (method_assignments + source_assignments).uniq
      end

      def collect_binding_assignments(node, found = [])
        return found unless node.is_a?(Array)

        if %i[assign opassign].include?(node.first)
          target = assignment_binding_name(node[1])
          value = node.first == :assign ? node[2] : node[3]
          found << [target, value] if target
        end
        node.each { |child| collect_binding_assignments(child, found) if child.is_a?(Array) }
        found
      end

      def assignment_binding_name(node)
        return unless node.is_a?(Array)

        case node.first
        when :var_field
          binding_token_name(node[1])
        when :const_path_field
          parent = constant_path_name(node[1])
          "constant:#{[parent, node.dig(2, 1)].compact.join('::')}"
        when :top_const_field
          "constant:#{node.dig(1, 1)}"
        end
      end

      def receiver_binding_name(node)
        return unless node.is_a?(Array)

        case node.first
        when :var_ref, :vcall
          binding_token_name(node[1])
        when :const_path_ref
          "constant:#{constant_path_name(node)}"
        when :top_const_ref
          "constant:#{node.dig(1, 1)}"
        end
      end

      def binding_token_name(token)
        return unless token.is_a?(Array)

        kind = {
          :@ident => "local", :@ivar => "instance", :@cvar => "class", :@gvar => "global", :@const => "constant"
        }[token.first]
        "#{kind}:#{token[1]}" if kind
      end

      def option_parser_instance_expression?(node, class_bindings)
        return false unless node.is_a?(Array)

        return option_parser_instance_expression?(node[1], class_bindings) if node.first == :method_add_arg
        return option_parser_instance_expression?(node[1], class_bindings) if node.first == :method_add_block
        return false unless node.first == :call

        api = node.dig(3, 1)
        receiver = node[1]
        return class_bindings.include?(receiver_binding_name(receiver)) if api == "new"
        return false unless %w[itself freeze tap].include?(api)

        option_parser_instance_expression?(receiver, class_bindings)
      end

      def option_parser_block_parameters(node, class_bindings = ["constant:OptionParser"], found = [])
        return found unless node.is_a?(Array)

        if node.first == :method_add_block && option_parser_instance_expression?(node[1], class_bindings)
          params = node.dig(2, 1, 1)
          found.concat(required_parameter_names(params))
        end
        node.each { |child| option_parser_block_parameters(child, class_bindings, found) if child.is_a?(Array) }
        found
      end

      def required_parameter_names(node)
        return [] unless node&.first == :params

        Array(node[1]).filter_map { |token| token[1] if token&.first == :@ident }
      end

      def contains_constant?(node, name)
        return false unless node.is_a?(Array)
        return true if node.first == :@const && node[1] == name

        node.any? { |child| contains_constant?(child, name) }
      end

      def contains_node?(node, kind)
        return false unless node.is_a?(Array)
        return true if node.first == kind

        node.any? { |child| contains_node?(child, kind) }
      end

      def option_spellings(arguments)
        arguments.filter_map do |argument|
          rendered = render_string(argument)
          rendered if rendered&.start_with?("-")
        end
      end

      def argument_value_type(arguments, spellings)
        joined = spellings.join(" ")
        return "boolean" if joined.include?("[no-]")
        return "optional string or boolean" if joined.match?(/\[(?:=)?[A-Z]/)
        return "integer" if arguments.any? { |argument| constant_name(argument) == "Integer" }
        return "float" if arguments.any? { |argument| constant_name(argument) == "Float" }
        return "integer" if joined.match?(/=(?:N|PERCENT|SECONDS)\b/)
        return "enum" if arguments.any? { |argument| argument.is_a?(Array) && argument.first == :array }
        return "enum" if arguments.any? { |argument| constant_path?(argument) }
        return "boolean" unless joined.match?(/(?:=| )[A-Z]/)

        "string"
      end

      def constant_name(node)
        return unless node.is_a?(Array) && node.first == :var_ref && node.dig(1, 0) == :@const

        node.dig(1, 1)
      end

      def constant_path?(node)
        node.is_a?(Array) && %i[const_path_ref top_const_ref].include?(node.first)
      end

      def render_string(node)
        return unless node.is_a?(Array) && node.first == :string_literal

        content = node[1]
        return "" unless content&.first == :string_content

        content.drop(1).map do |part|
          case part.first
          when :@tstring_content
            part[1]
          when :string_embexpr
            token = find_identifier(part)
            token ? "\#{#{token}}" : "\#{...}"
          else
            ""
          end
        end.join
      end

      def find_identifier(node)
        return unless node.is_a?(Array)
        return node[1] if node.first == :@ident

        node.each do |child|
          found = find_identifier(child)
          return found if found
        end
        nil
      end

      def dynamic?(spellings)
        spellings.any? { |spelling| spelling.include?("\#{") }
      end

      def expand_dynamic_spellings(spellings, dynamic_context)
        return [spellings] unless dynamic?(spellings)

        raise "dynamic OptionParser declaration is not inside a static Hash#each loop" unless dynamic_context

        names = hash_string_keys(dynamic_context.dig(1, 1))
        raise "dynamic OptionParser declaration has no statically enumerable names" if names.empty?

        names.map do |name|
          spellings.map { |spelling| spelling.gsub(/\#\{[a-z_][a-z0-9_]*\}/, name) }
        end
      end

      def expand_boolean_spellings(spellings)
        spellings.flat_map do |spelling|
          if spelling.start_with?("--[no-]")
            suffix = spelling.delete_prefix("--[no-]")
            ["--#{suffix}", "--no-#{suffix}"]
          else
            spelling
          end
        end
      end

      def dynamic_loop(node, target_line)
        return unless node.is_a?(Array)

        if node.first == :method_add_block && node.dig(1, 0) == :call && node.dig(1, 3, 1) == "each" &&
           option_line?(node[2], target_line)
          return node
        end

        node.each do |child|
          found = dynamic_loop(child, target_line)
          return found if found
        end
        nil
      end

      def option_line?(node, target_line)
        return false unless node.is_a?(Array)
        return true if node.first == :@ident && REGISTRATION_APIS.include?(node[1]) && node.dig(2, 0) == target_line

        node.any? { |child| option_line?(child, target_line) }
      end

      def hash_string_keys(node, found = [])
        return found unless node.is_a?(Array)

        if node.first == :assoc_new
          value = render_string(node[1])
          found << value if value
        end
        node.each { |child| hash_string_keys(child, found) if child.is_a?(Array) }
        found
      end

      def digest_ast(node)
        Digest::SHA256.hexdigest(Marshal.dump(strip_positions(node)))
      end

      def strip_positions(node)
        return node unless node.is_a?(Array)
        return node.take(2) if node.first.to_s.start_with?("@")

        node.map { |child| strip_positions(child) }
      end

      def load_inventory
        value = YAML.safe_load(File.binread(@registry), permitted_classes: [], permitted_symbols: [], aliases: false)
        raise "configuration inventory root must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "cannot load configuration inventory: #{e.message}"
      end

      def exact_keys!(mapping, expected, label)
        raise "#{label} must be a mapping" unless mapping.is_a?(Hash)

        actual = mapping.keys
        return if actual.sort == expected.sort

        raise "#{label} keys must be exactly #{expected.join(', ')}; got #{actual.join(', ')}"
      end

      def verify_exact_coverage(entries, declarations)
        ids = entries.map { |entry| entry.fetch("id", nil) }
        duplicates = ids.tally.select { |_id, count| count > 1 }.keys
        raise "configuration inventory duplicate registrations: #{duplicates.join(', ')}" unless duplicates.empty?

        expected = declarations.map(&:id)
        missing = expected - ids
        extra = ids - expected
        return if missing.empty? && extra.empty?

        raise "configuration inventory coverage drift; missing=#{missing.join(',')} extra=#{extra.join(',')}"
      end

      def verify_entries(entries, declarations)
        entries.each do |entry|
          id = entry.fetch("id", "unknown")
          exact_keys!(entry, ENTRY_KEYS, "registration #{id}")
          declaration = declarations.fetch(id)
          verify_source_binding(entry, declaration)
          verify_classification(entry)
        end
      end

      def verify_source_binding(entry, declaration)
        id = entry.fetch("id")
        {
          "source" => declaration.source,
          "method" => declaration.method_name,
          "line" => declaration.line,
          "registration_api" => declaration.registration_api,
          "declaration_sha256" => declaration.declaration_sha256,
          "context_sha256" => declaration.context_sha256,
          "surface" => declaration.surface,
          "declared_spellings" => declaration.declared_spellings,
          "effective_spellings" => declaration.spellings,
          "source_value_type" => declaration.source_value_type
        }.each do |field, expected|
          raise "registration #{id} #{field} drift" unless entry.fetch(field) == expected
        end
        unless entry.fetch("declaration_sha256").match?(SHA256)
          raise "registration #{id} declaration_sha256 must be SHA-256"
        end
        return unless declaration.context_sha256 && !entry.fetch("context_sha256").to_s.match?(SHA256)

        raise "registration #{id} dynamic declaration must bind its enclosing method"
      end

      def verify_classification(entry)
        id = entry.fetch("id")
        nonempty_string!(entry.fetch("surface"), id, "surface")
        spellings = entry.fetch("effective_spellings")
        unless spellings.is_a?(Array) && !spellings.empty? && spellings.all? do |value|
          value.is_a?(String) && value.start_with?("-")
        end
          raise "registration #{id} effective_spellings must be a non-empty option array"
        end
        raise "registration #{id} effective_spellings must be unique" unless spellings.uniq == spellings

        key = entry.fetch("canonical_key")
        raise "registration #{id} has an unclassified canonical key" unless key.is_a?(String) && key.match?(KEY)

        %w[value_type value_domain default public_contract_effect trust_implications].each do |field|
          nonempty_string!(entry.fetch(field), id, field)
        end
        stages = entry.fetch("affected_stages")
        unless stages.is_a?(Array) && !stages.empty? && stages.all? { |stage| stage.is_a?(String) && !stage.empty? }
          raise "registration #{id} affected_stages must be a non-empty string array"
        end

        enum!(entry, "owner_class", OWNER_CLASSES)
        enum!(entry, "value_type", SEMANTIC_VALUE_TYPES)
        enum!(entry, "grammar_admission", ADMISSION_RESULTS)
        enum!(entry, "override_algebra", OVERRIDE_ALGEBRAS)
        enum!(entry, "ir_presence", IR_PRESENCE)
        enum!(entry, "manifest_presence", MANIFEST_PRESENCE)
        enum!(entry, "compatibility_status", COMPATIBILITY_STATES)
        verify_owner_policy(entry)
      end

      def verify_owner_policy(entry)
        id = entry.fetch("id")
        owner = entry.fetch("owner_class")
        admission = entry.fetch("grammar_admission")
        override = entry.fetch("override_algebra")
        ir = entry.fetch("ir_presence")
        manifest = entry.fetch("manifest_presence")
        compatibility = entry.fetch("compatibility_status")
        case owner
        when "grammar_contract"
          raise "registration #{id} grammar contract must pass A1-A8" unless admission == "admitted_a1_a8"
          unless %w[fixed staged_fixed_compatibility analysis_override].include?(override)
            raise "registration #{id} grammar contract has invalid override algebra"
          end
          raise "registration #{id} grammar contract must record its IR state" if ir == "not_persisted"
          unless %w[current current_gap].include?(manifest)
            raise "registration #{id} grammar contract must record its manifest state"
          end

          expected_persistence = GRAMMAR_CONTRACT_PERSISTENCE[entry.fetch("canonical_key")]
          unless expected_persistence == [ir, manifest]
            raise "registration #{id} grammar contract IR/manifest persistence is inconsistent"
          end
        when "grammar_minimum"
          unless admission == "admitted_a1_a8" && override == "minimum" && ir != "not_persisted" &&
                 %w[current current_gap].include?(manifest) && compatibility == "current"
            raise "registration #{id} grammar minimum policy fields are inconsistent"
          end
        when "project_build_policy"
          expected_manifest = entry.fetch("canonical_key") == "companion.manifest" ? "not_applicable" : "current"
          unless admission == "excluded_x5_packaging_or_deployment" && override == "project_selection" &&
                 ir == "not_persisted" && manifest == expected_manifest &&
                 %w[current obsolete_alias].include?(compatibility)
            raise "registration #{id} project build policy fields are inconsistent"
          end
        when "invocation_request"
          allowed = ADMISSION_RESULTS - %w[admitted_a1_a8 excluded_x5_packaging_or_deployment]
          unless allowed.include?(admission) && override == "invocation_only" && ir == "not_persisted" &&
                 manifest == "not_applicable" && %w[current internal_compatibility].include?(compatibility)
            raise "registration #{id} invocation request fields are inconsistent"
          end
        end
        verify_compatibility_policy(entry)
      end

      def verify_compatibility_policy(entry)
        id = entry.fetch("id")
        owner = entry.fetch("owner_class")
        override = entry.fetch("override_algebra")
        status = entry.fetch("compatibility_status")
        if status == "staged_compatibility"
          unless owner == "grammar_contract" && override == "staged_fixed_compatibility"
            raise "registration #{id} staged compatibility requires a staged grammar contract"
          end
        elsif override == "staged_fixed_compatibility"
          raise "registration #{id} staged fixed override must expose staged compatibility"
        end
        if status == "internal_compatibility" &&
           (owner != "invocation_request" || !entry.fetch("canonical_key").start_with?("compatibility."))
          raise "registration #{id} internal compatibility must be a compatibility invocation"
        end
        if entry.fetch("canonical_key").start_with?("compatibility.") && status != "internal_compatibility"
          raise "registration #{id} compatibility invocation must remain internal compatibility"
        end
        if override == "fixed" && entry.fetch("surface") != "generate"
          raise "registration #{id} fixed generation policy must use the generate surface"
        end
        return unless override == "analysis_override" && entry.fetch("surface") == "generate"

        raise "registration #{id} analysis override cannot use the generate surface"
      end

      def verify_aliases(entries)
        by_surface = entries.group_by { |entry| entry.fetch("surface") }
        by_surface.each do |surface, surface_entries|
          spellings = {}
          surface_entries.each do |entry|
            entry.fetch("effective_spellings").each do |spelling|
              normalized = spelling.sub(/(?:\[?=|\s)[A-Z][A-Z0-9_-]*\]?\z/, "")
              previous = spellings[normalized]
              if previous && previous.fetch("canonical_key") != entry.fetch("canonical_key")
                raise "surface #{surface} alias #{normalized} maps to multiple canonical concepts"
              end

              spellings[normalized] = entry
            end
          end
        end
        obsolete = entries.select { |entry| entry.fetch("compatibility_status") == "obsolete_alias" }
        obsolete.each do |entry|
          matches = entries.reject { |candidate| candidate.equal?(entry) }.select do |candidate|
            candidate.fetch("surface") == entry.fetch("surface") &&
              candidate.fetch("canonical_key") == entry.fetch("canonical_key") &&
              candidate.fetch("owner_class") == entry.fetch("owner_class") &&
              candidate.fetch("compatibility_status") == "current"
          end
          raise "obsolete alias #{entry.fetch('id')} must point to a canonical registration" if matches.empty?
        end
      end

      def verify_document!(entries)
        expected = render(entries)
        actual = File.binread(@document)
        return if actual == expected

        raise "declarative configuration documentation is stale; regenerate it from the inventory"
      end

      def nonempty_string!(value, id, field)
        return if value.is_a?(String) && !value.strip.empty?

        raise "registration #{id} #{field} must be a non-empty string"
      end

      def enum!(entry, field, allowed)
        value = entry.fetch(field)
        return if allowed.include?(value)

        raise "registration #{entry.fetch('id')} #{field} must be one of #{allowed.join(', ')}"
      end

      def cell(value)
        value.to_s.gsub("|", "\\|").gsub("\n", " ")
      end

      def markdown_row(values)
        "| #{values.join(' | ')} |"
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/PredicateMethod
  end
end

if $PROGRAM_NAME == __FILE__
  inventory = Ibex::Quality::ConfigurationInventory.new
  case ARGV.fetch(0, "check")
  when "check"
    inventory.verify!
  when "render"
    inventory.write_document!
  else
    warn "usage: ruby tool/quality/configuration_inventory.rb [check|render]"
    exit 64
  end
end
