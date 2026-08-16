# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

module Ibex
  module Quality
    # rubocop:disable Metrics/ClassLength -- one validator owns the closed registry and all source bindings.
    # Validates the public workload registry and its repository-owned sources.
    class Workloads
      ROOT = File.expand_path("../..", __dir__)
      REVISION = /\A[0-9a-f]{40}\z/
      SHA256 = /\A[0-9a-f]{64}\z/
      ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      CLASSIFICATIONS = %w[external_real public_real repository_real repository_synthetic].freeze
      ELIGIBILITY = %w[diagnostic_only eligible ineligible].freeze
      PAIN_STATES = %w[none_recorded observed unknown].freeze
      WORKAROUND_STATES = %w[documented not_applicable unknown].freeze
      WORKLOAD_KEYS = %w[
        id classification owner project repository_url revision source_binding grammar license
        permission counts used_features known_conflicts current_pain current_workaround benchmark_eligibility
      ].freeze

      def initialize(root: ROOT, registry: nil, documentation: nil, evidence: nil)
        @root = File.expand_path(root)
        @registry = registry || File.join(@root, "docs/registry/workloads.yml")
        @documentation = documentation || File.join(@root, "docs/policy/workloads.md")
        @evidence = evidence || File.join(@root, "tool/quality/workloads/evidence.yml")
      end

      def verify!
        document = load_yaml
        exact_keys!(document, %w[schema_version counting_method problems workloads], "registry")
        raise "workload registry schema_version must be 1" unless document["schema_version"] == 1

        method = verify_counting_method(document.fetch("counting_method"))
        problems = verify_problems(document.fetch("problems"))
        workloads = document.fetch("workloads")
        record_array!(workloads, "workloads")
        workloads.each { |workload| verify_workload(workload, method, problems) }
        verify_source_bindings(workloads)
        verify_fixed_evidence(workloads)
        verify_documentation(workloads, problems)
        true
      rescue KeyError => e
        raise "invalid workload registry: #{e.message}"
      end

      private

      def load_yaml
        value = YAML.safe_load_file(@registry, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise "workload registry root must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "workload registry YAML is invalid: #{e.message}"
      end

      def verify_counting_method(method)
        exact_keys!(method, %w[id algorithm description source_revision], "counting_method")
        raise "counting_method id must be ibex-normalized-lalr-v1" unless
          method.fetch("id") == "ibex-normalized-lalr-v1"
        raise "counting_method algorithm must be lalr" unless method.fetch("algorithm") == "lalr"

        revision!(method.fetch("source_revision"), "counting_method source_revision")
        non_empty_string!(method.fetch("description"), "counting_method description")
        method
      end

      def verify_problems(problems)
        record_array!(problems, "problems")
        problems.each do |problem|
          exact_keys!(problem, %w[id status title evidence], "problem")
          id!(problem.fetch("id"), "problem id")
          raise "#{problem.fetch('id')}: invalid problem status" unless
            %w[observed tracked].include?(problem.fetch("status"))

          non_empty_string!(problem.fetch("title"), "#{problem.fetch('id')}: title")
          string_array!(problem.fetch("evidence"), "#{problem.fetch('id')}: evidence")
          problem.fetch("evidence").each { |entry| verify_locator!(entry, "#{problem.fetch('id')}: evidence") }
        end
        problems.to_h { |problem| [problem.fetch("id"), problem] }
      end

      # rubocop:disable Metrics/AbcSize -- the closed workload record is intentionally checked in one entry point.
      def verify_workload(workload, method, problems)
        exact_keys!(workload, WORKLOAD_KEYS, "workload")
        id = workload.fetch("id")
        id!(id, "workload id")
        raise "#{id}: invalid classification" unless CLASSIFICATIONS.include?(workload.fetch("classification"))

        %w[owner project].each { |key| non_empty_string!(workload.fetch(key), "#{id}: #{key}") }
        repository_url!(workload.fetch("repository_url"), "#{id}: repository_url")
        expected_repository = "https://github.com/#{workload.fetch('owner')}/#{workload.fetch('project')}"
        raise "#{id}: owner/project do not match repository_url" unless
          expected_repository == workload.fetch("repository_url")

        revision!(workload.fetch("revision"), "#{id}: revision")
        verify_source_binding(id, workload.fetch("source_binding"), workload.fetch("classification"))
        verify_grammar(id, workload)
        verify_license(id, workload)
        verify_permission(id, workload)
        verify_classification_evidence(id, workload)
        verify_counts(id, workload.fetch("counts"), method.fetch("id"))
        string_array!(workload.fetch("used_features"), "#{id}: used_features")
        ordered_strings!(workload.fetch("used_features"), "#{id}: used_features")
        verify_conflicts(id, workload.fetch("known_conflicts"))
        verify_pain(id, workload.fetch("current_pain"), problems)
        verify_workaround(id, workload.fetch("current_workaround"))
        verify_eligibility(id, workload)
      end
      # rubocop:enable Metrics/AbcSize

      def verify_classification_evidence(id, workload)
        remote = %w[external_real public_real].include?(workload.fetch("classification"))
        expected_storage = remote ? "remote" : "repository"
        expected_permission = remote ? "public_source" : "repository_owned"
        raise "#{id}: grammar storage conflicts with classification" unless
          workload.dig("grammar", "storage") == expected_storage
        raise "#{id}: permission status conflicts with classification" unless
          workload.dig("permission", "status") == expected_permission

        evidence = workload.dig("license", "evidence") + workload.dig("permission", "evidence")
        raise "#{id}: evidence storage conflicts with classification" unless
          evidence.all? { |entry| entry.fetch("storage") == expected_storage }
      end

      def verify_source_binding(id, binding, classification)
        exact_keys!(binding, %w[kind id], "#{id}: source_binding")
        classifications = {
          "bison_external" => "external_real",
          "gallery" => "repository_synthetic",
          "public_workloads" => "public_real",
          "repository" => "repository_real"
        }
        expected = classifications[binding.fetch("kind")]
        raise "#{id}: invalid source binding kind" unless expected
        raise "#{id}: classification does not match its source binding" unless classification == expected

        return if binding.fetch("id").is_a?(String) && binding.fetch("id").match?(/\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/)

        raise "#{id}: source binding id must be a canonical upstream identifier"
      end

      def verify_grammar(id, workload)
        grammar = workload.fetch("grammar")
        exact_keys!(grammar, %w[identity path sha256 storage source_url], "#{id}: grammar")
        non_empty_string!(grammar.fetch("identity"), "#{id}: grammar identity")
        relative_path!(grammar.fetch("path"), "#{id}: grammar path")
        sha256!(grammar.fetch("sha256"), "#{id}: grammar sha256")
        storage = grammar.fetch("storage")
        raise "#{id}: grammar storage must be remote or repository" unless %w[remote repository].include?(storage)

        if storage == "repository"
          raise "#{id}: repository grammar source_url must be repository" unless
            grammar.fetch("source_url") == "repository"

          verify_repository_digest!(
            grammar.fetch("path"), grammar.fetch("sha256"), "#{id}: grammar", revision: workload.fetch("revision")
          )
        else
          expected = github_blob_url(workload, grammar.fetch("path"))
          unless grammar.fetch("source_url") == expected
            raise "#{id}: grammar source_url is not its canonical primary URL"
          end
        end
      end

      def verify_license(id, workload)
        license = workload.fetch("license")
        exact_keys!(license, %w[expression evidence], "#{id}: license")
        non_empty_string!(license.fetch("expression"), "#{id}: license expression")
        evidence = license.fetch("evidence")
        record_array!(evidence, "#{id}: license evidence", key: "locator")
        evidence.each { |entry| verify_evidence(id, entry, workload, "license") }
      end

      def verify_permission(id, workload)
        permission = workload.fetch("permission")
        exact_keys!(permission, %w[status evidence], "#{id}: permission")
        raise "#{id}: permission status must be public_source or repository_owned" unless
          %w[public_source repository_owned].include?(permission.fetch("status"))

        evidence = permission.fetch("evidence")
        record_array!(evidence, "#{id}: permission evidence", key: "locator")
        evidence.each { |entry| verify_evidence(id, entry, workload, "permission") }
      end

      def verify_evidence(id, evidence, workload, kind)
        exact_keys!(evidence, %w[locator sha256 storage], "#{id}: #{kind} evidence")
        sha256!(evidence.fetch("sha256"), "#{id}: #{kind} evidence sha256")
        case evidence.fetch("storage")
        when "repository"
          relative_path!(evidence.fetch("locator"), "#{id}: #{kind} evidence")
          verify_repository_digest!(
            evidence.fetch("locator"), evidence.fetch("sha256"), "#{id}: #{kind}",
            revision: workload.fetch("revision")
          )
        when "remote"
          canonical_remote_locator!(
            evidence.fetch("locator"), workload.fetch("revision"), id, kind,
            owner: workload.fetch("owner"), project: workload.fetch("project")
          )
        else
          raise "#{id}: #{kind} evidence storage must be remote or repository"
        end
      end

      def verify_counts(id, counts, method)
        exact_keys!(counts, %w[method productions states tokens], "#{id}: counts")
        raise "#{id}: counts use an unsupported method" unless counts.fetch("method") == method

        %w[productions states tokens].each do |name|
          verify_measurement(id, name, counts.fetch(name))
        end
      end

      def verify_conflicts(id, conflicts)
        exact_keys!(conflicts, %w[reduce_reduce shift_reduce], "#{id}: known_conflicts")
        %w[reduce_reduce shift_reduce].each do |name|
          verify_measurement(id, name, conflicts.fetch(name))
        end
      end

      def verify_measurement(id, name, measurement)
        raise "#{id}: #{name} measurement must be a mapping" unless measurement.is_a?(Hash)

        case measurement["status"]
        when "measured"
          exact_keys!(measurement, %w[status value], "#{id}: #{name}")
          value = measurement.fetch("value")
          raise "#{id}: #{name} measured value must be a non-negative integer" unless
            value.is_a?(Integer) && value >= 0
        when "not_measured"
          exact_keys!(measurement, %w[status reason], "#{id}: #{name}")
          non_empty_string!(measurement.fetch("reason"), "#{id}: #{name} reason")
        else
          raise "#{id}: #{name} status must be measured or not_measured"
        end
      end

      def verify_pain(id, pain, problems)
        exact_keys!(pain, %w[status problem_ids summary evidence], "#{id}: current_pain")
        raise "#{id}: invalid current pain status" unless PAIN_STATES.include?(pain.fetch("status"))

        string_array!(pain.fetch("problem_ids"), "#{id}: problem_ids", allow_empty: true)
        ordered_strings!(pain.fetch("problem_ids"), "#{id}: problem_ids")
        missing = pain.fetch("problem_ids").reject { |problem_id| problems.key?(problem_id) }
        raise "#{id}: unknown problem ids #{missing.join(', ')}" unless missing.empty?

        non_empty_string!(pain.fetch("summary"), "#{id}: current pain summary")
        string_array!(pain.fetch("evidence"), "#{id}: current pain evidence", allow_empty: true)
        pain.fetch("evidence").each { |entry| verify_locator!(entry, "#{id}: current pain evidence") }
        if pain.fetch("status") == "observed" && (pain.fetch("problem_ids").empty? || pain.fetch("evidence").empty?)
          raise "#{id}: observed pain requires a problem id and evidence"
        end
        return unless pain.fetch("status") != "observed" && !pain.fetch("problem_ids").empty?

        raise "#{id}: unobserved pain cannot claim problem ids"
      end

      def verify_workaround(id, workaround)
        exact_keys!(workaround, %w[status summary evidence], "#{id}: current_workaround")
        raise "#{id}: invalid workaround status" unless WORKAROUND_STATES.include?(workaround.fetch("status"))

        non_empty_string!(workaround.fetch("summary"), "#{id}: workaround summary")
        string_array!(workaround.fetch("evidence"), "#{id}: workaround evidence", allow_empty: true)
        workaround.fetch("evidence").each { |entry| verify_locator!(entry, "#{id}: workaround evidence") }
        return unless workaround.fetch("status") == "documented" && workaround.fetch("evidence").empty?

        raise "#{id}: documented workaround requires evidence"
      end

      def verify_eligibility(id, workload)
        eligibility = workload.fetch("benchmark_eligibility")
        exact_keys!(eligibility, %w[status scopes reasons], "#{id}: benchmark_eligibility")
        raise "#{id}: invalid benchmark eligibility" unless ELIGIBILITY.include?(eligibility.fetch("status"))

        string_array!(eligibility.fetch("scopes"), "#{id}: benchmark scopes", allow_empty: true)
        ordered_strings!(eligibility.fetch("scopes"), "#{id}: benchmark scopes")
        string_array!(eligibility.fetch("reasons"), "#{id}: benchmark reasons")
        return if eligibility.fetch("status") == "ineligible"

        measurements = workload.fetch("counts").values_at("productions", "states", "tokens")
        unless measurements.all? { |measurement| measurement.fetch("status") == "measured" }
          raise "#{id}: benchmark eligibility requires measured production, state, and token counts"
        end
        raise "#{id}: benchmark eligibility requires explicit scopes" if eligibility.fetch("scopes").empty?
        raise "#{id}: benchmark eligibility lacks permission evidence" if
          workload.dig("permission", "evidence").empty?
        raise "#{id}: benchmark eligibility lacks license evidence" if workload.dig("license", "evidence").empty?
      end

      def verify_source_bindings(workloads)
        groups = workloads.group_by { |workload| workload.dig("source_binding", "kind") }
        verify_public_workloads(groups.fetch("public_workloads", []))
        verify_gallery(groups.fetch("gallery", []))
        verify_bison_external(groups.fetch("bison_external", []))
        verify_repository_sources(groups.fetch("repository", []))
      end

      def verify_public_workloads(workloads)
        path = File.join(@root, "benchmark/public_workloads.json")
        manifest = JSON.parse(File.binread(path)).fetch("workloads")
        registry = workloads.to_h { |workload| [workload.dig("source_binding", "id"), workload] }
        raise "public workload bindings differ from benchmark/public_workloads.json" unless
          registry.keys.sort == manifest.map { |entry| entry.fetch("id") }.sort

        manifest.each do |entry|
          workload = registry.fetch(entry.fetch("id"))
          expected = [entry.fetch("revision"), entry.fetch("grammar_path"), entry.fetch("grammar_sha256")]
          actual = [workload.fetch("revision"), workload.dig("grammar", "path"), workload.dig("grammar", "sha256")]
          raise "#{workload.fetch('id')}: public workload manifest drift" unless actual == expected

          registered_metrics = {
            "method" => workload.dig("counts", "method"),
            "productions" => workload.dig("counts", "productions", "value"),
            "states" => workload.dig("counts", "states", "value"),
            "tokens" => workload.dig("counts", "tokens", "value"),
            "shift_reduce" => workload.dig("known_conflicts", "shift_reduce", "value"),
            "reduce_reduce" => workload.dig("known_conflicts", "reduce_reduce", "value")
          }
          raise "#{workload.fetch('id')}: public workload metrics drift" unless
            registered_metrics == entry.fetch("grammar_metrics")
        end
      end

      def verify_gallery(workloads)
        directories = Dir.glob(File.join(@root, "gallery/*")).select do |path|
          File.directory?(path) && File.file?(File.join(path, "grammar.y"))
        end
        registry = workloads.to_h { |workload| [workload.dig("source_binding", "id"), workload] }
        raise "gallery bindings differ from committed gallery grammars" unless
          registry.keys.sort == directories.map { |path| File.basename(path) }.sort

        workloads.each { |workload| verify_local_automaton(workload) }
      end

      def verify_bison_external(workloads)
        require_relative "bison_external"
        entries = BisonExternal::BISON_CORPUS + [BisonExternal::CURRENT_RUBY]
        registry = workloads.to_h { |workload| [workload.dig("source_binding", "id"), workload] }
        raise "Bison external bindings differ from tool/quality/bison_external.rb" unless
          registry.keys.sort == entries.map { |entry| entry.fetch(:name) }.sort

        entries.each do |entry|
          workload = registry.fetch(entry.fetch(:name))
          url = entry.fetch(:url)
          revision = url[%r{/([0-9a-f]{40})/}, 1]
          source_url = url.sub("raw.githubusercontent.com", "github.com")
                          .sub(%r{/([0-9a-f]{40})/}, "/blob/\\1/")
          identity = [revision, source_url, entry.fetch(:sha256)]
          registered = [workload.fetch("revision"), workload.dig("grammar", "source_url"),
                        workload.dig("grammar", "sha256")]
          raise "#{workload.fetch('id')}: Bison external identity drift" unless registered == identity

          verify_bison_counts(workload, entry.fetch(:expected))
        end
      end

      def verify_bison_counts(workload, expected)
        id = workload.fetch("id")
        if expected.fetch(:structural_unsupported, 0).positive?
          measured = workload.fetch("counts").values_at("productions", "states", "tokens") +
                     workload.fetch("known_conflicts").values
          raise "#{id}: structurally incomplete imports cannot publish complete counts" unless
            measured.all? { |entry| entry.fetch("status") == "not_measured" }
          raise "#{id}: structurally incomplete import must be benchmark-ineligible" unless
            workload.dig("benchmark_eligibility", "status") == "ineligible"

          return
        end

        actual = {
          productions: workload.dig("counts", "productions", "value"),
          states: workload.dig("counts", "states", "value"),
          tokens: workload.dig("counts", "tokens", "value"),
          sr: workload.dig("known_conflicts", "shift_reduce", "value"),
          rr: workload.dig("known_conflicts", "reduce_reduce", "value")
        }
        expected_values = expected.slice(:productions, :states, :tokens, :sr, :rr)
        raise "#{id}: Bison external counts drift" unless actual == expected_values
      end

      def verify_fixed_evidence(workloads)
        document = YAML.safe_load_file(@evidence, permitted_classes: [], permitted_symbols: [], aliases: false)
        exact_keys!(document, %w[schema_version records], "fixed evidence")
        raise "fixed evidence schema_version must be 1" unless document.fetch("schema_version") == 1

        records = document.fetch("records")
        record_array!(records, "fixed evidence records")
        records.each { |record| verify_fixed_evidence_record(record) }
        remote = workloads.select do |workload|
          %w[external_real public_real].include?(workload.fetch("classification"))
        end
        projected = remote.map { |workload| fixed_evidence_projection(workload) }
        unless projected == records
          raise "remote source, license, or permission evidence differs from the reviewed fixture"
        end
      rescue Psych::Exception => e
        raise "fixed workload evidence YAML is invalid: #{e.message}"
      end

      def verify_fixed_evidence_record(record)
        keys = %w[id classification owner project repository_url revision grammar license permission]
        exact_keys!(record, keys, "fixed evidence record")
        id = record.fetch("id")
        id!(id, "fixed evidence id")
        raise "#{id}: fixed evidence classification must be remote" unless
          %w[external_real public_real].include?(record.fetch("classification"))

        %w[owner project].each { |key| non_empty_string!(record.fetch(key), "#{id}: fixed evidence #{key}") }
        revision!(record.fetch("revision"), "#{id}: fixed evidence revision")
        expected_repository = "https://github.com/#{record.fetch('owner')}/#{record.fetch('project')}"
        raise "#{id}: fixed evidence repository identity mismatch" unless
          record.fetch("repository_url") == expected_repository

        exact_keys!(record.fetch("grammar"), %w[path source_url sha256], "#{id}: fixed grammar")
        relative_path!(record.dig("grammar", "path"), "#{id}: fixed grammar path")
        sha256!(record.dig("grammar", "sha256"), "#{id}: fixed grammar sha256")
        raise "#{id}: fixed grammar source URL mismatch" unless
          record.dig("grammar", "source_url") == github_blob_url(record, record.dig("grammar", "path"))

        verify_fixed_evidence_group(id, record, "license")
        verify_fixed_evidence_group(id, record, "permission")
        permission = record.fetch("permission")
        raise "#{id}: fixed permission must be public_source" unless permission.fetch("status") == "public_source"

        expected_permission = [{
          "locator" => record.dig("grammar", "source_url"),
          "sha256" => record.dig("grammar", "sha256"),
          "storage" => "remote"
        }]
        raise "#{id}: fixed permission must bind the exact grammar bytes" unless
          permission.fetch("evidence") == expected_permission
      end

      def verify_fixed_evidence_group(id, record, kind)
        expected = kind == "license" ? %w[expression evidence] : %w[status evidence]
        group = record.fetch(kind)
        exact_keys!(group, expected, "#{id}: fixed #{kind}")
        non_empty_string!(group.fetch(kind == "license" ? "expression" : "status"), "#{id}: fixed #{kind}")
        evidence = group.fetch("evidence")
        record_array!(evidence, "#{id}: fixed #{kind} evidence", key: "locator")
        evidence.each do |entry|
          exact_keys!(entry, %w[locator sha256 storage], "#{id}: fixed #{kind} evidence")
          raise "#{id}: fixed #{kind} evidence must be remote" unless entry.fetch("storage") == "remote"

          sha256!(entry.fetch("sha256"), "#{id}: fixed #{kind} evidence sha256")
          canonical_remote_locator!(
            entry.fetch("locator"), record.fetch("revision"), id, kind,
            owner: record.fetch("owner"), project: record.fetch("project")
          )
        end
      end

      def fixed_evidence_projection(workload)
        {
          "id" => workload.fetch("id"),
          "classification" => workload.fetch("classification"),
          "owner" => workload.fetch("owner"),
          "project" => workload.fetch("project"),
          "repository_url" => workload.fetch("repository_url"),
          "revision" => workload.fetch("revision"),
          "grammar" => workload.fetch("grammar").slice("path", "source_url", "sha256"),
          "license" => workload.fetch("license"),
          "permission" => workload.fetch("permission")
        }
      end

      def verify_repository_sources(workloads)
        raise "repository binding must contain only the self-hosted grammar" unless
          workloads.map { |entry| entry.dig("source_binding", "id") } == ["ibex-frontend"]

        workloads.each { |workload| verify_local_automaton(workload) }
      end

      def verify_local_automaton(workload)
        source = File.binread(repository_path(workload.dig("grammar", "path"), "local grammar"))
        mode = source.include?("pragma extended") ? :extended : :default
        ast = Frontend::Parser.new(source, file: workload.dig("grammar", "path"), mode: mode).parse
        grammar = Normalizer.new(ast, mode: mode).normalize
        automaton = LALR::Builder.new(grammar).build
        actual = {
          "productions" => grammar.productions.length,
          "states" => automaton.states.length,
          "tokens" => grammar.terminals.length,
          "shift_reduce" => automaton.conflict_summary.fetch(:sr),
          "reduce_reduce" => automaton.conflict_summary.fetch(:rr)
        }
        registered = workload.fetch("counts").slice("productions", "states", "tokens")
                             .transform_values { |entry| entry["value"] }
                             .merge(workload.fetch("known_conflicts").transform_values { |entry| entry["value"] })
        raise "#{workload.fetch('id')}: repository grammar counts drift" unless actual == registered
      end

      def verify_documentation(workloads, problems)
        source = File.read(@documentation, encoding: Encoding::UTF_8)
        raise "workload documentation must distinguish synthetic and real sources" unless
          source.include?("repository_synthetic") && source.include?("public_real") &&
          source.include?("external_real") && source.include?("repository_real")

        (workloads.map { |entry| entry.fetch("id") } + problems.keys).each do |id|
          raise "workload documentation is missing stable id #{id}" unless source.include?("`#{id}`")
        end
      end

      def record_array!(records, label, key: "id")
        raise "#{label} must be a non-empty array" unless records.is_a?(Array) && !records.empty?

        values = records.map { |record| record.is_a?(Hash) ? record[key] : nil }
        raise "#{label} must use unique canonical order" unless values == values.compact.sort && values.uniq == values
      end

      def string_array!(values, label, allow_empty: false)
        valid = values.is_a?(Array) && (allow_empty || !values.empty?) &&
                values.all? { |value| value.is_a?(String) && !value.strip.empty? }
        raise "#{label} must be #{allow_empty ? 'an' : 'a non-empty'} array of strings" unless valid
      end

      def ordered_strings!(values, label)
        raise "#{label} must use unique canonical order" unless values == values.sort && values.uniq == values
      end

      def exact_keys!(record, expected, label)
        raise "#{label} must be a mapping" unless record.is_a?(Hash)
        raise "#{label} keys must be #{expected.sort.join(', ')}" unless record.keys.sort == expected.sort
      end

      def id!(value, label)
        raise "#{label} must be a canonical kebab-case id" unless value.is_a?(String) && value.match?(ID)
      end

      def revision!(value, label)
        raise "#{label} must be an immutable full SHA-1" unless value.is_a?(String) && value.match?(REVISION)
      end

      def sha256!(value, label)
        raise "#{label} must be 64 lowercase hex" unless value.is_a?(String) && value.match?(SHA256)
      end

      def non_empty_string!(value, label)
        raise "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
      end

      def repository_url!(value, label)
        non_empty_string!(value, label)
        raise "#{label} must be a canonical HTTPS GitHub repository URL" unless
          value.match?(%r{\Ahttps://github\.com/[^/]+/[^/]+\z})
      end

      def github_blob_url(record, path)
        "https://github.com/#{record.fetch('owner')}/#{record.fetch('project')}/blob/" \
          "#{record.fetch('revision')}/#{path}"
      end

      def canonical_remote_locator!(value, revision, id, kind, owner:, project:)
        non_empty_string!(value, "#{id}: #{kind} evidence locator")
        prefixes = [
          "https://github.com/#{owner}/#{project}/blob/#{revision}/",
          "https://raw.githubusercontent.com/#{owner}/#{project}/#{revision}/"
        ]
        prefix = prefixes.find { |candidate| value.start_with?(candidate) }
        raise "#{id}: #{kind} evidence is not a canonical primary GitHub URL" unless prefix

        relative_path!(value.delete_prefix(prefix), "#{id}: #{kind} evidence path")
      end

      def relative_path!(value, label)
        non_empty_string!(value, label)
        path = Pathname.new(value)
        clean = path.cleanpath.to_s
        return unless path.absolute? || clean != value || clean.start_with?("../")

        raise "#{label} must be a normalized relative path"
      end

      def verify_repository_digest!(relative, digest, label, revision: nil)
        path = repository_path(relative, label)
        raise "#{label} path is missing" unless File.file?(path)
        raise "#{label} digest drift" unless Digest::SHA256.file(path).hexdigest == digest

        return unless revision

        source, error, status = Open3.capture3("git", "show", "#{revision}:#{relative}", chdir: @root)
        raise "#{label} is absent at pinned revision: #{error.strip}" unless status.success?
        raise "#{label} digest does not match its pinned revision" unless Digest::SHA256.hexdigest(source) == digest
      end

      def repository_path(relative, label)
        relative_path!(relative, label)
        path = File.expand_path(relative, @root)
        raise "#{label} escapes the repository" unless path.start_with?("#{@root}/")

        path
      end

      def verify_locator!(value, label)
        non_empty_string!(value, label)
        return if value.start_with?("https://")

        path = repository_path(value, label)
        raise "#{label} path is missing" unless File.file?(path)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
