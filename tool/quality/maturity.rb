# frozen_string_literal: true

require "date"
require "digest"
require "open3"
require "pathname"
require "set"
require "yaml"

require_relative "maturity_authority"

module Ibex
  module Quality
    # rubocop:disable Metrics/ClassLength -- one validator owns the closed maturity audit and its public projections.
    # Validates the Preview/Experimental inventory, evidence, and generated public summary.
    class Maturity
      ROOT = File.expand_path("../..", __dir__)
      REVISION = /\A[0-9a-f]{40}\z/
      SHA256 = /\A[0-9a-f]{64}\z/
      ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      REVIEWED_REVISION = MaturityAuthority::REVIEWED_REVISION
      RELEASES = MaturityAuthority::RELEASES
      SNAPSHOTS = MaturityAuthority::SNAPSHOTS
      INTRODUCTION_AUTHORITIES = MaturityAuthority::INTRODUCTIONS
      SEMANTIC_COMMIT_AUTHORITIES = MaturityAuthority::SEMANTIC_COMMITS
      STABLE_OVERLAPS = MaturityAuthority::STABLE_OVERLAPS
      EXPECTED = {
        "ebnf-groups" => "preview",
        "parameterized-rules" => "preview",
        "inline-rules" => "preview",
        "middle-actions" => "preview",
        "multiple-entries" => "preview",
        "canonical-imports" => "preview",
        "generated-lexers" => "preview",
        "semantic-locations-types" => "preview",
        "ast-generation" => "preview",
        "grammar-tests" => "preview",
        "documentation-tooling" => "preview",
        "ielr" => "preview",
        "lsp" => "preview",
        "watch" => "preview",
        "debug" => "preview",
        "coverage" => "preview",
        "browser-playground" => "preview",
        "action-shadow" => "preview",
        "bounded-repair" => "experimental",
        "incremental-cst" => "experimental"
      }.freeze
      ROOT_KEYS = %w[schema_version audit budgets release_dependencies features].freeze
      FEATURE_KEYS = %w[
        id name maturity activation external_use specification_history issue_audit documentation
        dependent_tooling limitations decision next_review release_gate sources
      ].freeze
      BUDGET_KEYS = %w[
        active_new_preview_tracks preview_track_limit active_grammar_syntax_tracks grammar_syntax_track_limit
        experimental_product_features experimental_product_limit
      ].freeze
      WORKLOAD_FEATURES = {
        "generated-lexers" => %w[generated_lexer],
        "semantic-locations-types" => %w[locations typed_symbols]
      }.freeze
      CANONICAL_SOURCES = {
        "ebnf-groups" => %w[lib/ibex/normalize/expander.rb],
        "parameterized-rules" => %w[lib/ibex/normalize/parameters.rb],
        "inline-rules" => %w[lib/ibex/normalize/inline_expansion.rb],
        "middle-actions" => %w[lib/ibex/frontend/parser/rules.rb lib/ibex/normalize/expander.rb],
        "multiple-entries" => %w[lib/ibex/codegen/ruby.rb],
        "canonical-imports" => %w[lib/ibex/frontend/resolver.rb],
        "generated-lexers" => %w[lib/ibex/runtime/generated_lexer.rb],
        "semantic-locations-types" => %w[
          lib/ibex/codegen/rbs.rb lib/ibex/codegen/ruby.rb lib/ibex/frontend/generated_parser_metadata.rb
          lib/ibex/runtime/parser.rb
        ],
        "ast-generation" => %w[lib/ibex/codegen/ruby_ast.rb],
        "grammar-tests" => %w[lib/ibex/grammar_tests.rb],
        "documentation-tooling" => %w[lib/ibex/codegen/documentation.rb],
        "ielr" => %w[lib/ibex/lalr/builder.rb],
        "lsp" => %w[lib/ibex/lsp/server.rb],
        "watch" => %w[lib/ibex/watch/runner.rb],
        "debug" => %w[lib/ibex/table_simulation.rb],
        "coverage" => %w[lib/ibex/coverage/collector.rb],
        "browser-playground" => %w[site/playground/analyzer.rb],
        "action-shadow" => %w[lib/ibex/codegen/action_method_source.rb],
        "bounded-repair" => %w[lib/ibex/runtime/repair.rb],
        "incremental-cst" => %w[lib/ibex/runtime/cst/incremental/session.rb]
      }.freeze
      ACTIVATION_SURFACES = {
        "ebnf-groups" => [["extended-grammar", "extended", false]],
        "parameterized-rules" => [["extended-grammar", "extended", false]],
        "inline-rules" => [["extended-grammar", "extended", false]],
        "middle-actions" => [["embedded-production-action", "compatible", true]],
        "multiple-entries" => [["multiple-start-declarations", "extended", false]],
        "canonical-imports" => [["import-declarations", "extended", false]],
        "generated-lexers" => [["lexer-declarations", "extended", false]],
        "semantic-locations-types" => [
          ["semantic-locations", "compatible", true],
          ["semantic-type-declarations", "extended", false]
        ],
        "ast-generation" => [["node-declarations", "extended", false]],
        "grammar-tests" => [["grammar-test-command", "explicit_command", false]],
        "documentation-tooling" => [["documentation-command", "explicit_command", false]],
        "ielr" => [["ielr-algorithm", "explicit_option", false]],
        "lsp" => [["lsp-command", "explicit_command", false]],
        "watch" => [["watch-option", "explicit_option", false]],
        "debug" => [["debug-command", "explicit_command", false]],
        "coverage" => [["coverage-command", "explicit_command", false]],
        "browser-playground" => [["browser-application", "explicit_application", false]],
        "action-shadow" => [["action-shadow-output", "explicit_option", false]],
        "bounded-repair" => [["repair-policy", "explicit_api", false]],
        "incremental-cst" => [["incremental-session", "explicit_api", false]]
      }.freeze
      EXPECTED_DECISIONS = EXPECTED.keys.to_h do |id|
        [id, %w[middle-actions semantic-locations-types].include?(id) ? "redesign" : "keep"]
      end.freeze
      SUMMARY_START = "<!-- maturity-summary:start -->"
      SUMMARY_END = "<!-- maturity-summary:end -->"
      COMMIT_ASSESSMENT_CLASSIFICATIONS = %w[
        semantic_change no_semantic_change internal_refactor docs_test_only
      ].freeze
      CONTRACT_EFFECT_REQUIREMENTS = {
        "semantic_change" => [
          /public .*?(?:syntax|API|output|runtime|behavior|contract)/i,
          "semantic commit effect must identify a public contract change"
        ],
        "no_semantic_change" => [
          /public contract (?:is|remains) unchanged/i,
          "no-change effect must state that the public contract is unchanged"
        ],
        "internal_refactor" => [
          /preserv(?:e|es|ing) the public contract/i,
          "refactor effect must state that it preserves the public contract"
        ],
        "docs_test_only" => [
          /executable behavior (?:is|remains) unchanged/i,
          "docs/test effect must state that executable behavior is unchanged"
        ]
      }.freeze

      class << self
        def pickaxe_revision(root, reviewed_revision, relative_path, query)
          @pickaxe_cache ||= {}
          key = [root, reviewed_revision, relative_path, query]
          @pickaxe_cache.fetch(key) do
            output, error, status = Open3.capture3(
              "git", "-C", root, "log", "--reverse", "--format=%H", "-S#{query}", reviewed_revision, "--",
              relative_path
            )
            raise "cannot reconstruct introduction: #{error.strip}" unless status.success?

            @pickaxe_cache[key] = output.lines(chomp: true).first
          end
        end

        def path_commits(root, from_revision, to_revision, paths)
          @path_commit_cache ||= {}
          key = [root, from_revision, to_revision, paths]
          @path_commit_cache.fetch(key) do
            output, error, status = Open3.capture3(
              "git", "-C", root, "log", "--reverse", "--format=%H", "#{from_revision}..#{to_revision}", "--",
              *paths
            )
            raise "cannot reconstruct semantic history: #{error.strip}" unless status.success?

            @path_commit_cache[key] = output.lines(chomp: true)
          end
        end

        def commit_subject(root, revision)
          @commit_subject_cache ||= {}
          key = [root, revision]
          @commit_subject_cache.fetch(key) do
            output, error, status = Open3.capture3("git", "-C", root, "show", "-s", "--format=%s", revision)
            raise "cannot read commit subject: #{error.strip}" unless status.success?

            @commit_subject_cache[key] = output.strip
          end
        end

        def commit_paths(root, revision)
          @commit_paths_cache ||= {}
          key = [root, revision]
          @commit_paths_cache.fetch(key) do
            output, error, status = Open3.capture3(
              "git", "-C", root, "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", revision
            )
            raise "cannot read commit paths: #{error.strip}" unless status.success?

            @commit_paths_cache[key] = output.lines(chomp: true)
          end
        end

        def first_parent(root, revision)
          @parent_cache ||= {}
          key = [root, revision]
          @parent_cache.fetch(key) do
            output, error, status = Open3.capture3("git", "-C", root, "rev-parse", "#{revision}^")
            raise "cannot resolve introduction parent: #{error.strip}" unless status.success?

            @parent_cache[key] = output.strip
          end
        end
      end

      def initialize(root: ROOT, registry: nil, narrative: nil, stability: nil, today: Date.today)
        @root = File.expand_path(root)
        @registry = registry || path("docs/maturity.yml")
        @narrative = narrative || path("docs/maturity.md")
        @stability = stability || path("docs/stability.md")
        @today = today
      end

      def verify!
        document = load_yaml(@registry)
        exact_keys!(document, ROOT_KEYS, "registry")
        raise "maturity registry schema_version must be 1" unless document.fetch("schema_version") == 1

        audit = verify_audit(document.fetch("audit"))
        dependencies = verify_release_dependencies(document.fetch("release_dependencies"))
        workloads = load_workloads
        features = verify_features(document.fetch("features"), audit, dependencies, workloads)
        verify_budgets(document.fetch("budgets"), features)
        verify_public_summary(features, document.fetch("budgets"), dependencies)
        true
      rescue KeyError => e
        raise "invalid maturity registry: #{e.message}"
      end

      private

      def load_yaml(file)
        value = YAML.safe_load_file(file, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise "#{relative(file)} root must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "#{relative(file)} YAML is invalid: #{e.message}"
      end

      def verify_audit(audit)
        exact_keys!(audit, %w[reviewed_at reviewed_repository_revision issue_audits], "audit")
        reviewed_at = date!(audit.fetch("reviewed_at"), "audit reviewed_at")
        raise "maturity review date cannot be in the future" if reviewed_at > @today

        @reviewed_revision = audit.fetch("reviewed_repository_revision")
        revision!(@reviewed_revision, "audit reviewed_repository_revision")
        raise "maturity audit must remain bound to the reviewed pre-H001 authority" unless
          @reviewed_revision == REVIEWED_REVISION

        load_reviewed_history
        verify_release_tags
        issue_audits = audit.fetch("issue_audits")
        record_array!(issue_audits, "issue audits")
        issue_audits.each { |entry| verify_issue_audit(entry, audit.fetch("reviewed_at")) }
        issue_audits.to_h { |entry| [entry.fetch("id"), entry] }
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- provenance is one closed record.
      def verify_issue_audit(entry, reviewed_at)
        exact_keys!(entry, %w[id provider repository query command source checked_at fresh_until result], "issue audit")
        id!(entry.fetch("id"), "issue audit id")
        raise "issue audit provider must be github_search_api" unless entry.fetch("provider") == "github_search_api"
        raise "issue audit repository must be ydah/ibex" unless entry.fetch("repository") == "ydah/ibex"

        expected_query = "repo:ydah/ibex is:issue is:open"
        raise "issue audit query must cover every open repository issue" unless entry.fetch("query") == expected_query

        expected_command = "gh api -X GET search/issues -f q='#{expected_query}' -f per_page=100"
        raise "issue audit command must be reproducible and exact" unless entry.fetch("command") == expected_command

        expected_source = "https://api.github.com/search/issues?q=repo%3Aydah%2Fibex+is%3Aissue+is%3Aopen"
        raise "issue audit source must be the canonical API query" unless entry.fetch("source") == expected_source

        checked = date!(entry.fetch("checked_at"), "issue audit checked_at")
        fresh_until = date!(entry.fetch("fresh_until"), "issue audit fresh_until")
        raise "issue audit predates the maturity review" if checked < Date.iso8601(reviewed_at)
        raise "issue audit checked_at cannot be in the future" if checked > @today
        raise "issue audit checked_at must not follow fresh_until" if checked > fresh_until
        raise "issue audit freshness window must be 30 days or less" if (fresh_until - checked).to_i > 30
        raise "issue audit is stale; rerun the exact query and review every result" if fresh_until < @today

        verify_issue_result(entry.fetch("result"))
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- closed result validation.
      def verify_issue_result(result)
        exact_keys!(result, %w[status total_count incomplete_results issues limitation], "issue audit result")
        raise "issue audit result status must be complete" unless result.fetch("status") == "complete"

        count = result.fetch("total_count")
        raise "issue audit total_count must be a non-negative integer" unless count.is_a?(Integer) && count >= 0
        unless result.fetch("incomplete_results") == false
          raise "incomplete GitHub issue results cannot support a maturity decision"
        end

        issues = result.fetch("issues")
        raise "issue audit issues must be an array" unless issues.is_a?(Array)

        issues.each { |issue| verify_issue_disposition(issue) }
        numbers = issues.map { |issue| issue.fetch("number") }
        raise "issue audit issue numbers must be ordered unique positive integers" unless
          numbers == numbers.uniq.sort && numbers.all?(&:positive?)
        raise "issue audit count does not match issues" unless issues.length == count

        non_empty_string!(result.fetch("limitation"), "issue audit limitation")
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def verify_issue_disposition(issue)
        exact_keys!(issue, %w[number title url disposition], "issue disposition")
        number = issue.fetch("number")
        raise "issue number must be a positive integer" unless number.is_a?(Integer) && number.positive?

        non_empty_string!(issue.fetch("title"), "issue title")
        expected_url = "https://github.com/ydah/ibex/issues/#{number}"
        raise "issue URL must be canonical" unless issue.fetch("url") == expected_url

        disposition = issue.fetch("disposition")
        exact_keys!(disposition, %w[feature_ids not_applicable_rationale], "issue disposition mapping")
        ids = disposition.fetch("feature_ids")
        string_array!(ids, "issue feature_ids", allow_empty: true)
        raise "issue feature_ids must be unique canonical order" unless ids == ids.uniq.sort

        unknown = ids - EXPECTED.keys
        raise "issue disposition references unknown feature IDs" unless unknown.empty?

        rationale = disposition.fetch("not_applicable_rationale")
        if ids.empty?
          non_empty_string!(rationale, "issue not_applicable_rationale")
        elsif !rationale.nil?
          raise "feature-assigned issue cannot also be not_applicable"
        end
      end

      def load_reviewed_history
        output, error, status = Open3.capture3("git", "-C", @root, "rev-list", "--reverse", @reviewed_revision)
        raise "cannot read reviewed repository history: #{error.strip}" unless status.success?

        revisions = output.lines(chomp: true)
        @reviewed_ancestors = revisions.to_set
        @release_ancestors = RELEASES.to_h do |tag, revision|
          tag_output, tag_error, tag_status = Open3.capture3("git", "-C", @root, "rev-list", revision)
          raise "cannot read release history for #{tag}: #{tag_error.strip}" unless tag_status.success?

          [tag, tag_output.lines(chomp: true).to_set]
        end
      end

      def verify_release_tags
        RELEASES.each do |tag, expected|
          actual, error, status = Open3.capture3("git", "-C", @root, "rev-parse", "#{tag}^{commit}")
          raise "cannot resolve release tag #{tag}: #{error.strip}" unless status.success?
          raise "release tag #{tag} drift" unless actual.strip == expected
          raise "release tag #{tag} is outside reviewed history" unless @reviewed_ancestors.include?(expected)
        end
        chronological = @release_ancestors.fetch("v0.2.0").include?(RELEASES.fetch("v0.1.0"))
        raise "release tag history is not chronological" unless chronological
      end

      def verify_budgets(budgets, features)
        exact_keys!(budgets, BUDGET_KEYS, "budgets")
        expected = {
          "active_new_preview_tracks" => 0,
          "preview_track_limit" => 3,
          "active_grammar_syntax_tracks" => 0,
          "grammar_syntax_track_limit" => 1,
          "experimental_product_features" => 2,
          "experimental_product_limit" => 5
        }
        raise "maturity budgets do not match the reviewed active budget" unless budgets == expected
        raise "experimental feature count and budget statement disagree" unless
          features.count do |feature|
            feature["maturity"] == "experimental"
          end == budgets.fetch("experimental_product_features")
      end

      def verify_release_dependencies(dependencies)
        exact_keys!(dependencies, %w[R001 R002 B003], "release_dependencies")
        expected = {
          "R001" => ["hold_external", "docs/error-ux-review-status-v1.json"],
          "R002" => ["pending_exact_revision", "docs/release-readiness.md"],
          "B003" => ["complete", "docs/workloads.yml"]
        }
        dependencies.each do |id, dependency|
          exact_keys!(dependency, %w[status evidence summary], "#{id} dependency")
          status, evidence = expected.fetch(id)
          raise "#{id} dependency status drift" unless dependency.fetch("status") == status
          raise "#{id} dependency evidence drift" unless dependency.fetch("evidence") == evidence

          verify_existing_path!(evidence, "#{id} dependency evidence")
          non_empty_string!(dependency.fetch("summary"), "#{id} dependency summary")
        end
        dependencies
      end

      def load_workloads
        document = load_yaml(path("docs/workloads.yml"))
        document.fetch("workloads").to_h do |workload|
          [workload.fetch("id"), workload]
        end
      end

      def verify_features(features, audit, dependencies, workloads)
        record_array!(features, "features")
        ids = features.map { |feature| feature.fetch("id") }
        raise "maturity inventory must contain the exact 18 Preview + 2 Experimental features in canonical order" unless
          ids == EXPECTED.keys
        raise "introduction authority inventory drift" unless INTRODUCTION_AUTHORITIES.keys == EXPECTED.keys
        raise "semantic commit authority inventory drift" unless SEMANTIC_COMMIT_AUTHORITIES.keys == EXPECTED.keys

        prepare_history_sources
        features.each { |feature| verify_feature(feature, audit, dependencies, workloads) }
        features
      end

      def prepare_history_sources
        relative_paths = CANONICAL_SOURCES.values.flatten.uniq.sort
        revisions = RELEASES.values + [@reviewed_revision]
        expressions = revisions.product(relative_paths)
        @git_objects = {}
        Open3.popen3("git", "-C", @root, "cat-file", "--batch") do |input, output, error, thread|
          expressions.each { |revision, relative_path| input.puts("#{revision}:#{relative_path}") }
          input.close
          expressions.each { |revision, relative_path| read_history_source(output, revision, relative_path) }
          message = error.read.strip
          raise "cannot read maturity source history: #{message}" unless thread.value.success?
        end
      end

      def read_history_source(output, revision, relative_path)
        header = output.gets&.strip
        fields = header&.split
        if fields&.last == "missing"
          @git_objects[[revision, relative_path]] = nil
          return
        end
        unless fields&.length == 3 && fields.fetch(1) == "blob"
          raise "invalid Git object header for #{revision}:#{relative_path}"
        end

        size = Integer(fields.fetch(2), 10)
        bytes = output.read(size)
        separator = output.read(1)
        raise "invalid Git object stream for #{relative_path}" unless bytes&.bytesize == size && separator == "\n"

        @git_objects[[revision, relative_path]] = bytes
      end

      # -- each evidence family must be checked together to prevent partial records.
      def verify_feature(feature, audit, dependencies, workloads)
        exact_keys!(feature, FEATURE_KEYS, "feature")
        id = feature.fetch("id")
        id!(id, "feature id")
        expected_maturity = EXPECTED.fetch(id)
        unless feature.fetch("maturity") == expected_maturity
          raise "#{id}: maturity drift is a silent promotion or removal"
        end

        non_empty_string!(feature.fetch("name"), "#{id}: name")
        verify_activation(id, feature.fetch("activation"), expected_maturity)
        verify_external_use(id, feature.fetch("external_use"), workloads)
        verify_specification_history(id, feature.fetch("specification_history"))
        verify_feature_issue_audit(id, feature.fetch("issue_audit"), audit)
        verify_documentation(id, feature.fetch("documentation"))
        verify_dependent_tooling(id, feature.fetch("dependent_tooling"))
        verify_limitations(id, feature.fetch("limitations"))
        verify_decision(
          id, feature.fetch("decision"), feature.fetch("external_use"), expected_maturity, dependencies, workloads
        )
        verify_next_review(id, feature.fetch("next_review"))
        verify_release_gate(id, feature.fetch("release_gate"), dependencies)
        verify_sources(id, feature.fetch("sources"))
      end

      def verify_activation(id, activation, _maturity)
        keys = %w[maturity_independent surfaces]
        keys << "stable_overlap" if STABLE_OVERLAPS.key?(id)
        exact_keys!(activation, keys, "#{id}: activation")
        raise "#{id}: activation must be explicitly independent from maturity" unless
          activation.fetch("maturity_independent") == true

        surfaces = activation.fetch("surfaces")
        record_array!(surfaces, "#{id}: activation surfaces")
        actual = surfaces.map do |surface|
          exact_keys!(surface, %w[id availability mechanism default_enabled], "#{id}: activation surface")
          non_empty_string!(surface.fetch("mechanism"), "#{id}: activation mechanism")
          default = surface.fetch("default_enabled")
          raise "#{id}: activation default_enabled must be boolean" unless [true, false].include?(default)

          [surface.fetch("id"), surface.fetch("availability"), default]
        end
        raise "#{id}: activation surfaces drift from the reviewed runtime boundary" unless
          actual == ACTIVATION_SURFACES.fetch(id)

        stable_surface_ids = surfaces.filter_map do |surface|
          surface.fetch("id") if surface.fetch("availability") == "compatible" && surface.fetch("default_enabled")
        end
        verify_stable_overlap(id, activation["stable_overlap"], stable_surface_ids)
      end

      def verify_stable_overlap(id, overlap, stable_surface_ids)
        expected = STABLE_OVERLAPS[id]
        if expected.nil?
          raise "#{id}: default-compatible activation requires Stable guarantee precedence" if stable_surface_ids.any?

          return
        end

        exact_keys!(
          overlap,
          %w[surface_ids governing_maturity breaking_policy guarantee separable_preview_activation],
          "#{id}: stable_overlap"
        )
        raise "#{id}: Stable overlap surface mapping drift" unless
          overlap.fetch("surface_ids") == stable_surface_ids && stable_surface_ids == expected.fetch(:surface_ids)
        raise "#{id}: Stable guarantee must govern default-compatible overlap" unless
          overlap.fetch("governing_maturity") == "stable" &&
          overlap.fetch("breaking_policy") == "stable_compatibility_lock"
        raise "#{id}: Stable overlap guarantee drift" unless overlap.fetch("guarantee") == expected.fetch(:guarantee)
        raise "#{id}: separable Preview activation drift" unless
          overlap.fetch("separable_preview_activation") == expected.fetch(:separable_preview_activation)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- coupled evidence.
      def verify_external_use(id, use, workloads)
        exact_keys!(use, %w[status workload_ids evidence summary], "#{id}: external_use")
        status = use.fetch("status")
        raise "#{id}: external use status must be demonstrated, not_demonstrated, or unknown" unless
          %w[demonstrated not_demonstrated unknown].include?(status)

        ids = use.fetch("workload_ids")
        string_array!(ids, "#{id}: external workload_ids", allow_empty: true)
        missing = ids.reject { |workload_id| workloads.key?(workload_id) }
        raise "#{id}: unknown workload ids #{missing.join(', ')}" unless missing.empty?

        string_array!(use.fetch("evidence"), "#{id}: external use evidence")
        use.fetch("evidence").each { |entry| verify_existing_path!(entry, "#{id}: external use evidence") }
        non_empty_string!(use.fetch("summary"), "#{id}: external use summary")
        if status == "demonstrated"
          raise "#{id}: demonstrated external use requires workload IDs" if ids.empty?

          invalid = ids.reject { |workload_id| workloads.fetch(workload_id).fetch("classification") == "public_real" }
          raise "#{id}: synthetic, repository, or diagnostic workloads cannot prove external use" unless invalid.empty?

          feature_names = WORKLOAD_FEATURES.fetch(id, [id.tr("-", "_")])
          unbound = ids.reject do |workload_id|
            (workloads.fetch(workload_id).fetch("used_features") & feature_names).any?
          end
          raise "#{id}: public workload records do not bind the claimed feature use" unless unbound.empty?
        elsif status == "unknown"
          unless use.fetch("summary").match?(/unknown|not surveyed/i)
            raise "#{id}: unknown external use must state why discovery is incomplete"
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def verify_specification_history(id, history)
        exact_keys!(
          history,
          %w[method introduction first_release snapshots changes unknowns evidence],
          "#{id}: specification_history"
        )
        raise "#{id}: history method must be git_pickaxe_and_source_snapshots_v1" unless
          history.fetch("method") == "git_pickaxe_and_source_snapshots_v1"

        authority = INTRODUCTION_AUTHORITIES.fetch(id)
        introduction = verify_introduction(id, history.fetch("introduction"), authority)
        verify_first_release(id, history.fetch("first_release"), introduction, authority)
        verify_history_snapshots(id, history.fetch("snapshots"), authority)
        verify_history_changes(id, history.fetch("changes"), authority)
        string_array!(history.fetch("unknowns"), "#{id}: specification history unknowns")
        verify_path_array!(history.fetch("evidence"), "#{id}: specification history evidence")
      end

      def verify_introduction(id, introduction, authority)
        exact_keys!(introduction, %w[revision path query summary], "#{id}: introduction")
        revision = introduction.fetch("revision")
        revision!(revision, "#{id}: introduction revision")
        raise "#{id}: introduction is outside reviewed history" unless @reviewed_ancestors.include?(revision)

        expected = authority.values_at(:revision, :path, :query)
        actual = introduction.values_at("revision", "path", "query")
        raise "#{id}: introduction authority drift" unless actual == expected

        relative_path = introduction.fetch("path")
        verify_existing_path!(relative_path, "#{id}: introduction path")
        query = introduction.fetch("query")
        non_empty_string!(query, "#{id}: introduction query")
        non_empty_string!(introduction.fetch("summary"), "#{id}: introduction summary")
        first = self.class.pickaxe_revision(@root, @reviewed_revision, relative_path, query)
        raise "#{id}: introduction revision is not the first pickaxe result" unless first == revision

        revision
      end

      def verify_first_release(id, release, introduction, authority)
        exact_keys!(release, %w[status tag revision], "#{id}: first_release")
        raise "#{id}: every audited feature must name its first release" unless release.fetch("status") == "released"

        expected_tag = authority.fetch(:first_release)
        raise "#{id}: first release tag drift" unless release.fetch("tag") == expected_tag
        raise "#{id}: first release revision drift" unless release.fetch("revision") == RELEASES.fetch(expected_tag)
        raise "#{id}: introduction is not an ancestor of its first release" unless
          @release_ancestors.fetch(expected_tag).include?(introduction)

        earlier_tags = RELEASES.keys.take_while { |tag| tag != expected_tag }
        already_released = earlier_tags.any? { |tag| @release_ancestors.fetch(tag).include?(introduction) }
        raise "#{id}: first release is later than a tag that already contains the introduction" if already_released
      end

      def verify_history_snapshots(id, snapshots, authority)
        record_array!(snapshots, "#{id}: history snapshots")
        raise "#{id}: history snapshots must cover v0.1.0, v0.2.0, and reviewed in order" unless
          snapshots.map { |snapshot| snapshot.fetch("id") } == SNAPSHOTS.keys

        snapshots.each_with_index do |snapshot, index|
          exact_keys!(
            snapshot, %w[id revision feature_status canonical_presence source_tree_sha256], "#{id}: history snapshot"
          )
          revision = SNAPSHOTS.fetch(snapshot.fetch("id"))
          raise "#{id}: snapshot revision drift" unless snapshot.fetch("revision") == revision

          expected_status = authority.fetch(:feature_status).fetch(index)
          raise "#{id}: snapshot feature presence drift" unless snapshot.fetch("feature_status") == expected_status

          verify_canonical_presence(
            id, snapshot.fetch("canonical_presence"), revision, expected_status, authority, index
          )

          digest!(snapshot.fetch("source_tree_sha256"), "#{id}: snapshot source tree digest")
          actual_digest = historical_source_tree_digest(id, revision)
          raise "#{id}: snapshot source tree digest drift" unless snapshot.fetch("source_tree_sha256") == actual_digest
        end
        snapshots
      end

      def verify_canonical_presence(id, presence, revision, feature_status, authority, index)
        exact_keys!(presence, %w[status present_paths absent_paths rationale], "#{id}: canonical presence")
        sources = CANONICAL_SOURCES.fetch(id)
        expected_absent = authority.fetch(:absent_sources).fetch(index)
        actual_absent = sources.select { |relative_path| @git_objects.fetch([revision, relative_path]).nil? }
        raise "#{id}: validator-owned canonical presence authority drift" unless actual_absent == expected_absent

        expected_present = sources - expected_absent
        raise "#{id}: canonical present path mapping drift" unless presence.fetch("present_paths") == expected_present
        raise "#{id}: canonical absent path mapping drift" unless presence.fetch("absent_paths") == expected_absent

        expected_status = if feature_status == "present"
                            raise "#{id}: present feature is missing a canonical blob" unless expected_absent.empty?

                            "complete"
                          elsif expected_present.empty?
                            "absent"
                          else
                            "partial"
                          end
        raise "#{id}: canonical presence status drift" unless presence.fetch("status") == expected_status

        non_empty_string!(presence.fetch("rationale"), "#{id}: canonical presence rationale")
      end

      def verify_history_changes(id, changes, authority)
        record_array!(changes, "#{id}: history changes", key: "boundary")
        expected_boundaries = semantic_boundaries(authority)
        expected_ids = expected_boundaries.map { |entry| entry.fetch(:id) }
        raise "#{id}: history change boundaries must be chronological and canonical" unless
          changes.map { |change| change.fetch("boundary") } == expected_ids
        raise "#{id}: semantic commit authority boundary drift" unless
          SEMANTIC_COMMIT_AUTHORITIES.fetch(id).keys == expected_ids

        changes.zip(expected_boundaries).each do |change, boundary|
          exact_keys!(
            change,
            %w[
              boundary from_revision to_revision classification commit_assessments diff_paths
              rationale unresolved_uncertainty
            ],
            "#{id}: history change"
          )
          verify_semantic_boundary(id, change, boundary, authority)
        end
      end

      def semantic_boundaries(authority)
        introduction = authority.fetch(:revision)
        introduction_parent = self.class.first_parent(@root, introduction)
        raise "introduction parent is outside reviewed history" unless @reviewed_ancestors.include?(introduction_parent)

        first_release = authority.fetch(:first_release)
        boundaries = [{
          id: "introduction..#{first_release}", from: introduction_parent, to: RELEASES.fetch(first_release),
          before_status: "absent", after_status: "present"
        }]
        if first_release == "v0.1.0"
          boundaries << {
            id: "v0.1.0..v0.2.0", from: RELEASES.fetch("v0.1.0"), to: RELEASES.fetch("v0.2.0"),
            before_status: "present", after_status: "present"
          }
        end
        boundaries << {
          id: "v0.2.0..reviewed", from: RELEASES.fetch("v0.2.0"), to: @reviewed_revision,
          before_status: "present", after_status: "present"
        }
        boundaries
      end

      def verify_semantic_boundary(id, change, expected_boundary, authority)
        boundary_id = change.fetch("boundary")
        classification = change.fetch("classification")
        unless %w[introduced semantic_change no_semantic_change].include?(classification)
          raise "#{id}: unsupported semantic history classification"
        end

        raise "#{id}: semantic boundary revision drift" unless
          boundary_id == expected_boundary.fetch(:id) &&
          change.fetch("from_revision") == expected_boundary.fetch(:from) &&
          change.fetch("to_revision") == expected_boundary.fetch(:to)

        paths = ([authority.fetch(:path)] + CANONICAL_SOURCES.fetch(id)).uniq.sort
        assessments = verify_commit_assessments(id, change, expected_boundary, paths)
        semantic = verify_commit_assessment_authority(id, boundary_id, assessments)
        verify_semantic_audit_text(id, change)
        verify_semantic_classification(id, classification, semantic, expected_boundary, authority)
      end

      def verify_commit_assessments(id, change, boundary, paths)
        verify_path_array!(change.fetch("diff_paths"), "#{id}: semantic diff paths")
        raise "#{id}: semantic diff scope drift" unless change.fetch("diff_paths") == paths

        assessments = change.fetch("commit_assessments")
        record_array!(assessments, "#{id}: commit assessments", key: "revision", allow_empty: true)
        assessments.each { |assessment| verify_commit_assessment(id, assessment, paths) }
        expected_reviewed = self.class.path_commits(
          @root, boundary.fetch(:from), boundary.fetch(:to), paths
        )
        reviewed = assessments.map { |assessment| assessment.fetch("revision") }
        raise "#{id}: commit assessment revision set or order drift" unless reviewed == expected_reviewed

        effects = assessments.map { |assessment| assessment.fetch("contract_effect") }
        raise "#{id}: commit-specific contract effects must be unique within a boundary" unless effects.uniq == effects

        assessments
      end

      def verify_commit_assessment(id, assessment, paths)
        exact_keys!(assessment, %w[revision classification summary contract_effect], "#{id}: commit assessment")
        revision = assessment.fetch("revision")
        revision!(revision, "#{id}: commit assessment revision")
        unless @reviewed_ancestors.include?(revision)
          raise "#{id}: commit assessment revision is outside reviewed ancestry"
        end

        classification = assessment.fetch("classification")
        unless COMMIT_ASSESSMENT_CLASSIFICATIONS.include?(classification)
          raise "#{id}: unsupported commit assessment classification"
        end

        subject = self.class.commit_subject(@root, revision)
        raise "#{id}: commit assessment subject drift for #{revision}" unless assessment.fetch("summary") == subject

        changed_paths = self.class.commit_paths(@root, revision)
        relevant_paths = changed_paths & paths
        raise "#{id}: commit assessment is unrelated to its audited paths" if relevant_paths.empty?

        verify_contract_effect(id, assessment, subject, relevant_paths)
      end

      def verify_contract_effect(id, assessment, subject, relevant_paths)
        effect = assessment.fetch("contract_effect")
        non_empty_string!(effect, "#{id}: commit contract effect")
        unless effect.length >= 80 && effect.include?(subject)
          raise "#{id}: contract effect must be a commit-specific rationale containing the exact subject"
        end
        unless relevant_paths.any? { |relative_path| effect.include?(relative_path) }
          raise "#{id}: commit-specific rationale must cite a path changed by that revision"
        end

        pattern, message = CONTRACT_EFFECT_REQUIREMENTS.fetch(assessment.fetch("classification"))
        raise "#{id}: #{message}" unless effect.match?(pattern)
      end

      def verify_commit_assessment_authority(id, boundary_id, assessments)
        semantic = assessments.filter_map do |assessment|
          assessment.fetch("revision") if assessment.fetch("classification") == "semantic_change"
        end
        expected = SEMANTIC_COMMIT_AUTHORITIES.fetch(id).fetch(boundary_id)
        raise "#{id}: semantic commit authority drift" unless semantic == expected

        semantic
      end

      def verify_semantic_audit_text(id, change)
        rationale = change.fetch("rationale")
        non_empty_string!(rationale, "#{id}: semantic audit rationale")
        unless rationale.match?(/public .*?(?:syntax|API|behavior|contract)/i)
          raise "#{id}: semantic rationale must address public syntax, API, behavior, or contract"
        end

        non_empty_string!(change.fetch("unresolved_uncertainty"), "#{id}: semantic audit unresolved uncertainty")
      end

      def verify_semantic_classification(id, classification, semantic, boundary, authority)
        expected = if boundary.fetch(:before_status) == "absent"
                     "introduced"
                   elsif semantic.any?
                     "semantic_change"
                   else
                     "no_semantic_change"
                   end
        raise "#{id}: semantic history classification drift" unless classification == expected

        case expected
        when "introduced" then verify_introduced_boundary(id, semantic, boundary, authority)
        when "semantic_change" then verify_changed_boundary(id, semantic, boundary)
        when "no_semantic_change" then verify_unchanged_boundary(id, semantic, boundary)
        end
      end

      def verify_introduced_boundary(id, semantic, boundary, authority)
        transition = boundary.fetch(:before_status) == "absent" && boundary.fetch(:after_status) == "present"
        raise "#{id}: introduced classification requires an absent-to-present boundary" unless transition
        raise "#{id}: introduction commit must be a reviewed semantic commit" unless
          semantic.include?(authority.fetch(:revision))
      end

      def verify_changed_boundary(id, semantic, boundary)
        present = boundary.fetch(:before_status) == "present" && boundary.fetch(:after_status) == "present"
        raise "#{id}: semantic_change requires a present feature and semantic commits" unless present && semantic.any?
      end

      def verify_unchanged_boundary(id, semantic, boundary)
        present = boundary.fetch(:before_status) == "present" && boundary.fetch(:after_status) == "present"
        raise "#{id}: no_semantic_change requires a present feature and no semantic commits" unless
          present && semantic.empty?
      end

      def historical_source_tree_digest(id, revision)
        payload = +"".b
        CANONICAL_SOURCES.fetch(id).sort.each do |relative_path|
          bytes = @git_objects.fetch([revision, relative_path])
          payload << relative_path.b << "\0".b << (bytes || "<absent>".b) << "\0".b
        end
        Digest::SHA256.hexdigest(payload)
      end

      def verify_feature_issue_audit(id, issue, audits)
        exact_keys!(issue, %w[audit_id status summary], "#{id}: issue_audit")
        audit = audits[issue.fetch("audit_id")]
        raise "#{id}: issue audit id is not registered" unless audit
        raise "#{id}: issue audit status must be none_found or open_found" unless
          %w[none_found open_found].include?(issue.fetch("status"))

        assigned = audit.dig("result", "issues").any? do |record|
          record.dig("disposition", "feature_ids").include?(id)
        end
        expected_status = assigned ? "open_found" : "none_found"
        unless issue.fetch("status") == expected_status
          raise "#{id}: issue status must derive from machine issue dispositions"
        end

        non_empty_string!(issue.fetch("summary"), "#{id}: issue audit summary")
      end

      def verify_documentation(id, documentation)
        exact_keys!(documentation, %w[status evidence gaps], "#{id}: documentation")
        raise "#{id}: invalid documentation status" unless %w[complete_with_gaps
                                                              incomplete].include?(documentation.fetch("status"))

        verify_path_array!(documentation.fetch("evidence"), "#{id}: documentation evidence")
        string_array!(documentation.fetch("gaps"), "#{id}: documentation gaps")
      end

      def verify_dependent_tooling(id, tooling)
        exact_keys!(tooling, %w[status evidence gaps], "#{id}: dependent_tooling")
        raise "#{id}: invalid tooling status" unless %w[present partial].include?(tooling.fetch("status"))

        verify_path_array!(tooling.fetch("evidence"), "#{id}: tooling evidence")
        string_array!(tooling.fetch("gaps"), "#{id}: tooling gaps")
      end

      def verify_limitations(id, limitations)
        exact_keys!(limitations, %w[performance safety], "#{id}: limitations")
        string_array!(limitations.fetch("performance"), "#{id}: performance limitations")
        string_array!(limitations.fetch("safety"), "#{id}: safety limitations")
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one contract.
      def verify_decision(id, decision, external_use, maturity, dependencies, workloads)
        exact_keys!(
          decision,
          %w[
            outcome target_maturity criteria_status user_problem value_classification alternatives reason
            kill_condition redesign_plan evidence
          ],
          "#{id}: decision"
        )
        outcome = decision.fetch("outcome")
        raise "#{id}: invalid maturity decision" unless %w[keep promote redesign remove].include?(outcome)
        raise "#{id}: invalid decision criteria status" unless %w[met unmet
                                                                  planned].include?(decision.fetch("criteria_status"))

        non_empty_string!(decision.fetch("user_problem"), "#{id}: decision user_problem")
        verify_value_classification(id, decision.fetch("value_classification"), external_use, workloads)
        string_array!(decision.fetch("alternatives"), "#{id}: decision alternatives")
        non_empty_string!(decision.fetch("reason"), "#{id}: decision reason")
        reason = decision.fetch("reason")
        if reason.match?(/implementation (?:exists|existence|alone)/i) || reason.match?(/\Atests? pass(?:es|ed)?\.?\z/i)
          raise "#{id}: implementation or passing tests alone cannot justify a maturity decision"
        end

        non_empty_string!(decision.fetch("kill_condition"), "#{id}: decision kill_condition")
        non_empty_string!(decision.fetch("redesign_plan"), "#{id}: decision redesign_plan")
        verify_stable_overlap_decision(id, decision) if STABLE_OVERLAPS.key?(id)

        verify_path_array!(decision.fetch("evidence"), "#{id}: decision evidence")
        case outcome
        when "keep"
          raise "#{id}: keep decision must retain current maturity" unless decision.fetch("target_maturity") == maturity
          unless decision.fetch("criteria_status") == "unmet"
            raise "#{id}: keep decision must record unmet promotion criteria"
          end
          unless decision.fetch("redesign_plan") == "not_applicable"
            raise "#{id}: keep decision cannot hide a redesign plan"
          end
        when "redesign"
          raise "#{id}: redesign retains current maturity until split work ships" unless
            decision.fetch("target_maturity") == maturity && decision.fetch("criteria_status") == "planned"
          raise "#{id}: redesign requires an explicit split plan" if decision.fetch("redesign_plan") == "not_applicable"
        when "promote"
          raise "#{id}: promotion requires met criteria" unless decision.fetch("criteria_status") == "met"

          blocked = dependencies.values.any? { |dependency| dependency.fetch("status") != "complete" }
          raise "#{id}: promotion is forbidden before R001 and exact-revision R002 complete" if blocked
        end
        raise "#{id}: reviewed maturity decision drift" unless outcome == EXPECTED_DECISIONS.fetch(id)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def verify_value_classification(id, classification, external_use, workloads)
        workload_classes = external_use.fetch("workload_ids").map do |workload_id|
          workloads.fetch(workload_id).fetch("classification")
        end.uniq
        expected = if external_use.fetch("status") == "demonstrated"
                     "public_real"
                   elsif workload_classes.include?("repository_synthetic")
                     "repository_synthetic"
                   elsif workload_classes.include?("external_real")
                     "diagnostic_external"
                   else
                     "repository_only"
                   end
        raise "#{id}: decision value classification drifts from workload evidence" unless classification == expected
      end

      def verify_stable_overlap_decision(id, decision)
        raise "#{id}: default-compatible Stable overlap cannot be kept as a breaking Preview surface" unless
          decision.fetch("outcome") == "redesign"

        text = decision.values_at("reason", "kill_condition", "redesign_plan").join(" ")
        if text.match?(/(?:may|can|could) break[^.]*Preview|breaking changes?[^.]*Preview notice/i)
          raise "#{id}: Stable guarantee takes precedence over Preview breaking-change notice"
        end
        return unless id == "middle-actions"

        raise "#{id}: redesign must state that no separable Preview activation exists" unless
          text.match?(/no separable Preview activation/i)
        unless decision.fetch("redesign_plan").match?(
          /split or remove .*redundant Preview classification.*next reviewed release.*distinct opt-in extension/i
        )
          raise "#{id}: redesign plan must split or remove the redundant Preview classification"
        end
      end

      def verify_next_review(id, review)
        exact_keys!(review, %w[triggers required_evidence], "#{id}: next_review")
        string_array!(review.fetch("triggers"), "#{id}: next review triggers")
        string_array!(review.fetch("required_evidence"), "#{id}: next review evidence")
      end

      def verify_release_gate(id, gate, dependencies)
        exact_keys!(gate, %w[status blockers summary], "#{id}: release_gate")
        raise "#{id}: release gate must remain blocked during H001" unless gate.fetch("status") == "blocked"
        raise "#{id}: release blockers must be exactly R001 and R002" unless gate.fetch("blockers") == %w[R001 R002]
        unless gate.fetch("blockers").all? { |blocker| dependencies.fetch(blocker).fetch("status") != "complete" }
          raise "#{id}: release blocker state disagrees with release dependencies"
        end

        non_empty_string!(gate.fetch("summary"), "#{id}: release gate summary")
      end

      def verify_sources(id, sources)
        record_array!(sources, "#{id}: sources", key: "path")
        actual_paths = sources.map { |source| source.fetch("path") }
        raise "#{id}: authoritative canonical source path set drift" unless actual_paths == CANONICAL_SOURCES.fetch(id)

        sources.each do |source|
          exact_keys!(source, %w[path sha256], "#{id}: source")
          file = verify_existing_path!(source.fetch("path"), "#{id}: source")
          digest!(source.fetch("sha256"), "#{id}: source digest")
          actual = Digest::SHA256.file(file).hexdigest
          raise "#{id}: source digest drift for #{source.fetch('path')}" unless actual == source.fetch("sha256")

          verify_reviewed_source!(id, source)
        end
      end

      def verify_reviewed_source!(id, source)
        relative_path = source.fetch("path")
        bytes = @git_objects.fetch([@reviewed_revision, relative_path])
        raise "#{id}: source is absent at reviewed revision #{@reviewed_revision}" unless bytes

        digest = Digest::SHA256.hexdigest(bytes)
        return if digest == source.fetch("sha256")

        raise "#{id}: source digest is not bound to reviewed revision #{@reviewed_revision}"
      end

      def verify_public_summary(features, budgets, dependencies)
        expected = summary_block(features, budgets, dependencies)
        [@narrative, @stability].each do |file|
          source = File.binread(file)
          actual = source[/#{Regexp.escape(SUMMARY_START)}.*?#{Regexp.escape(SUMMARY_END)}/m]
          raise "#{relative(file)} is missing the canonical maturity summary" unless actual
          unless actual == expected
            raise "#{relative(file)} maturity summary drift; regenerate it from docs/maturity.yml"
          end
        end
      end

      def summary_block(features, budgets, dependencies)
        preview = features.count { |feature| feature.fetch("maturity") == "preview" }
        experimental = features.count { |feature| feature.fetch("maturity") == "experimental" }
        preview_active = budgets.fetch("active_new_preview_tracks")
        preview_limit = budgets.fetch("preview_track_limit")
        syntax_active = budgets.fetch("active_grammar_syntax_tracks")
        syntax_limit = budgets.fetch("grammar_syntax_track_limit")
        experiment_active = budgets.fetch("experimental_product_features")
        experiment_limit = budgets.fetch("experimental_product_limit")
        lines = [SUMMARY_START]
        lines << "Inventory: **#{preview} Preview, #{experimental} Experimental**. " \
                 "Active new Preview tracks: **#{preview_active}/#{preview_limit}** " \
                 "(grammar syntax: **#{syntax_active}/#{syntax_limit}**). " \
                 "Experimental product features: **#{experiment_active}/#{experiment_limit}**."
        lines << "Release dependency state: R001 **#{dependencies.dig('R001', 'status')}**; " \
                 "R002 **#{dependencies.dig('R002', 'status')}**; no feature is promoted by this audit."
        lines << ""
        lines << "| Stable ID | Feature | Current maturity | Decision | External use | Release gate |"
        lines << "| --- | --- | --- | --- | --- | --- |"
        features.each do |feature|
          lines << "| `#{feature.fetch('id')}` | #{feature.fetch('name')} | #{title(feature.fetch('maturity'))} | " \
                   "#{title(feature.dig('decision',
                                        'outcome'))} #{title(feature.dig('decision', 'target_maturity'))} | " \
                   "#{feature.dig('external_use', 'status').tr('_', ' ')} | Blocked: R001, R002 |"
        end
        lines << SUMMARY_END
        lines.join("\n")
      end

      def title(value)
        value.split("_").map(&:capitalize).join(" ")
      end

      def verify_path_array!(values, context)
        string_array!(values, context)
        values.each { |entry| verify_existing_path!(entry, context) }
      end

      def verify_existing_path!(value, context)
        raise "#{context} must be a normalized relative path" unless
          value.is_a?(String) && !value.empty? && value == Pathname.new(value).cleanpath.to_s && !value.start_with?(
            "../", "/"
          )

        file = path(value)
        raise "#{context} path is missing: #{value}" unless File.file?(file)

        file
      end

      def exact_keys!(value, expected, context)
        raise "#{context} must be a mapping" unless value.is_a?(Hash)

        actual = value.keys
        return if actual.sort == expected.sort

        raise "#{context} keys must be exactly #{expected.join(', ')}; got #{actual.join(', ')}"
      end

      def record_array!(value, context, key: "id", allow_empty: false)
        valid = value.is_a?(Array)
        valid &&= !value.empty? unless allow_empty
        raise "#{context} must be #{allow_empty ? 'an' : 'a non-empty'} array" unless valid
        raise "#{context} entries must be mappings" unless value.all?(Hash)

        ids = value.map { |entry| entry[key] }
        raise "#{context} must have unique identifiers" unless ids.compact == ids.compact.uniq
      end

      def string_array!(value, context, allow_empty: false)
        valid = value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) && !entry.strip.empty? }
        valid &&= !value.empty? unless allow_empty
        raise "#{context} must be #{allow_empty ? 'an' : 'a non-empty'} array of non-empty strings" unless valid
      end

      def non_empty_string!(value, context)
        raise "#{context} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
      end

      def id!(value, context)
        raise "#{context} must be a canonical kebab-case id" unless value.is_a?(String) && value.match?(ID)
      end

      def revision!(value, context)
        raise "#{context} must be an immutable full SHA-1" unless value.is_a?(String) && value.match?(REVISION)
      end

      def digest!(value, context)
        raise "#{context} must be a SHA-256" unless value.is_a?(String) && value.match?(SHA256)
      end

      def date!(value, context)
        Date.iso8601(value)
      rescue ArgumentError, TypeError
        raise "#{context} must be an ISO-8601 date"
      end

      def path(relative_path)
        File.join(@root, relative_path)
      end

      def relative(file)
        file.delete_prefix("#{@root}/")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
