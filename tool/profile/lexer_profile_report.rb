# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "open3"
require "rbconfig"
require "yaml"
require_relative "lexer_profile_dependencies"
require_relative "lexer_profiler"

module Ibex
  module Profile
    # Canonical digests used to bind the H006 report to its inputs.
    module LexerProfileDigest
      module_function

      def sha256(value)
        Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
      end

      def canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end

      def deterministic_report_input(document)
        copy = Marshal.load(Marshal.dump(document))
        copy.delete("environment")
        copy.delete("provenance")
        copy.fetch("cohorts").fetch(0).fetch("workloads").each do |workload|
          observations = workload.dig("result", "runtime_observations")
          observations&.each_value { |item| item["value"] = 0 }
        end
        copy
      end
    end

    # Host metadata for diagnostic time/allocation observations.
    class LexerProfileEnvironment
      def build
        uname = Etc.uname
        {
          "observation_role" => "host_bound_not_regression_golden",
          "ruby_engine" => RUBY_ENGINE,
          "ruby_version" => RUBY_VERSION,
          "ruby_patchlevel" => RUBY_PATCHLEVEL,
          "ruby_description" => RUBY_DESCRIPTION,
          "ruby_platform" => RUBY_PLATFORM,
          "rubyopt" => ENV.fetch("RUBYOPT", nil),
          "yjit_enabled" => yjit_enabled?,
          "host_os" => RbConfig::CONFIG.fetch("host_os"),
          "host_cpu" => RbConfig::CONFIG.fetch("host_cpu"),
          "kernel_name" => uname.fetch(:sysname),
          "kernel_release" => uname.fetch(:release),
          "kernel_version" => uname.fetch(:version),
          "kernel_machine" => uname.fetch(:machine),
          "logical_processors" => Etc.nprocessors
        }
      end

      private

      def yjit_enabled?
        return false unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?)

        RubyVM::YJIT.enabled?
      end
    end

    # Binds H006 inputs and execution dependencies to one exact clean capture.
    class LexerProfileProvenance
      FIXTURE_PATHS = %w[
        test/fixtures/lexer_profile/alternation.txt
        test/fixtures/lexer_profile/alternation.y
        test/fixtures/lexer_profile/chunk-boundary.txt
        test/fixtures/lexer_profile/chunk-boundary.y
        test/fixtures/lexer_profile/lazy-quantifier.txt
        test/fixtures/lexer_profile/lazy-quantifier.y
        test/fixtures/lexer_profile/long-common-prefix.txt
        test/fixtures/lexer_profile/long-common-prefix.y
        test/fixtures/lexer_profile/nested-quantifier.txt
        test/fixtures/lexer_profile/nested-quantifier.y
        test/fixtures/lexer_profile/parser-feedback.txt
        test/fixtures/lexer_profile/parser-feedback.y
        test/fixtures/lexer_profile/stateful-string.txt
        test/fixtures/lexer_profile/stateful-string.y
        test/fixtures/lexer_profile/unicode-property.txt
        test/fixtures/lexer_profile/unicode-property.y
      ].freeze
      SOURCE_DEPENDENCY_PATHS = LexerProfileDependencies::SOURCE_PATHS
      # Package metadata and release version constants are loaded by the
      # aggregate graph but do not affect lexer construction or observations.
      # Keep them out of the evidence binding so release bumps remain metadata
      # changes rather than profile invalidations.
      RELEASE_METADATA_PATHS = %w[
        ibex.gemspec
        lib/ibex/version.rb
        lib/ibex/runtime/version.rb
      ].freeze
      BOUND_SOURCE_DEPENDENCY_PATHS = (SOURCE_DEPENDENCY_PATHS - RELEASE_METADATA_PATHS).freeze
      BOUND_PATHS = (%w[
        Rakefile
        docs/records/profiles/lexer-construction-profile.md
        docs/registry/workloads.yml
        schema/lexer-profile-v1.schema.json
        test/packaging/schema_files_test.rb
        test/profile/lexer_profile_schema_test.rb
        test/profile/lexer_profiler_test.rb
        test/quality/lexer_profile_test.rb
        test/support/public_json_schemas.rb
        tool/lexer_profile.rb
        tool/profile/lexer_profile_dependencies.rb
        tool/profile/lexer_profile_report.rb
        tool/profile/lexer_profiler.rb
        tool/quality/lexer_profile.rb
        tool/quality/lexer_profile_integrity.rb
      ] + FIXTURE_PATHS + BOUND_SOURCE_DEPENDENCY_PATHS).sort.freeze
      IMPLEMENTATION_PATHS = (BOUND_SOURCE_DEPENDENCY_PATHS + %w[
        schema/lexer-profile-v1.schema.json
        tool/profile/lexer_profile_dependencies.rb
        tool/profile/lexer_profile_report.rb
        tool/profile/lexer_profiler.rb
        tool/quality/lexer_profile.rb
        tool/quality/lexer_profile_integrity.rb
      ]).sort.freeze

      def initialize(root)
        @root = root
      end

      def build(environment, measurement_policy, heuristic_analysis, deterministic_report_input)
        base = capture!("git", "rev-parse", "HEAD").strip
        bindings = BOUND_PATHS.map { |path| binding(base, path) }
        status_lines = capture!("git", "status", "--porcelain=v1", "--untracked-files=normal").lines(chomp: true)
        provenance = {
          "base_revision" => base,
          "base_revision_role" => "Exact clean capture revision and parent of the committed evidence revision",
          "capture_worktree_clean" => status_lines.empty?,
          "capture_worktree_status" => status_lines,
          "capture_worktree_status_sha256" => LexerProfileDigest.sha256(status_lines),
          "bound_paths" => bindings,
          "bound_paths_sha256" => LexerProfileDigest.sha256(bindings),
          "implementation_sha256" => implementation_digest(bindings),
          "deterministic_report_input_sha256" => LexerProfileDigest.sha256(deterministic_report_input),
          "environment_observation_sha256" => LexerProfileDigest.sha256(environment),
          "measurement_policy_sha256" => LexerProfileDigest.sha256(measurement_policy),
          "heuristic_analysis_sha256" => LexerProfileDigest.sha256(heuristic_analysis),
          "evidence_path" => "tool/profile/evidence/lexer-profile-v1.json",
          "evidence_exclusion_reason" => "the evidence file is excluded from its own digest to avoid circularity"
        }
        provenance["capture_identity_sha256"] = self.class.capture_identity(provenance)
        provenance
      end

      def self.capture_identity(provenance)
        LexerProfileDigest.sha256(
          provenance.slice(
            "base_revision", "capture_worktree_clean", "capture_worktree_status_sha256",
            "bound_paths_sha256", "implementation_sha256", "deterministic_report_input_sha256",
            "environment_observation_sha256", "measurement_policy_sha256", "heuristic_analysis_sha256"
          )
        )
      end

      private

      def binding(base, path)
        bytes = File.binread(File.join(@root, path))
        base_bytes = git_object(base, path)
        digest = Digest::SHA256.hexdigest(bytes)
        base_digest = Digest::SHA256.hexdigest(base_bytes) if base_bytes
        state = git_state(base_bytes, digest, base_digest)
        { "path" => path, "sha256" => digest, "git_state" => state, "base_sha256" => base_digest }
      end

      def git_state(base_bytes, current_digest, base_digest)
        return "untracked" if base_bytes.nil?

        current_digest == base_digest ? "base" : "modified"
      end

      def implementation_digest(bindings)
        selected = bindings.select { |item| IMPLEMENTATION_PATHS.include?(item.fetch("path")) }
        LexerProfileDigest.sha256(selected.map { |item| item.slice("path", "sha256") })
      end

      def git_object(revision, path)
        stdout, _stderr, status = Open3.capture3("git", "show", "#{revision}:#{path}", chdir: @root)
        stdout.b if status.success?
      end

      def capture!(*command)
        stdout, stderr, status = Open3.capture3(*command, chdir: @root)
        raise "lexer profile metadata command failed: #{stderr}#{stdout}" unless status.success?

        stdout
      end
    end

    # Applies H006 semantic and workload thresholds without using timing as a gate.
    class LexerProfileDecisions
      def initialize(cohorts)
        @synthetic = cohorts.fetch(0).fetch("workloads")
        @public_real = cohorts.fetch(1).fetch("workloads")
      end

      def build
        [automatic_replacement, separate_profile]
      end

      private

      def automatic_replacement
        arbitrary_actions = @synthetic.sum do |workload|
          workload.dig("result", "structure", "arbitrary_lexer_action_rule_ids")&.length.to_i
        end
        decision(
          "automatic-regexp-replacement", "NO-GO", [
            threshold("regexp-semantic-equivalence", "leftmost-first and maximal-munch agree",
                      "/a|ab/ consumes 1 byte under the current Ruby Regexp rule; maximal-munch would consume 2",
                      false),
            threshold("arbitrary-action-migration", "all actions have a specified declarative translation",
                      "#{arbitrary_actions} trusted Ruby lexer actions observed; no translation is specified", false),
            threshold("parser-feedback-migration", "parser-to-lexer feedback is absent or specified",
                      "parser-feedback fixture changes lexer state before the next lookahead", false)
          ],
          "Automatic replacement is semantically unsafe: inside-rule Ruby Regexp selection, opaque Ruby actions, " \
          "and parser-driven state changes are not an automaton-equivalent contract."
        )
      end

      def separate_profile
        adversarial = @synthetic.count { |workload| workload.fetch("suite") == "adversarial" }
        measured_public = @public_real.count { |workload| workload.dig("availability", "status") == "measured" }
        decision(
          "separate-automaton-profile", "MORE DATA", [
            threshold("adversarial-semantics", "all 8 required fixtures measured", adversarial.to_s,
                      adversarial == 8),
            threshold("public-real-generated-lexer", "at least 2 verified generated-lexer workloads",
                      measured_public.to_s, measured_public >= 2),
            threshold("independent-semantics-contract", "L001 semantics and action boundary implemented",
                      "not implemented; this profile observes only the current Regexp lexer", false),
            threshold("adoption-trigger", "at least 2 verified users blocked by current lexer construction",
                      "0 verified users", false)
          ],
          "A separate automaton profile remains plausible, but the registry has no public-real Ibex generated-lexer " \
          "workload and no verified adoption trigger. Diagnostic elapsed time and allocations do not affect " \
          "this decision."
        )
      end

      def threshold(id, target, observed, satisfied)
        { "id" => id, "target" => target, "observed" => observed, "satisfied" => satisfied }
      end

      def decision(feature, outcome, thresholds, reason)
        {
          "feature" => feature,
          "decision" => outcome,
          "thresholds" => thresholds,
          "reason" => reason,
          "counterevidence_required" => counterevidence(feature)
        }
      end

      def counterevidence(feature)
        if feature == "automatic-regexp-replacement"
          return [
            "a formal compatibility mode preserving Ruby Regexp inside-rule leftmost-first behavior",
            "a reviewed translation or explicit rejection contract for arbitrary lexer actions",
            "a reviewed parser-feedback state transition contract",
            "differential evidence over verified real generated-lexer workloads"
          ]
        end

        [
          "at least two verified public-real Ibex generated-lexer workloads",
          "a standalone automaton semantic contract with declaration-order tie breaking",
          "a bounded action interface that excludes arbitrary parser feedback",
          "verified adoption pressure that structural evidence can address"
        ]
      end
    end

    # Builds exact-revision synthetic and public-real lexer evidence.
    # rubocop:disable Metrics/ClassLength -- exact workload binding and policy stay in one auditable report builder.
    class LexerProfileReport
      FIXTURE_REVISION = "10db74e0b6f33f2ece6899d0b9e153ed92bf1d48"
      GALLERY_INPUTS = {
        "gallery-calc" => "gallery/calc/corpus/basic.txt",
        "gallery-json" => "gallery/json/corpus/nested.json",
        "gallery-sql-lite" => "gallery/sql-lite/corpus/basic.sql"
      }.freeze
      FIXTURES = [
        ["alternation", %w[alternation regexp-leftmost-first]],
        ["lazy-quantifier", %w[lazy-quantifier]],
        ["long-common-prefix", %w[long-common-prefix]],
        ["nested-quantifier", %w[nested-quantifier regexp-warning]],
        ["chunk-boundary", %w[chunk-boundary-inside-token]],
        ["unicode-property", %w[unicode-property]],
        ["stateful-string", %w[stateful-string lexer-state-mutation]],
        ["parser-feedback", %w[parser-action-state-mutation parser-to-lexer-feedback]]
      ].freeze

      def initialize(root:)
        @root = File.expand_path(root)
        @profiler = LexerProfiler.new
        @registry = YAML.safe_load_file(File.join(@root, "docs/registry/workloads.yml"), aliases: false)
      end

      def build
        cohorts = [synthetic_cohort, public_real_cohort]
        environment = LexerProfileEnvironment.new.build
        policy = measurement_policy
        heuristics = heuristic_analysis
        content = report_content(cohorts, environment, policy, heuristics)
        deterministic_input = LexerProfileDigest.deterministic_report_input(content)
        provenance = LexerProfileProvenance.new(@root).build(environment, policy, heuristics, deterministic_input)
        {
          "ibex_report" => content.fetch("ibex_report"),
          "schema_version" => content.fetch("schema_version"),
          "trust" => content.fetch("trust"),
          "environment" => environment,
          "provenance" => provenance,
          "measurement_policy" => policy,
          "heuristic_analysis" => heuristics,
          "semantic_comparison" => content.fetch("semantic_comparison"),
          "cohorts" => cohorts,
          "decisions" => content.fetch("decisions"),
          "limitations" => content.fetch("limitations")
        }
      end

      private

      def report_content(cohorts, environment, policy, heuristics)
        {
          "ibex_report" => "lexer_profile",
          "schema_version" => 1,
          "trust" => "internal_local_observation",
          "environment" => environment,
          "measurement_policy" => policy,
          "heuristic_analysis" => heuristics,
          "semantic_comparison" => semantic_comparison,
          "cohorts" => cohorts,
          "decisions" => LexerProfileDecisions.new(cohorts).build,
          "limitations" => limitations
        }
      end

      def synthetic_cohort
        fixtures = FIXTURES.map { |name, features| fixture_record(name, features) }
        galleries = registered("repository_synthetic").map { |item| gallery_record(item) }
        { "kind" => "synthetic", "workloads" => fixtures + galleries.sort_by { |item| item.fetch("id") } }
      end

      def public_real_cohort
        workloads = registered("public_real").sort_by { |item| item.fetch("id") }.map do |item|
          identity(item).merge(
            "suite" => "registered",
            "adversarial_features" => [],
            "input" => nil,
            "availability" => {
              "status" => "not_run",
              "reason" => "registered source does not use the Ibex generated lexer and no verified port was supplied"
            },
            "result" => nil,
            "notes" => ["No generated-lexer metrics are inferred from an external application lexer."]
          )
        end
        { "kind" => "public_real", "workloads" => workloads }
      end

      def fixture_record(name, features)
        grammar_path = "test/fixtures/lexer_profile/#{name}.y"
        input_path = "test/fixtures/lexer_profile/#{name}.txt"
        grammar_source = git_bytes(FIXTURE_REVISION, grammar_path).force_encoding(Encoding::UTF_8)
        input_seed = git_bytes(FIXTURE_REVISION, input_path).force_encoding(Encoding::UTF_8).delete_suffix("\n")
        repeat = name == "chunk-boundary" ? 129 : 1
        input = input_seed * repeat
        streaming = name != "unicode-property"
        incremental = name != "unicode-property"
        {
          "id" => "adversarial-#{name}",
          "classification" => "repository_synthetic",
          "grammar" => grammar_identity("H006 adversarial #{name}", grammar_path, FIXTURE_REVISION, grammar_source),
          "suite" => "adversarial",
          "adversarial_features" => features,
          "input" => input_identity(input_path, FIXTURE_REVISION, input_seed, input, repeat),
          "availability" => { "status" => "measured", "reason" => nil },
          "result" => profile(grammar_source, grammar_path, input, streaming, incremental),
          "notes" => fixture_notes(name)
        }
      end

      def gallery_record(item)
        grammar_path = item.dig("grammar", "path")
        input_path = GALLERY_INPUTS.fetch(item.fetch("id"))
        revision = item.fetch("revision")
        grammar_source = git_bytes(revision, grammar_path).force_encoding(Encoding::UTF_8)
        verify_digest!(item.fetch("id"), grammar_source, item.dig("grammar", "sha256"))
        input = git_bytes(revision, input_path).force_encoding(Encoding::UTF_8)
        identity(item).merge(
          "suite" => "registered",
          "adversarial_features" => [],
          "input" => input_identity(input_path, revision, input, input, 1),
          "availability" => { "status" => "measured", "reason" => nil },
          "result" => profile(grammar_source, grammar_path, input, true, false),
          "notes" => ["Trusted repository lexer and parser actions execute during this diagnostic profile."]
        )
      end

      def profile(source, path, input, streaming, incremental)
        ast = Frontend::Parser.new(source, file: path, mode: :extended).parse
        grammar = Normalizer.new(ast, mode: :extended).normalize
        @profiler.profile(
          grammar: grammar, input: input, streaming: streaming, incremental: incremental, file: path
        )
      end

      def identity(item)
        grammar = item.fetch("grammar")
        {
          "id" => item.fetch("id"),
          "classification" => item.fetch("classification"),
          "grammar" => {
            "identity" => grammar.fetch("identity"),
            "path" => grammar.fetch("path"),
            "revision" => item.fetch("revision"),
            "sha256" => grammar.fetch("sha256"),
            "storage" => grammar.fetch("storage"),
            "source_url" => grammar.fetch("source_url")
          }
        }
      end

      def grammar_identity(identity, path, revision, source)
        {
          "identity" => identity,
          "path" => path,
          "revision" => revision,
          "sha256" => Digest::SHA256.hexdigest(source),
          "storage" => "repository",
          "source_url" => "repository"
        }
      end

      def input_identity(path, revision, seed, input, repeat)
        {
          "path" => path,
          "revision" => revision,
          "seed_sha256" => Digest::SHA256.hexdigest(seed),
          "sha256" => Digest::SHA256.hexdigest(input),
          "bytes" => input.bytesize,
          "derivation" => repeat == 1 ? "exact file bytes" : "newline-stripped seed repeated #{repeat} times"
        }
      end

      def registered(classification)
        @registry.fetch("workloads").select { |item| item.fetch("classification") == classification }
      end

      def git_bytes(revision, path)
        stdout, stderr, status = Open3.capture3("git", "show", "#{revision}:#{path}", chdir: @root)
        raise "cannot read #{path} at #{revision}: #{stderr}" unless status.success?

        stdout
      end

      def verify_digest!(id, source, expected)
        actual = Digest::SHA256.hexdigest(source)
        raise "#{id}: grammar digest drift (expected #{expected}, got #{actual})" unless actual == expected
      end

      def fixture_notes(name)
        case name
        when "alternation"
          ["Ruby Regexp chooses the first successful alternative inside one rule; this is not maximal munch."]
        when "chunk-boundary"
          ["A 128-byte seed is repeated 129 times; the single token crosses byte offset 16384."]
        when "unicode-property"
          ["Measured with String input; incremental SourceText is binary and is not claimed compatible here."]
        when "parser-feedback"
          [
            "Semantic parsing executes the reduction action before lexing TAIL; " \
            "syntax-only incremental scanning cannot."
          ]
        else
          ["Committed adversarial observation of the current generated Ruby Regexp lexer."]
        end
      end

      def measurement_policy
        {
          "runtime_role" => "diagnostic_observation_only",
          "elapsed_time_release_gate" => false,
          "allocation_count_release_gate" => false,
          "allocation_metric" => "GC.total_allocated_objects delta; not retained bytes or peak memory",
          "streaming_chunk_size_bytes" => Runtime::LexerInput::DEFAULT_CHUNK_SIZE,
          "incremental_metric" => "bytes read by the generated lexer after an identity edit divided by source bytes",
          "action_execution" => "trusted committed repository actions execute; remote source actions are never run",
          "public_workload_rule" => "unported external lexers remain not_run and contribute no inferred metrics"
        }
      end

      def heuristic_analysis
        {
          "method" => "normalized-source-pattern-scan",
          "fields" => %w[
            alternation_rule_ids lazy_rule_ids state_mutation_sources parser_to_lexer_feedback
          ],
          "coverage" => "literal normalized Regexp source and direct `lexer_state =` action text",
          "false_negative_possible" => true,
          "limitations" => [
            "escaped or dynamically constructed Regexp semantics are not a complete Regexp AST analysis",
            "aliases, helper calls, metaprogramming, and indirect state mutation are not detected",
            "a zero count is an observation from this heuristic, not proof that a behavior is absent"
          ]
        }
      end

      def semantic_comparison
        {
          "current_engine" => "Ruby Regexp per declared rule",
          "current_inside_rule_selection" => "Ruby leftmost-first alternative selection",
          "current_across_rule_selection" => "longest matched byte length, then declaration-order tie break",
          "candidate_engine" => "separate automaton profile, not implemented by H006",
          "candidate_selection" => "maximal munch with declaration-order tie break",
          "equivalent" => false,
          "witness" => "/a|ab/ matches `a` in the current rule although maximal munch would match `ab`",
          "migration_risks" => [
            "inside-rule alternation and lazy quantifiers can change token boundaries",
            "arbitrary Ruby lexer actions have no declarative automaton translation",
            "parser reductions can mutate lexer state before the next lookahead"
          ]
        }
      end

      def limitations
        [
          "The profiler observes the current generated lexer and does not implement an automaton lexer.",
          "Synthetic fixtures and galleries are not substitutes for public-real generated-lexer workloads.",
          "Elapsed time and allocation deltas are host-bound diagnostics, not release gates or golden values.",
          "Peak buffer bytes are process-local instrumentation of LexerInput, not whole-process peak memory.",
          "Incremental full-scan share describes the current byte-zero scan path, not incremental parser reuse.",
          "Static source heuristics can miss indirect Regexp and state-mutation behavior."
        ]
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
