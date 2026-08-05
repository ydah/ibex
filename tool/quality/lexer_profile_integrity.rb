# frozen_string_literal: true

require "digest"
require "json"
require "open3"

module Ibex
  module Quality
    # Reconstructs the H006 source snapshot and validates observation provenance.
    class LexerProfileProvenance
      def initialize(root:, document:)
        @root = root
        @document = document
        @provenance = document.fetch("provenance")
      end

      def verify!(committed: true)
        verify_base_revision!
        verify_observation_digests!
        bindings = verify_bound_paths!
        verify_capture_status!(bindings)
        verify_implementation_digest!(bindings)
        verify_deterministic_report_input!
        verify_capture_identity!
        return unless committed

        verify_committed_capture!
        verify_clean_capture!(bindings)
      end

      private

      def verify_base_revision!
        revision = @provenance.fetch("base_revision")
        _output, status = capture("git", "cat-file", "-e", "#{revision}^{commit}")
        raise "lexer profile base revision is unavailable" unless status.success?

        _output, status = capture("git", "merge-base", "--is-ancestor", revision, "HEAD")
        raise "lexer profile base revision is not an ancestor of HEAD" unless status.success?
      end

      def verify_observation_digests!
        verify_digest!("environment observation", @document.fetch("environment"),
                       @provenance.fetch("environment_observation_sha256"))
        verify_digest!("measurement policy", @document.fetch("measurement_policy"),
                       @provenance.fetch("measurement_policy_sha256"))
        verify_digest!("heuristic analysis", @document.fetch("heuristic_analysis"),
                       @provenance.fetch("heuristic_analysis_sha256"))
      end

      def verify_bound_paths!
        bindings = @provenance.fetch("bound_paths")
        expected = Profile::LexerProfileProvenance::BOUND_PATHS
        actual = bindings.map { |item| item.fetch("path") }
        raise "lexer profile bound path inventory drift" unless actual == expected

        bindings.each { |item| verify_binding!(item) }
        verify_digest!("bound paths", bindings, @provenance.fetch("bound_paths_sha256"))
        bindings
      end

      def verify_binding!(item)
        path = item.fetch("path")
        current_digest = Digest::SHA256.file(File.join(@root, path)).hexdigest
        raise "lexer profile bound source drift: #{path}" unless current_digest == item.fetch("sha256")

        base_bytes = git_object(@provenance.fetch("base_revision"), path)
        base_digest = Digest::SHA256.hexdigest(base_bytes) if base_bytes
        raise "lexer profile base source digest drift: #{path}" unless base_digest == item.fetch("base_sha256")

        expected_state = git_state(base_digest, current_digest)
        raise "lexer profile Git state drift: #{path}" unless item.fetch("git_state") == expected_state
      rescue Errno::ENOENT
        raise "lexer profile bound source is missing: #{path}"
      end

      def git_state(base_digest, current_digest)
        return "untracked" if base_digest.nil?

        base_digest == current_digest ? "base" : "modified"
      end

      def verify_capture_status!(bindings)
        lines = @provenance.fetch("capture_worktree_status")
        clean = @provenance.fetch("capture_worktree_clean")
        raise "lexer profile capture clean-state drift" unless clean == lines.empty?

        verify_digest!("capture worktree status", lines, @provenance.fetch("capture_worktree_status_sha256"))
        changed = bindings.reject { |item| item.fetch("git_state") == "base" }
        missing = changed.reject { |item| lines.any? { |line| line.end_with?(item.fetch("path")) } }
        raise "lexer profile capture status omits bound changes" unless missing.empty?
      end

      def verify_implementation_digest!(bindings)
        selected_bindings = bindings.select do |item|
          Profile::LexerProfileProvenance::IMPLEMENTATION_PATHS.include?(item.fetch("path"))
        end
        selected = selected_bindings.map { |item| item.slice("path", "sha256") }
        verify_digest!("implementation", selected, @provenance.fetch("implementation_sha256"))
      end

      def verify_deterministic_report_input!
        input = Profile::LexerProfileDigest.deterministic_report_input(@document)
        verify_digest!(
          "deterministic report input", input, @provenance.fetch("deterministic_report_input_sha256")
        )
      end

      def verify_capture_identity!
        expected = Profile::LexerProfileProvenance.capture_identity(@provenance)
        return if @provenance.fetch("capture_identity_sha256") == expected

        raise "lexer profile capture identity digest drift"
      end

      def verify_committed_capture!
        parent = committed_capture_parent
        return if parent == @provenance.fetch("base_revision")

        raise "lexer profile base revision is not the exact committed capture parent"
      end

      def committed_capture_parent
        path = @provenance.fetch("evidence_path")
        output, status = capture("git", "log", "--format=%H", "--", path)
        raise "lexer profile capture history is unavailable" unless status.success?

        identity = @provenance.fetch("capture_identity_sha256")
        output.lines(chomp: true).each do |revision|
          bytes = git_object(revision, path)
          next unless bytes && capture_identity(bytes) == identity

          parent, parent_status = capture("git", "rev-parse", "#{revision}^1")
          raise "lexer profile capture history is unavailable" unless parent_status.success?

          return parent.strip
        end
        raise "lexer profile capture identity is not bound by committed evidence history"
      end

      def capture_identity(bytes)
        JSON.parse(bytes).dig("provenance", "capture_identity_sha256")
      rescue JSON::ParserError
        nil
      end

      def verify_clean_capture!(bindings)
        clean = @provenance.fetch("capture_worktree_clean")
        lines = @provenance.fetch("capture_worktree_status")
        states = bindings.map { |item| item.fetch("git_state") }.uniq
        return if clean && lines.empty? && states == ["base"]

        raise "lexer profile committed capture must use a clean exact revision"
      end

      def verify_digest!(label, value, expected)
        actual = Profile::LexerProfileDigest.sha256(value)
        raise "lexer profile #{label} digest drift" unless actual == expected
      end

      def git_object(revision, path)
        output, status = capture("git", "show", "#{revision}:#{path}")
        output.b if status.success?
      end

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command, chdir: @root)
        [stdout, status]
      end
    end

    # Cross-record constraints and the required adversarial witness assertions.
    class LexerProfileSemantics
      ADVERSARIAL_IDS = %w[
        adversarial-alternation
        adversarial-lazy-quantifier
        adversarial-long-common-prefix
        adversarial-nested-quantifier
        adversarial-chunk-boundary
        adversarial-unicode-property
        adversarial-stateful-string
        adversarial-parser-feedback
      ].freeze
      PUBLIC_IDS = %w[bcdice-command-parser namae-parser nokogiri-css-parser].freeze

      def initialize(document)
        @document = document
        @synthetic = document.fetch("cohorts").fetch(0).fetch("workloads")
        @public_real = document.fetch("cohorts").fetch(1).fetch("workloads")
      end

      def verify!
        verify_unique_identifiers!
        verify_workloads!
        verify_required_fixtures!
        verify_public_real!
        verify_decisions!
      end

      private

      def verify_unique_identifiers!
        ids = (@synthetic + @public_real).map { |workload| workload.fetch("id") }
        raise "lexer profile workload identifiers are not unique" unless ids.uniq == ids
      end

      def verify_workloads!
        @synthetic.each do |workload|
          result = workload.fetch("result")
          structure = result.fetch("structure")
          states = structure.fetch("states")
          rules = structure.fetch("rules_per_state")
          raise "#{workload.fetch('id')}: state/rule inventory drift" unless rules.keys == states
          raise "#{workload.fetch('id')}: rule count drift" unless rules.values.sum == structure.fetch("rule_count")

          input_bytes = workload.fetch("input").fetch("bytes")
          streaming = result.fetch("streaming")
          unless streaming.fetch("source_bytes_read") == input_bytes
            raise "#{workload.fetch('id')}: source read count drift"
          end

          verify_rule_ids!(workload.fetch("id"), structure)
          verify_token_lengths!(workload.fetch("id"), result.fetch("token_lengths"), input_bytes)
        end
      end

      def verify_rule_ids!(identifier, structure)
        count = structure.fetch("rule_count")
        ids = structure.values_at(
          "alternation_rule_ids", "lazy_rule_ids", "arbitrary_lexer_action_rule_ids"
        ).flatten
        ids.concat(structure.dig("state_mutation_sources", "lexer_rule_ids"))
        raise "#{identifier}: lexer rule identifier out of range" unless ids.all? { |id| id < count }
      end

      def verify_token_lengths!(identifier, lengths, input_bytes)
        sample = lengths.fetch("sample").map { |token| token.fetch("bytes") }
        valid = lengths.fetch("minimum_bytes") <= sample.min &&
                lengths.fetch("maximum_bytes") >= sample.max &&
                lengths.fetch("total_bytes") <= input_bytes &&
                sample.length <= lengths.fetch("count")
        raise "#{identifier}: token length summary is inconsistent" unless valid
      end

      def verify_required_fixtures!
        fixtures = @synthetic.select { |workload| workload.fetch("suite") == "adversarial" }
        by_id = fixtures.to_h { |workload| [workload.fetch("id"), workload] }
        raise "lexer profile adversarial fixture inventory drift" unless by_id.keys == ADVERSARIAL_IDS

        verify_alternation!(by_id.fetch("adversarial-alternation"))
        verify_lazy!(by_id.fetch("adversarial-lazy-quantifier"))
        verify_long_prefix!(by_id.fetch("adversarial-long-common-prefix"))
        verify_nested!(by_id.fetch("adversarial-nested-quantifier"))
        verify_chunk!(by_id.fetch("adversarial-chunk-boundary"))
        verify_unicode!(by_id.fetch("adversarial-unicode-property"))
        verify_stateful!(by_id.fetch("adversarial-stateful-string"))
        verify_feedback!(by_id.fetch("adversarial-parser-feedback"))
      end

      def verify_alternation!(workload)
        result = workload.fetch("result")
        bytes = result.dig("token_lengths", "sample").map { |token| token.fetch("bytes") }
        return if result.dig("structure", "alternation_rule_ids") == [0] && bytes == [1, 1]

        raise "alternation fixture no longer witnesses Ruby leftmost-first behavior"
      end

      def verify_lazy!(workload)
        result = workload.fetch("result")
        bytes = result.dig("token_lengths", "sample").map { |token| token.fetch("bytes") }
        return if result.dig("structure", "lazy_rule_ids") == [0] && bytes == [1, 1, 1]

        raise "lazy fixture no longer witnesses one-byte matches"
      end

      def verify_long_prefix!(workload)
        result = workload.fetch("result")
        token = result.dig("token_lengths", "sample", 0)
        return if token.fetch("token") == "RIGHT" && token.fetch("bytes") == workload.dig("input", "bytes")

        raise "long common-prefix fixture no longer selects its complete rule"
      end

      def verify_nested!(workload)
        warnings = workload.dig("result", "structure", "regexp_warnings")
        return if warnings == [{ "type" => "redos", "rule_id" => 0 }]

        raise "nested quantifier fixture no longer records its Regexp warning"
      end

      def verify_chunk!(workload)
        chunk = workload.dig("result", "streaming", "chunk_size_bytes")
        peak = workload.dig("result", "streaming", "peak_buffer_bytes")
        input = workload.dig("input", "bytes")
        token = workload.dig("result", "token_lengths", "maximum_bytes")
        return if input > chunk && token == input && peak > chunk

        raise "chunk-boundary fixture does not cross a streaming boundary inside one token"
      end

      def verify_unicode!(workload)
        result = workload.fetch("result")
        return if result.dig("streaming", "source_kind") == "string" &&
                  result.dig("token_lengths", "maximum_bytes") == workload.dig("input", "bytes") &&
                  result.dig("incremental_full_scan", "status") == "not_requested"

        raise "Unicode property fixture observation drift"
      end

      def verify_stateful!(workload)
        structure = workload.dig("result", "structure")
        return if structure.fetch("states") == %w[INITIAL STRING] &&
                  structure.dig("state_mutation_sources", "lexer_rule_ids") == [0, 2]

        raise "stateful string fixture no longer records lexer action state mutation"
      end

      def verify_feedback!(workload)
        result = workload.fetch("result")
        productions = result.dig("structure", "state_mutation_sources", "parser_production_ids")
        second_state = result.dig("token_lengths", "sample", 1, "state")
        incremental = result.dig("incremental_full_scan", "status")
        return if result.dig("structure", "parser_to_lexer_feedback") && !productions.empty? &&
                  second_state == "AFTER" && incremental == "not_measured"

        raise "parser-feedback fixture no longer records parser-driven lexer state"
      end

      def verify_public_real!
        ids = @public_real.map { |workload| workload.fetch("id") }
        raise "lexer profile public-real workload inventory drift" unless ids == PUBLIC_IDS
        return if @public_real.all? do |workload|
          workload.dig("availability", "status") == "not_run" && workload.fetch("result").nil?
        end

        raise "lexer profile inferred measurements for an unavailable public-real generated lexer"
      end

      def verify_decisions!
        decisions = @document.fetch("decisions")
        outcomes = decisions.map { |decision| decision.values_at("feature", "decision") }
        expected = [["automatic-regexp-replacement", "NO-GO"], ["separate-automaton-profile", "MORE DATA"]]
        raise "lexer profile decision contract drift" unless outcomes == expected
        raise "lexer profile diagnostic timing became a release gate" unless timing_is_diagnostic?
      end

      def timing_is_diagnostic?
        policy = @document.fetch("measurement_policy")
        return false if policy.fetch("elapsed_time_release_gate") || policy.fetch("allocation_count_release_gate")

        @synthetic.all? do |workload|
          workload.dig("result", "runtime_observations").values.all? { |item| !item.fetch("release_gate") }
        end
      end
    end
  end
end
