# frozen_string_literal: true

require "date"
require "digest"
require "open3"
require "pathname"
require "yaml"

module Ibex
  module Quality
    # rubocop:disable Metrics/ClassLength -- one validator owns the closed maturity audit and its public projections.
    # Validates the Preview/Experimental inventory, evidence, and generated public summary.
    class Maturity
      ROOT = File.expand_path("../..", __dir__)
      REVISION = /\A[0-9a-f]{40}\z/
      SHA256 = /\A[0-9a-f]{64}\z/
      ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
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
      SUMMARY_START = "<!-- maturity-summary:start -->"
      SUMMARY_END = "<!-- maturity-summary:end -->"

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
        issue_audits = audit.fetch("issue_audits")
        record_array!(issue_audits, "issue audits")
        issue_audits.each { |entry| verify_issue_audit(entry, audit.fetch("reviewed_at")) }
        issue_audits.to_h { |entry| [entry.fetch("id"), entry] }
      end

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
        raise "issue audit freshness window must be 30 days or less" if (fresh_until - checked).to_i > 30
        raise "issue audit is stale; rerun the exact query and review every result" if fresh_until < @today

        verify_issue_result(entry.fetch("result"))
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- closed result validation.
      def verify_issue_result(result)
        exact_keys!(result, %w[status total_count incomplete_results issue_numbers limitation], "issue audit result")
        raise "issue audit result status must be complete" unless result.fetch("status") == "complete"

        count = result.fetch("total_count")
        raise "issue audit total_count must be a non-negative integer" unless count.is_a?(Integer) && count >= 0
        unless result.fetch("incomplete_results") == false
          raise "incomplete GitHub issue results cannot support a maturity decision"
        end

        numbers = result.fetch("issue_numbers")
        raise "issue audit issue_numbers must be ordered unique positive integers" unless
          numbers.is_a?(Array) && numbers == numbers.uniq.sort && numbers.all? do |number|
            number.is_a?(Integer) && number.positive?
          end
        raise "issue audit count does not match issue_numbers" unless numbers.length == count

        non_empty_string!(result.fetch("limitation"), "issue audit limitation")
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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

        prepare_reviewed_sources(features)
        features.each { |feature| verify_feature(feature, audit, dependencies, workloads) }
        features
      end

      def prepare_reviewed_sources(features)
        sources = features.flat_map { |feature| feature.fetch("sources") }
        relative_paths = sources.map { |source| source.fetch("path") }.uniq
        @reviewed_digests = {}
        Open3.popen3("git", "-C", @root, "cat-file", "--batch") do |input, output, error, thread|
          relative_paths.each { |relative_path| input.puts("#{@reviewed_revision}:#{relative_path}") }
          input.close
          relative_paths.each { |relative_path| read_reviewed_source(output, relative_path) }
          message = error.read.strip
          raise "cannot read maturity sources at reviewed revision: #{message}" unless thread.value.success?
        end
      end

      def read_reviewed_source(output, relative_path)
        header = output.gets&.strip
        fields = header&.split
        unless fields&.length == 3 && fields.fetch(1) == "blob"
          raise "source is absent at reviewed revision #{@reviewed_revision}: #{relative_path}"
        end

        size = Integer(fields.fetch(2), 10)
        bytes = output.read(size)
        separator = output.read(1)
        raise "invalid Git object stream for #{relative_path}" unless bytes&.bytesize == size && separator == "\n"

        @reviewed_digests[relative_path] = Digest::SHA256.hexdigest(bytes)
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
        verify_decision(id, feature.fetch("decision"), expected_maturity, dependencies)
        verify_next_review(id, feature.fetch("next_review"))
        verify_release_gate(id, feature.fetch("release_gate"), dependencies)
        verify_sources(id, feature.fetch("sources"))
      end

      def verify_activation(id, activation, maturity)
        exact_keys!(activation, %w[kind mechanism default_enabled], "#{id}: activation")
        raise "#{id}: activation kind must be explicit" unless activation.fetch("kind") == "explicit"

        non_empty_string!(activation.fetch("mechanism"), "#{id}: activation mechanism")
        raise "#{id}: #{maturity} feature cannot be default-enabled" unless activation.fetch("default_enabled") == false
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
        exact_keys!(history, %w[status changes unknowns evidence], "#{id}: specification_history")
        raise "#{id}: unsupported specification history status" unless
          %w[complete partial not_reconstructed].include?(history.fetch("status"))

        string_array!(history.fetch("changes"), "#{id}: specification changes", allow_empty: true)
        string_array!(history.fetch("unknowns"), "#{id}: specification history unknowns", allow_empty: true)
        string_array!(history.fetch("evidence"), "#{id}: specification history evidence")
        history.fetch("evidence").each { |entry| verify_existing_path!(entry, "#{id}: history evidence") }
        return unless history.fetch("status") == "not_reconstructed" && history.fetch("unknowns").empty?

        raise "#{id}: unreconstructed history requires an explicit unknown"
      end

      def verify_feature_issue_audit(id, issue, audits)
        exact_keys!(issue, %w[audit_id status summary], "#{id}: issue_audit")
        audit = audits[issue.fetch("audit_id")]
        raise "#{id}: issue audit id is not registered" unless audit
        raise "#{id}: issue audit status must be none_found or open_found" unless
          %w[none_found open_found].include?(issue.fetch("status"))

        if audit.dig("result", "total_count").zero? && issue.fetch("status") != "none_found"
          raise "#{id}: issue audit cannot claim an open issue"
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

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- one compatibility contract.
      def verify_decision(id, decision, maturity, dependencies)
        exact_keys!(decision, %w[outcome target_maturity criteria_status reason evidence], "#{id}: decision")
        outcome = decision.fetch("outcome")
        raise "#{id}: invalid maturity decision" unless %w[keep promote redesign remove].include?(outcome)
        raise "#{id}: invalid decision criteria status" unless %w[met unmet
                                                                  planned].include?(decision.fetch("criteria_status"))

        non_empty_string!(decision.fetch("reason"), "#{id}: decision reason")
        if decision.fetch("reason").match?(/implementation (?:exists|existence|alone)/i)
          raise "#{id}: implementation existence cannot be the reason for a maturity decision"
        end

        verify_path_array!(decision.fetch("evidence"), "#{id}: decision evidence")
        if outcome == "keep"
          raise "#{id}: keep decision must retain current maturity" unless decision.fetch("target_maturity") == maturity
          unless decision.fetch("criteria_status") == "unmet"
            raise "#{id}: keep decision must record unmet promotion criteria"
          end
        elsif outcome == "promote"
          raise "#{id}: promotion requires met criteria" unless decision.fetch("criteria_status") == "met"

          blocked = dependencies.values.any? { |dependency| dependency.fetch("status") != "complete" }
          raise "#{id}: promotion is forbidden before R001 and exact-revision R002 complete" if blocked
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
        digest = @reviewed_digests.fetch(relative_path)
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

      def record_array!(value, context, key: "id")
        raise "#{context} must be a non-empty array" unless value.is_a?(Array) && !value.empty?
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
