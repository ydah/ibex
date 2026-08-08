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
        ["lib/ibex/cli/config.rb", "add_config_contract_options"] => "config",
        ["lib/ibex/cli/config.rb", "add_config_options"] => "config",
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
        ["lib/ibex/cli/config.rb", "add_config_contract_options"] => [0],
        ["lib/ibex/cli/config.rb", "add_config_options"] => [0],
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
        "parser.algorithm" => %w[grammar_ir_v3_parser_contract current],
        "parser.entries" => %w[grammar_ir_v3_parser_contract current],
        "cst.trivia" => %w[grammar_ir_v3_parser_contract current]
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
        grammar_ir_v3_parser_contract
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
          "A parser/options-style helper parameter is a conservative OptionParser signal.",
          "A static literal beginning with `-` on any otherwise-unproven receiver is deliberately rejected;",
          "this enforced conservative restriction has no scope-bound exclusion registry.",
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
          "This D001 artifact is inventory-only and adds no grammar syntax. " \
          "The D002 typed effective-configuration model",
          "consumes these canonical classifications without changing the inventory's admission decisions. D006 admits",
          "root-only extended syntax for parser algorithm and entry construction; it does not turn the inventory into",
          "a generic CLI key-value language.",
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
          markdown_row(["`parser.algorithm`, `parser.entries`", "Grammar Contract",
                        "fixed generation / explicit algorithm analysis override",
                        "root `parser` syntax writes Grammar IR v3; manifest records contract and construction facts"]),
          markdown_row(["`cst.trivia`", "Grammar Contract", "fixed generation / explicit analysis override",
                        "root `parser` syntax writes Grammar IR v3; manifest records contract and CST facts"]),
          markdown_row(["table/runtime/debug/source mapping/companions", "Project Build Policy", "project selection",
                        "manifest records current generation choices"]),
          markdown_row(["emit/path/watch/report/budget/locale/help/warnings", "Invocation Request", "invocation only",
                        "excluded from Grammar IR"]),
          "",
          "Fixed means a grammar declaration may be matched but not silently contradicted by generation CLI.",
          "Analysis commands and grammar tests may choose a different algorithm only as an explicit, reported",
          "noncanonical override; parser entry construction remains fixed.",
          "Grammar IR v3 closes persistence for the first-wave construction and CST concepts. The root-only `parser`",
          "block exposes `parser.algorithm`, `parser.entries`, and `cst_trivia` as source syntax and requires the",
          "existing `pragma cst` compatibility declaration; declaration-free grammars retain the current default.",
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
        index = build_source_index
        bindings = build_option_parser_bindings(index)
        calls = index.fetch(:calls).select { |call| registration_candidate?(call, bindings) }
        values = calls.flat_map { |call| declarations_for_call(call.fetch(:source), call) }.sort_by(&:id)
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

      def build_source_index
        index = {
          calls: [], assignments: [], methods: [], blocks: [], constant_definitions: ["OptionParser"],
          constant_aliases: {}, local_definitions: [], class_variable_definitions: [],
          superclass_references: [], superclasses: {}, sequence: 0
        }
        source_trees = source_paths.to_h do |relative|
          source = File.binread(path(relative))
          sexp = Ripper.sexp(source)
          raise "cannot parse production Ruby source #{relative}" unless sexp

          [relative, sexp]
        end
        preindex_constant_definitions(source_trees, index)
        source_trees.each do |relative, sexp|
          context = lexical_context(source: relative)
          walk(sexp, context, index)
        end
        finalize_superclasses(index)
        index
      end

      def preindex_constant_definitions(source_trees, index)
        declarations = []
        source_trees.each do |source, sexp|
          discover_constant_declarations(sexp, nil, declarations, source)
        end
        owners = Array.new(declarations.length)
        aliases = {}
        converged = false
        (declarations.length + 2).times do
          candidate_index = index.merge(
            constant_definitions: (["OptionParser"] + owners.compact).uniq,
            constant_aliases: aliases
          )
          resolved = declarations.map do |declaration|
            parent_id = declaration.fetch(:parent_id)
            next if parent_id && !owners[parent_id]

            parent = parent_id ? owners.fetch(parent_id) : nil
            raw_constant_declaration_owner(declaration, parent, candidate_index)
          end
          resolved_aliases = constant_identity_aliases(declarations, resolved, owners, candidate_index)
          if resolved == owners && resolved_aliases == aliases
            converged = true
            break
          end

          owners = resolved
          aliases = resolved_aliases
        end
        raise "constant namespace owner index did not converge" unless converged

        index[:constant_definitions] = (["OptionParser"] + owners.compact).uniq
        index[:constant_aliases] = aliases
      end

      def discover_constant_declarations(node, parent_id, declarations, source)
        return unless node.is_a?(Array)

        if %i[class module].include?(node.first)
          declaration_id = declarations.length
          declarations << { kind: :namespace, node: node[1], parent_id: parent_id, source: source }
          body = node.first == :class ? node[3] : node[2]
          discover_constant_declarations(body, declaration_id, declarations, source)
          return
        end
        if node.first == :sclass
          discover_constant_declarations(node[2], parent_id, declarations, source)
          return
        end
        if %i[assign opassign].include?(node.first) && constant_assignment_target?(node[1])
          conditional = node.first == :opassign && node.dig(2, 1) == "||="
          value = node.first == :assign ? node[2] : node[3] if node.first == :assign || conditional
          declarations << {
            kind: :assignment, node: node[1], value: value, parent_id: parent_id, conditional: conditional,
            source: source
          }
        end
        node.each do |child|
          discover_constant_declarations(child, parent_id, declarations, source) if child.is_a?(Array)
        end
      end

      def constant_assignment_target?(node)
        return false unless node.is_a?(Array)
        return true if %i[const_path_field top_const_field].include?(node.first)

        node.first == :var_field && node.dig(1, 0) == :@const
      end

      def raw_constant_declaration_owner(declaration, parent, index)
        node = declaration.fetch(:node)
        return lexical_owner(node, parent, index) if declaration.fetch(:kind) == :namespace

        case node.first
        when :var_field
          name = node.dig(1, 1)
          parent ? "#{parent}::#{name}" : name
        when :const_path_field
          resolve_qualified_assignment(constant_path_name(node), parent, index)
        when :top_const_field
          node.dig(1, 1)
        end
      end

      def constant_identity_aliases(declarations, resolved, previous_owners, index)
        grouped = declarations.each_index.group_by { |declaration_id| resolved[declaration_id] }
        grouped.each_with_object({}) do |(owner, declaration_ids), aliases|
          next unless owner

          sources = declaration_ids.group_by { |declaration_id| declarations.fetch(declaration_id).fetch(:source) }
          state = if sources.one?
                    ordered_constant_identity_state(
                      declaration_ids, declarations, previous_owners, index
                    )
                  else
                    cross_file_constant_identity_state(
                      sources.values, declarations, previous_owners, index
                    )
                  end
          aliases[owner] = state.fetch(1) if state&.first == :identity && state.fetch(1) != owner
        end
      end

      def ordered_constant_identity_state(declaration_ids, declarations, previous_owners, index)
        declaration_ids.each_with_object([:unset]) do |declaration_id, state|
          declaration = declarations.fetch(declaration_id)
          next state.replace([:truthy]) if declaration.fetch(:kind) == :namespace

          assigned = constant_assignment_state(declaration, previous_owners, index)
          state.replace(ordered_assignment_state(state, assigned, declaration.fetch(:conditional)))
        end
      end

      def ordered_assignment_state(current, assigned, conditional)
        kind = current.is_a?(Array) ? current.first : current
        if [true, "||="].include?(conditional)
          return assigned if %i[unset falsey].include?(kind)
          return :may_parser if kind == :unknown && %i[parser may_parser].include?(assigned)

          return current
        end
        if conditional == "&&="
          return current if %i[unset falsey].include?(kind)
          return and_assignment_unknown_state(assigned) if kind == :unknown
          return and_assignment_may_parser_state(assigned) if kind == :may_parser
        end

        assigned
      end

      def and_assignment_unknown_state(assigned)
        return :falsey if assigned == :falsey
        return :may_parser if %i[parser may_parser].include?(assigned)

        :unknown
      end

      def and_assignment_may_parser_state(assigned)
        return :falsey if assigned == :falsey
        return :may_parser if %i[parser may_parser unknown].include?(assigned)

        :unknown
      end

      def cross_file_constant_identity_state(source_declaration_ids, declarations, previous_owners, index)
        return [:unknown] unless source_declaration_ids.flatten.all? do |declaration_id|
          declaration = declarations.fetch(declaration_id)
          declaration.fetch(:kind) == :assignment && declaration.fetch(:conditional)
        end

        states = source_declaration_ids.map do |declaration_ids|
          ordered_constant_identity_state(declaration_ids, declarations, previous_owners, index)
        end
        return [:unknown] if states.any? { |state| %i[truthy unknown].include?(state.first) }

        identities = states.filter_map { |state| state.fetch(1) if state.first == :identity }.uniq
        identities.one? ? [:identity, identities.first] : [:unknown]
      end

      def constant_assignment_state(declaration, previous_owners, index)
        value = unwrap_parenthesized_expression(declaration[:value])
        return [:falsey] if falsey_literal?(value)

        parent_id = declaration.fetch(:parent_id)
        parent = parent_id ? previous_owners[parent_id] : nil
        return [:unknown] if parent_id && !parent

        target = resolve_constant_node(value, { owner: parent }, index)
        return [:identity, target] if target
        return [:truthy] if constant_path_name(value) || definitely_truthy_expression?(value)

        [:unknown]
      end

      def falsey_literal?(node)
        node = unwrap_parenthesized_expression(node)
        node&.first == :var_ref && node.dig(1, 0) == :@kw && %w[false nil].include?(node.dig(1, 1))
      end

      def definitely_truthy_expression?(node)
        node = unwrap_parenthesized_expression(node)
        return false unless node.is_a?(Array)
        return true if %i[array hash string_literal symbol_literal].include?(node.first)
        return true if node.first.to_s.match?(/\A@(?:int|float|rational|imaginary|CHAR)\z/)
        return true if node.first == :var_ref && node.dig(1, 0) == :@kw && node.dig(1, 1) == "true"

        node.first == :call && node.dig(3, 1) == "new"
      end

      def finalize_superclasses(index)
        index.fetch(:superclass_references).each do |reference|
          superclass = resolve_constant_node(reference.fetch(:node), reference.fetch(:context), index)
          index.fetch(:superclasses)[reference.fetch(:owner)] = superclass if superclass
        end
      end

      def lexical_context(source:, owner: nil, method: nil, method_node: nil, scope: nil, role: :singleton,
                          singleton_class: false, scope_chain: nil)
        resolved_scope = scope || "#{source}:top"
        {
          source: source, owner: owner, method: method, method_node: method_node,
          scope: resolved_scope, scope_chain: scope_chain || [resolved_scope], role: role,
          singleton_class: singleton_class
        }
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

      def walk(node, context, index)
        return unless node.is_a?(Array)

        if node.first == :class
          owner = lexical_owner(node[1], context[:owner], index)
          index.fetch(:constant_definitions) << owner
          index.fetch(:superclass_references) << { owner: owner, node: node[2], context: context } if node[2]
          nested = context.merge(
            owner: owner, method: nil, method_node: nil, scope: "#{context[:source]}:#{owner}:body", role: :singleton,
            scope_chain: ["#{context[:source]}:#{owner}:body"], singleton_class: false
          )
          walk(node[3], nested, index)
          return
        end

        if node.first == :module
          owner = lexical_owner(node[1], context[:owner], index)
          index.fetch(:constant_definitions) << owner
          nested = context.merge(
            owner: owner, method: nil, method_node: nil, scope: "#{context[:source]}:#{owner}:body", role: :singleton,
            scope_chain: ["#{context[:source]}:#{owner}:body"], singleton_class: false
          )
          walk(node[2], nested, index)
          return
        end

        if node.first == :sclass
          owner = singleton_definition_owner(node[1], context, index)
          nested = context.merge(
            owner: owner, method: nil, method_node: nil, role: :singleton,
            scope: "#{context[:source]}:#{owner}:singleton", scope_chain: ["#{context[:source]}:#{owner}:singleton"],
            singleton_class: true
          )
          walk(node[2], nested, index)
          return
        end

        if node.first == :def
          name = node.fetch(1).fetch(1)
          role = context[:singleton_class] ? :singleton : :instance
          nested = method_context(context, node, name, role)
          parameters = method_parameters(node)
          index_parameters(parameters, nested, index)
          index.fetch(:methods) << nested.merge(parameters: parameters.fetch(:names))
          node.drop(2).each { |child| walk(child, nested, index) }
          return
        end

        if node.first == :defs
          name = node.fetch(3).fetch(1)
          owner = singleton_definition_owner(node[1], context, index)
          nested = method_context(context.merge(owner: owner), node, name, :singleton, token: node[3])
          parameters = singleton_method_parameters(node)
          index_parameters(parameters, nested, index)
          index.fetch(:methods) << nested.merge(parameters: parameters.fetch(:names))
          node.drop(4).each { |child| walk(child, nested, index) }
          return
        end

        if node.first == :method_add_block
          walk_block(node, context, index)
          return
        end

        if %i[assign opassign].include?(node.first)
          walk_assignment(node, context, index)
          return
        end

        call = reflective_registration_call(node) || registration_call(node)
        if call && (call.fetch(:reflective, false) || REGISTRATION_APIS.include?(call.fetch(:api)))
          index.fetch(:calls) << call.merge(context).merge(order: next_index_order(index))
        end
        node.each do |child|
          walk(child, context, index) if child.is_a?(Array)
        end
      end

      def walk_assignment(node, context, index)
        target = node[1]
        value = node.first == :assign ? node[2] : node[3]
        walk(target, context, index)

        value_context = context
        operator = node.dig(2, 1) if node.first == :opassign
        if %w[||= &&=].include?(operator)
          guard = {
            targets: assignment_binding_names(target, context, index),
            order: next_index_order(index), operator: operator
          }
          guards = context.fetch(:execution_guards, []) + [guard]
          value_context = context.merge(execution_guards: guards)
        end
        walk(value, value_context, index)
        record_assignment(node, context, index)
      end

      def method_context(context, node, name, role, token: node[1])
        line = token.dig(2, 0)
        owner = context[:owner] || "Object"
        separator = role == :instance ? "#" : "."
        context.merge(
          method: name, method_node: node, scope: "#{context[:source]}:#{line}:#{owner}#{separator}#{name}",
          scope_chain: ["#{context[:source]}:#{line}:#{owner}#{separator}#{name}"], role: role,
          singleton_class: role == :singleton
        )
      end

      def singleton_method_parameters(node)
        parameters = node[4]
        parameters = parameters[1] if parameters&.first == :paren
        parameter_details(parameters)
      end

      def singleton_definition_owner(target, context, index)
        if target&.first == :var_ref && target.dig(1, 0) == :@kw && target.dig(1, 1) == "self"
          return context[:owner] || "Object"
        end

        resolve_constant_node(target, context, index) || lexical_owner(target, context[:owner], index)
      end

      def lexical_owner(node, parent, index)
        name = constant_path_name(node)
        return parent || "Object" unless name
        return canonical_constant_name(name.delete_prefix("::"), index) if absolute_constant_name?(name)
        return canonical_constant_name(name, index) unless parent
        return canonical_constant_name("#{parent}::#{name}", index) unless name.include?("::")

        namespace = name.rpartition("::").first
        lexical_namespace = nearest_defined_constant(namespace, parent, index)
        owner = lexical_namespace ? "#{lexical_namespace}::#{name.split('::').last}" : name
        canonical_constant_name(owner, index)
      end

      def record_assignment(node, context, index)
        return unless %i[assign opassign].include?(node.first)

        value = node.first == :assign ? node[2] : node[3]
        operator = node.dig(2, 1) if node.first == :opassign
        conditional = %w[||= &&=].include?(operator) ? operator : false
        assignment_binding_names(node[1], context, index).each do |target|
          index.fetch(:assignments) << {
            target: target, value: value, context: context, conditional: conditional,
            order: next_index_order(index), parameter_default: false
          }
          index.fetch(:constant_definitions) << target.delete_prefix("constant:") if target.start_with?("constant:")
          if target.start_with?("class_variable:")
            index.fetch(:class_variable_definitions) << target
          elsif target.start_with?("local:")
            index.fetch(:local_definitions) << target
          end
        end
      end

      def walk_block(node, context, index)
        walk(node[1], context, index)
        block_variables = node.dig(2, 1)
        params = block_variables&.first == :block_var ? block_variables[1] : nil
        block_locals = block_variables&.first == :block_var ? block_variables[2] : nil
        parameters = parameter_details(params, block_locals: block_locals)
        if block_variables.nil?
          implicit = implicit_block_parameter_names(node.dig(2, 2))
          parameters[:names] = (parameters.fetch(:names) + implicit).uniq
          parameters[:yielded_names] = implicit
        end
        line = find_line(node[1]) || 0
        scope = "#{context[:scope]}:block:#{line}:#{index.fetch(:blocks).length}"
        nested = context.merge(scope: scope, scope_chain: [scope] + context.fetch(:scope_chain))
        index_parameters(parameters, nested, index)
        index.fetch(:blocks) << {
          node: node, expression: node[1], parameters: parameters.fetch(:names),
          yielded_parameters: parameters.fetch(:yielded_names),
          falsey_parameters: parameters.fetch(:falsey_names),
          truthy_parameters: parameters.fetch(:truthy_names),
          block_locals: parameters.fetch(:block_local_names), context: nested
        }
        walk(node[2], nested, index)
      end

      def implicit_block_parameter_names(node, names = [])
        return names unless node.is_a?(Array)
        return names if %i[class module sclass def defs].include?(node.first)

        if node.first == :method_add_block
          implicit_block_parameter_names(node[1], names)
          return names
        end

        token = node[1] if %i[var_ref vcall].include?(node.first)
        names << token[1] if token&.first == :@ident && %w[_1 it].include?(token[1])
        node.each { |child| implicit_block_parameter_names(child, names) if child.is_a?(Array) }
        names.uniq
      end

      def find_line(node)
        return unless node.is_a?(Array)
        return node.dig(2, 0) if node.first.to_s.start_with?("@")

        node.each do |child|
          line = find_line(child)
          return line if line
        end
        nil
      end

      def next_index_order(index)
        index[:sequence] += 1
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

      def build_option_parser_bindings(index)
        assignments = index.fetch(:assignments)
        classes = option_parser_class_bindings(assignments, index)
        instances = option_parser_parameter_bindings(index.fetch(:methods))
        blocks = index.fetch(:blocks)
        block_scopes = blocks.to_h { |block| [block.fetch(:context).fetch(:scope), true] }
        assignments_by_scope = assignments.group_by { |assignment| assignment.fetch(:context).fetch(:scope) }
        loop do
          previous = instances.length
          add_assignment_instance_bindings(assignments, block_scopes, classes, instances, index)
          add_block_instance_bindings(blocks, assignments_by_scope, classes, instances, index)
          instances.uniq!
          return { classes: classes, instances: instances, index: index } if previous == instances.length
        end
      end

      def add_assignment_instance_bindings(assignments, block_scopes, classes, instances, index)
        assignments.each do |assignment|
          context = assignment.fetch(:context)
          block_local = assignment.fetch(:target).start_with?("local:#{context.fetch(:scope)}:") &&
                        block_scopes.key?(context.fetch(:scope))
          next if block_local && assignment.fetch(:conditional, false)

          value = assignment.fetch(:value)
          instances << assignment.fetch(:target) if option_parser_instance_expression?(
            value, context, classes, instances, index
          )
        end
      end

      def add_block_instance_bindings(blocks, assignments_by_scope, classes, instances, index)
        blocks.each do |block|
          context = block.fetch(:context)
          yielding = option_parser_yielding_expression?(
            block.fetch(:expression), context, classes, instances, index
          )
          block.fetch(:yielded_parameters).each do |name|
            instances << local_binding(context, name) if yielding
          end
          assignments = assignments_by_scope.fetch(context.fetch(:scope), [])
          states = block_instance_states(
            block, classes, instances, index, seed_yielded: yielding, assignments: assignments
          )
          states.each { |binding, state| instances << binding if %i[parser may_parser].include?(state) }
        end
      end

      def registration_candidate?(call, bindings)
        return false unless call_execution_reachable?(call, bindings)
        return true unless option_spellings(call.fetch(:arguments)).empty?
        return true if option_parser_subclass_registration?(call, bindings)
        return true if call.fetch(:implicit) && SURFACES.key?([call.fetch(:source), call[:method]])
        return receiver_option_parser_class?(call, bindings) if call.fetch(:unbound, false)

        receiver_option_parser?(call, bindings)
      end

      def call_execution_reachable?(call, bindings)
        guards = call.fetch(:execution_guards, [])
        return true if guards.empty?

        index = bindings.fetch(:index)
        block = index.fetch(:blocks).find do |candidate|
          candidate.fetch(:context).fetch(:scope) == call.fetch(:scope)
        end
        return true unless block

        yielding = option_parser_yielding_expression?(
          block.fetch(:expression), block.fetch(:context), bindings.fetch(:classes), bindings.fetch(:instances), index
        )
        guards.all? do |guard|
          states = block_instance_states(
            block, bindings.fetch(:classes), bindings.fetch(:instances), index,
            seed_yielded: yielding, before_order: guard.fetch(:order)
          )
          guard_execution_reachable?(guard, states)
        end
      end

      def guard_execution_reachable?(guard, states)
        kinds = guard.fetch(:targets).map { |target| states.fetch(target, :unset) }
        case guard.fetch(:operator)
        when "||=" then kinds.none? { |kind| %i[parser truthy].include?(kind) }
        when "&&=" then kinds.none? { |kind| %i[unset falsey].include?(kind) }
        else true
        end
      end

      def constant_path_name(node)
        return unless node.is_a?(Array)

        case node.first
        when :var_ref, :const_ref
          node.dig(1, 1) if node.dig(1, 0) == :@const
        when :top_const_ref, :top_const_field
          "::#{node.dig(1, 1)}"
        when :const_path_ref, :const_path_field
          parent = constant_path_name(node[1])
          child = node.dig(2, 1)
          [parent, child].compact.join("::")
        end
      end

      def receiver_option_parser?(call, bindings)
        receiver = call[:receiver]
        return false unless receiver.is_a?(Array)

        index = bindings.fetch(:index)
        block_local = block_local_receiver_provenance(call, receiver, bindings)
        return block_local unless block_local.nil?

        option_parser_instance_expression?(
          receiver, call, bindings.fetch(:classes), bindings.fetch(:instances), index
        )
      end

      def block_local_receiver_provenance(call, receiver, bindings)
        index = bindings.fetch(:index)
        block = index.fetch(:blocks).find do |candidate|
          candidate.fetch(:context).fetch(:scope) == call.fetch(:scope)
        end
        return unless block

        local_prefix = "local:#{block.fetch(:context).fetch(:scope)}:"
        local_candidates = block_receiver_binding_candidates(receiver, call, index).select do |candidate|
          candidate.start_with?(local_prefix)
        end
        return if local_candidates.empty?

        yielding = option_parser_yielding_expression?(
          block.fetch(:expression), block.fetch(:context), bindings.fetch(:classes), bindings.fetch(:instances), index
        )
        states = block_instance_states(
          block, bindings.fetch(:classes), bindings.fetch(:instances), index,
          seed_yielded: yielding, before_order: call.fetch(:order)
        )
        block_identity_expression?(receiver, block.fetch(:context), states, index)
      end

      def block_receiver_binding_candidates(node, context, index)
        node = unwrap_parenthesized_expression(node)
        candidates = binding_candidates(node, context, index)
        return candidates unless candidates.empty?
        return [] unless node.is_a?(Array)

        if %i[method_add_arg method_add_block].include?(node.first)
          return block_receiver_binding_candidates(node[1], context, index)
        end
        return [] unless node.first == :call && %w[itself freeze tap dup clone].include?(node.dig(3, 1))

        block_receiver_binding_candidates(node[1], context, index)
      end

      def receiver_option_parser_class?(call, bindings)
        receiver = call[:receiver]
        return false unless receiver.is_a?(Array)

        binding_candidates(receiver, call, bindings.fetch(:index)).any? do |candidate|
          bindings.fetch(:classes).include?(candidate)
        end
      end

      def option_parser_class_bindings(assignments, index)
        classes = ["constant:OptionParser"]
        loop do
          previous = classes.length
          assignments.each do |assignment|
            candidates = binding_candidates(assignment.fetch(:value), assignment.fetch(:context), index)
            classes << assignment.fetch(:target) if candidates.any? { |candidate| classes.include?(candidate) }
          end
          classes.uniq!
          return classes if previous == classes.length
        end
      end

      def option_parser_parameter_bindings(methods)
        methods.flat_map do |method|
          names = method.fetch(:parameters)
          positions = REVIEWED_OPTION_PARSER_PARAMETER_POSITIONS.fetch(
            [method.fetch(:source), method.fetch(:method)], []
          )
          reviewed = positions.filter_map { |position| names[position] }
          ambiguous = names.grep(/\A(?:option_parser|options?|opts?|parser)\z/)
          (reviewed + ambiguous).uniq.map { |name| local_binding(method, name) }
        end.uniq
      end

      def method_parameters(node)
        parameters = node&.dig(2)
        parameters = parameters[1] if parameters&.first == :paren
        parameter_details(parameters)
      end

      def parameter_details(node, block_locals: nil)
        names = []
        defaults = []
        yielded_names = []
        falsey_names = []
        truthy_names = []
        if node&.first == :params
          first_positional = Array(node[1]).first || Array(node[2]).first&.first
          first_positional_name = parameter_name(first_positional)
          yielded_names << first_positional_name if first_positional_name
          required_names = parameter_names(node[1])
          names.concat(required_names)
          falsey_names.concat(required_names - yielded_names)
          Array(node[2]).each do |token, value|
            name = parameter_name(token)
            names << name if name
            defaults << { name: name, value: value } if name
          end
          rest_names = parameter_names(node[3])
          names.concat(rest_names)
          truthy_names.concat(rest_names)
          post_names = parameter_names(node[4])
          names.concat(post_names)
          falsey_names.concat(post_names)
          Array(node[5]).each do |token, value|
            name = parameter_name(token)
            names << name if name
            defaults << { name: name, value: value } if name && value != false
          end
          names.concat(parameter_names(node[6]))
          names.concat(parameter_names(node[7]))
        end
        block_local_names = parameter_names(block_locals)
        names.concat(block_local_names)
        {
          names: names.uniq, defaults: defaults, yielded_names: yielded_names,
          falsey_names: falsey_names, truthy_names: truthy_names, block_local_names: block_local_names
        }
      end

      def parameter_names(node)
        return [] unless node.is_a?(Array)

        name = parameter_name(node)
        return [name] if name

        node.flat_map { |child| parameter_names(child) }.uniq
      end

      def parameter_name(node)
        return unless node.is_a?(Array)
        return node[1] if node.first == :@ident
        return node[1].delete_suffix(":") if node.first == :@label

        parameter_name(node[1]) if %i[rest_param kwrest_param blockarg].include?(node.first)
      end

      def index_parameters(parameters, context, index)
        parameters.fetch(:names).each do |name|
          index.fetch(:local_definitions) << local_binding(context, name)
        end
        parameters.fetch(:defaults).each do |default|
          index.fetch(:assignments) << {
            target: local_binding(context, default.fetch(:name)), value: default.fetch(:value), context: context,
            conditional: false, order: next_index_order(index), parameter_default: true
          }
        end
      end

      def assignment_binding_names(node, context, index)
        return [] unless node.is_a?(Array)

        case node.first
        when :var_field
          [assignment_token_name(node[1], context, index)].compact
        when :const_path_field
          name = constant_path_name(node)
          ["constant:#{resolve_qualified_assignment(name, context[:owner], index)}"]
        when :top_const_field
          ["constant:#{node.dig(1, 1)}"]
        else []
        end
      end

      def binding_candidates(node, context, index)
        node = unwrap_parenthesized_expression(node)
        return [] unless node.is_a?(Array)

        case node.first
        when :var_ref, :vcall
          reference_token_names(node[1], context, index)
        when :const_path_ref
          resolved = resolve_constant_name(constant_path_name(node), context[:owner], index)
          resolved ? ["constant:#{resolved}"] : []
        when :top_const_ref
          ["constant:#{node.dig(1, 1)}"]
        else
          []
        end || []
      end

      def assignment_token_name(token, context, index)
        return unless token.is_a?(Array)

        case token.first
        when :@ident then local_assignment_binding(context, token[1], index)
        when :@ivar then ivar_binding(context, token[1])
        when :@cvar then class_variable_binding(context, token[1], index)
        when :@gvar then "global:#{token[1]}"
        when :@const then qualified_constant_binding(context[:owner], token[1])
        end
      end

      def reference_token_names(token, context, index)
        return [] unless token.is_a?(Array)

        case token.first
        when :@ident then [local_reference_binding(context, token[1], index)]
        when :@ivar then [ivar_binding(context, token[1])]
        when :@cvar then [class_variable_binding(context, token[1], index)]
        when :@gvar then ["global:#{token[1]}"]
        when :@const
          resolved = resolve_constant_name(token[1], context[:owner], index)
          resolved ? ["constant:#{resolved}"] : []
        else []
        end
      end

      def local_binding(context, name)
        "local:#{context.fetch(:scope)}:#{name}"
      end

      def local_reference_binding(context, name, index)
        context.fetch(:scope_chain).each do |scope|
          binding = "local:#{scope}:#{name}"
          return binding if index.fetch(:local_definitions).include?(binding)
        end
        local_binding(context, name)
      end

      def local_assignment_binding(context, name, index)
        local_reference_binding(context, name, index)
      end

      def ivar_binding(context, name)
        owner = context[:owner] || "Object"
        separator = context[:role] == :instance ? "#" : "."
        "instance_variable:#{owner}#{separator}#{name}"
      end

      def qualified_constant_binding(owner, name)
        "constant:#{owner ? "#{owner}::#{name}" : name}"
      end

      def resolve_constant_node(node, context, index)
        name = constant_path_name(node)
        resolve_constant_name(name, context[:owner], index) if name
      end

      def resolve_constant_name(name, owner, index)
        return unless name

        definitions = index.fetch(:constant_definitions)
        if absolute_constant_name?(name)
          absolute = name.delete_prefix("::")
          canonical = canonical_constant_name(absolute, index)
          return canonical if definitions.include?(absolute) || definitions.include?(canonical)

          return
        end
        candidate = constant_search_names(name, owner, index).find do |value|
          definitions.include?(value) || definitions.include?(canonical_constant_name(value, index))
        end
        canonical_constant_name(candidate, index) if candidate
      end

      def constant_search_names(name, owner, index)
        if name.include?("::")
          namespace, _, leaf = name.rpartition("::")
          resolved_namespace = resolve_constant_name(namespace, owner, index)
          qualified = "#{resolved_namespace}::#{leaf}" if resolved_namespace
          return [qualified, name].compact.uniq
        end

        lexical = lexical_owner_chain(owner).map { |candidate| "#{candidate}::#{name}" }
        inherited = ancestor_chain(owner, index).map { |ancestor| "#{ancestor}::#{name}" }
        (lexical + inherited + [name]).uniq
      end

      def resolve_qualified_assignment(name, owner, index)
        if absolute_constant_name?(name)
          namespace, _, leaf = name.delete_prefix("::").rpartition("::")
          return "#{canonical_constant_name(namespace, index)}::#{leaf}"
        end

        namespace, _, leaf = name.rpartition("::")
        resolved_namespace = resolve_constant_name(namespace, owner, index)
        canonical_namespace = canonical_constant_name(resolved_namespace || namespace, index)
        "#{canonical_namespace}::#{leaf}"
      end

      def absolute_constant_name?(name)
        name.start_with?("::")
      end

      def canonical_constant_name(name, index)
        return name unless name

        aliases = index.fetch(:constant_aliases)
        seen = []
        current = name
        loop do
          return current if seen.include?(current)

          seen << current
          prefixes = aliases.keys.select do |candidate|
            current == candidate || current.start_with?("#{candidate}::")
          end
          prefix = prefixes.max_by(&:length)
          return current unless prefix

          current = "#{aliases.fetch(prefix)}#{current.delete_prefix(prefix)}"
        end
      end

      def nearest_defined_constant(name, owner, index)
        resolve_constant_name(name, owner, index)
      end

      def lexical_owner_chain(owner)
        values = []
        current = owner
        while current
          values << current
          current = current.include?("::") ? current.rpartition("::").first : nil
        end
        values
      end

      def ancestor_chain(owner, index)
        values = []
        current = owner
        seen = []
        while current && !seen.include?(current)
          seen << current
          current = index.fetch(:superclasses)[current]
          values << current if current
        end
        values
      end

      def class_variable_binding(context, name, index)
        owner = context[:owner] || "Object"
        candidates = [owner, *ancestor_chain(owner, index)].map { |candidate| "class_variable:#{candidate}:#{name}" }
        existing = candidates.find { |candidate| index.fetch(:class_variable_definitions).include?(candidate) }
        existing || candidates.first
      end

      def option_parser_subclass_registration?(call, bindings)
        return false unless call.fetch(:implicit) || self_receiver?(call[:receiver])

        option_parser_subclass_instance_context?(call, bindings.fetch(:classes), bindings.fetch(:index))
      end

      def option_parser_subclass_instance_context?(context, class_bindings, index)
        return false unless context.fetch(:role) == :instance

        ancestor_chain(context[:owner], index).any? { |ancestor| class_bindings.include?("constant:#{ancestor}") }
      end

      def self_receiver?(node)
        node = unwrap_parenthesized_expression(node)
        node&.first == :var_ref && node.dig(1, 0) == :@kw && node.dig(1, 1) == "self"
      end

      def option_parser_instance_expression?(node, context, class_bindings, instance_bindings, index)
        node = unwrap_parenthesized_expression(node)
        return false unless node.is_a?(Array)
        return true if self_receiver?(node) && option_parser_subclass_instance_context?(context, class_bindings, index)
        return true if binding_candidates(node, context, index).any? { |binding| instance_bindings.include?(binding) }

        if node.first == :method_add_block
          return true if identity_returning_builder_block?(node, class_bindings, instance_bindings, index)

          return option_parser_instance_expression?(node[1], context, class_bindings, instance_bindings, index)
        end
        if node.first == :method_add_arg
          return option_parser_instance_expression?(node[1], context, class_bindings, instance_bindings, index)
        end
        return false unless node.first == :call

        api = node.dig(3, 1)
        receiver = node[1]
        if api == "new"
          return binding_candidates(receiver, context, index).any? { |candidate| class_bindings.include?(candidate) }
        end
        return false unless %w[itself freeze tap dup clone].include?(api)

        option_parser_instance_expression?(receiver, context, class_bindings, instance_bindings, index)
      end

      def option_parser_yielding_expression?(node, context, class_bindings, instance_bindings, index)
        node = unwrap_parenthesized_expression(node)
        node = unwrap_parenthesized_expression(node[1]) while node&.first == :method_add_arg
        return false unless node&.first == :call

        api = node.dig(3, 1)
        if api == "new"
          return option_parser_instance_expression?(node, context, class_bindings, instance_bindings, index)
        end
        return false unless %w[tap then yield_self].include?(api)

        option_parser_instance_expression?(node[1], context, class_bindings, instance_bindings, index)
      end

      def identity_returning_builder_block?(node, class_bindings, instance_bindings, index)
        block = index.fetch(:blocks).find { |candidate| candidate.fetch(:node).equal?(node) }
        return false unless block

        expression = unwrap_parenthesized_expression(block.fetch(:expression))
        expression = unwrap_parenthesized_expression(expression[1]) while expression&.first == :method_add_arg
        return false unless expression&.first == :call && %w[then yield_self].include?(expression.dig(3, 1))
        return false unless option_parser_yielding_expression?(
          block.fetch(:expression), block.fetch(:context), class_bindings, instance_bindings, index
        )

        returned = unwrap_parenthesized_expression(block_last_expression(node))
        states = block_instance_states(block, class_bindings, instance_bindings, index, seed_yielded: true)
        block_identity_expression?(returned, block.fetch(:context), states, index)
      end

      def block_instance_states(block, class_bindings, instance_bindings, index, seed_yielded:,
                                assignments: index.fetch(:assignments), before_order: nil)
        context = block.fetch(:context)
        states = block.fetch(:parameters).to_h { |name| [local_binding(context, name), :unknown] }
        if seed_yielded
          block.fetch(:falsey_parameters).each { |name| states[local_binding(context, name)] = :falsey }
          block.fetch(:truthy_parameters).each { |name| states[local_binding(context, name)] = :truthy }
        end
        block.fetch(:block_locals).each { |name| states[local_binding(context, name)] = :falsey }
        yielded_bindings = block.fetch(:yielded_parameters).map { |name| local_binding(context, name) }
        block.fetch(:yielded_parameters).each do |name|
          states[local_binding(context, name)] = :parser if seed_yielded
        end
        assignments.each do |assignment|
          next unless assignment.fetch(:context).fetch(:scope) == context.fetch(:scope)
          next if before_order && assignment.fetch(:order) >= before_order

          target = assignment.fetch(:target)
          next unless target.start_with?("local:#{context.fetch(:scope)}:")
          next if seed_yielded && assignment.fetch(:parameter_default, false) && yielded_bindings.include?(target)

          assigned = block_assignment_state(
            assignment.fetch(:value), context, states, class_bindings, instance_bindings, index
          )
          states[target] = ordered_assignment_state(
            states.fetch(target, :unset), assigned, assignment.fetch(:conditional, false)
          )
        end
        states
      end

      def block_assignment_state(node, context, states, class_bindings, instance_bindings, index)
        node = unwrap_parenthesized_expression(node)
        local_state = block_local_expression_state(node, context, states, index)
        return local_state if local_state && local_state != :unknown
        return :parser if option_parser_instance_expression?(
          node, context, class_bindings, instance_bindings, index
        )
        return :falsey if falsey_literal?(node)
        return :truthy if constant_path_name(node) || definitely_truthy_expression?(node)

        candidates = binding_candidates(node, context, index)
        candidates.each { |binding| return states.fetch(binding) if states.key?(binding) }
        :unknown
      end

      def block_local_expression_state(node, context, states, index)
        candidates = block_receiver_binding_candidates(node, context, index)
        local_states = candidates.filter_map { |binding| states[binding] if states.key?(binding) }
        return if local_states.empty?
        return :parser if local_states.include?(:parser)
        return :may_parser if local_states.include?(:may_parser)

        local_states.find { |state| state != :unknown } || :unknown
      end

      def block_identity_expression?(node, context, states, index)
        %i[parser may_parser].include?(block_local_expression_state(node, context, states, index))
      end

      def block_last_expression(node)
        body = node.dig(2, 2)
        body = body[1] if body&.first == :bodystmt
        body&.last
      end

      def unwrap_parenthesized_expression(node)
        while node.is_a?(Array) && node.first == :paren
          expressions = node[1]
          break unless expressions.is_a?(Array) && !expressions.empty?

          node = expressions.last
        end
        node
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
        if override == "fixed" && !%w[generate config].include?(entry.fetch("surface"))
          raise "registration #{id} fixed policy must use the generate or config surface"
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
