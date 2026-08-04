# frozen_string_literal: true

require "shellwords"
require_relative "assessment_choice"

module Ibex
  module Quality
    # Validates assessment meaning, owned evidence, and deterministic commands.
    class RuntimeABIAssessmentFields
      RAKE_TASKS = %w[
        quality:runtime_abi test test:matrix test:matrix:full test:zero_cost test:ir_schema
        test:docs_coverage test:adversarial frontend:check release:reproducible lint
      ].freeze
      AUXILIARY_COMMANDS = [
        %w[bundle exec rubocop], %w[actionlint -color], %w[zizmor .], %w[npm run test:site]
      ].freeze

      def initialize(root:, contract:, test_contract:, changed_paths:, runtime_paths:)
        @root = root
        @contract = contract
        @changed_paths = changed_paths
        @runtime_paths = runtime_paths
        @interactions = test_contract.fetch("interactions").to_h { |entry| [entry.fetch("id"), entry.fetch("tests")] }
      end

      def verify!(value)
        policy = @contract.fetch("assessment")
        verify_fields(value, policy.fetch("required_fields"))
        state = vocabulary!(value, "state", policy.fetch("states"))
        choice = vocabulary!(value, "abi_choice", policy.fetch("abi_choices"))
        regeneration = vocabulary!(value, "regeneration", policy.fetch("regeneration"))
        surfaces = array_vocabulary!(value, "surfaces", policy.fetch("surfaces"))

        verify_rationale(value.fetch("rationale"))
        interactions = affected_interactions(value.fetch("affected_interactions"))
        evidence = evidence_paths(value.fetch("evidence"))
        tests = owned_tests(value.fetch("tests"), interactions)
        verify_commands(value.fetch("verification"), tests)
        verify_runtime_evidence(evidence)
        RuntimeABIAssessmentChoice.verify!(
          state: state, choice: choice, regeneration: regeneration, surfaces: surfaces
        )
      end

      private

      def verify_fields(value, required)
        raise "runtime ABI assessment must be a mapping" unless value.is_a?(Hash)
        return if value.keys.sort == required.sort

        raise "runtime ABI assessment fields must be #{required.sort.join(', ')}"
      end

      def vocabulary!(value, field, allowed)
        actual = value.fetch(field)
        raise "runtime ABI assessment #{field} must be one of #{allowed.join(', ')}" unless allowed.include?(actual)

        actual
      end

      def array_vocabulary!(value, field, allowed)
        actual = value.fetch(field)
        unless unique_nonempty_strings?(actual) && (actual - allowed).empty?
          raise "runtime ABI assessment #{field} must be a non-empty unique subset of #{allowed.join(', ')}"
        end

        actual
      end

      def verify_rationale(value)
        unless value.is_a?(String)
          raise "runtime ABI assessment rationale must be substantive and must replace the placeholder"
        end

        text = value.strip
        placeholder = /\b(?:todo|tbd|fixme|template|placeholder)\b/i
        tokens = text.downcase.scan(/[\p{L}\p{N}]+/u)
        characters = tokens.join.each_char.to_a
        repeated = tokens.tally.values.max.to_i * 2 > tokens.length
        valid = text.length >= 20 && !text.match?(placeholder) && !text.match?(/\p{Cf}/u) &&
                tokens.length >= 6 && tokens.uniq.length >= 5 && characters.uniq.length >= 10 && !repeated
        return if valid

        raise "runtime ABI assessment rationale must be substantive and must replace the placeholder"
      end

      def affected_interactions(values)
        unless unique_nonempty_strings?(values) && (values - @interactions.keys).empty?
          raise "affected_interactions must be documented interaction ids"
        end

        values
      end

      def evidence_paths(values)
        unless unique_nonempty_strings?(values)
          raise "runtime ABI assessment evidence must be a non-empty unique path list"
        end

        invalid = values.reject { |path| @changed_paths.include?(path) || regression_test?(path) }
        raise "evidence must be a changed path or owned regression test: #{invalid.join(', ')}" unless invalid.empty?

        values
      end

      def owned_tests(values, interactions)
        unless unique_nonempty_strings?(values)
          raise "runtime ABI assessment tests must be a non-empty unique path list"
        end

        owners = interactions.to_h { |id| [id, @interactions.fetch(id)] }
        verify_owned_test_paths(values, owners)
        values
      end

      def verify_owned_test_paths(values, owners)
        allowed = owners.values.flatten.uniq
        invalid = values - allowed
        raise "tests are not owned by affected_interactions: #{invalid.join(', ')}" unless invalid.empty?

        non_regressions = values.reject { |path| regression_test?(path) }
        unless non_regressions.empty?
          raise "selected tests must be executable regression tests: #{non_regressions.join(', ')}"
        end

        missing = owners.filter_map { |id, paths| id if (values & paths).empty? }
        raise "affected interactions lack selected tests: #{missing.join(', ')}" unless missing.empty?

        absent = values.reject { |path| File.file?(File.join(@root, path)) }
        raise "selected tests are missing: #{absent.join(', ')}" unless absent.empty?
      end

      def verify_commands(values, tests)
        raise "verification must be a non-empty unique command list" unless unique_nonempty_strings?(values)

        tokens = values.to_h { |command| [command, parse_allowed_command(command, tests)] }
        invalid = tokens.filter_map { |command, allowed| command unless allowed }
        raise "verification contains a non-allowlisted command: #{invalid.join(', ')}" unless invalid.empty?

        abi_gate = "bundle exec rake quality:runtime_abi"
        raise "verification must run #{abi_gate}" unless values.include?(abi_gate)
        return if values.include?("bundle exec rake test")

        missing = tests.reject { |test| values.include?("bundle exec ruby -Itest #{test}") }
        raise "verification must run every selected test: #{missing.join(', ')}" unless missing.empty?
      end

      def parse_allowed_command(command, tests)
        tokens = Shellwords.split(command)
        return true if AUXILIARY_COMMANDS.include?(tokens)
        if tokens.values_at(0, 1, 2) == %w[bundle exec rake] && tokens.length == 4
          return RAKE_TASKS.include?(tokens.fetch(3))
        end

        tokens.length == 5 && tokens.values_at(0, 1, 2) == %w[bundle exec ruby] &&
          tokens.fetch(3) == "-Itest" && tests.include?(tokens.fetch(4))
      rescue ArgumentError
        false
      end

      def verify_runtime_evidence(evidence)
        missing = @runtime_paths - evidence
        raise "evidence omits changed runtime-facing paths: #{missing.join(', ')}" unless missing.empty?
      end

      def regression_test?(path)
        path.end_with?("_test.rb") && @interactions.values.flatten.include?(path) &&
          File.file?(File.join(@root, path))
      end

      def unique_nonempty_strings?(values)
        values.is_a?(Array) && !values.empty? && values.all?(String) &&
          values.none?(&:empty?) && values.uniq.length == values.length
      end
    end
  end
end
