# frozen_string_literal: true

require "yaml"
require_relative "document"

module Ibex
  module Quality
    # Cross-checks matrix arithmetic, interaction ownership, schedules, and goldens.
    class RuntimeABITestContractVerifier
      include RuntimeABIDocument

      AXES = %w[algorithm table cst locations entries].freeze
      INTERACTIONS = %w[
        parser_semantics generated_lexer semantic_actions table_encoding locations cst entry_modes
        parser_drivers generated_ast recovery resource_limits observation incremental_cst embedded_runtime
      ].freeze
      COVERAGE = %w[matrix matrix_and_focused focused_regression].freeze
      LONG_GATES = %w[test:matrix:full test:adversarial fuzz:long].freeze

      def initialize(root:, contract:)
        @root = File.expand_path(root)
        @contract = contract
      end

      def verify!
        exact_keys!(@contract, %w[contract_version golden interactions matrix scheduled_long_gates],
                    "test interaction contract")
        raise "test interaction contract_version must be 1" unless @contract["contract_version"] == 1

        verify_matrix
        verify_interactions
        verify_schedule
        verify_golden
      end

      private

      def verify_matrix
        declared = YAML.safe_load_file(path("test/matrix.yml"), permitted_classes: [], aliases: false)
        matrix = @contract.fetch("matrix")
        exact_keys!(matrix, %w[axes expected_cases representative_cases roles], "test interaction matrix")
        raise "matrix axes are stale or missing" unless matrix.fetch("axes") == declared.fetch("axes")

        product = matrix.fetch("axes").values.map(&:length).inject(1, :*)
        expected = matrix.fetch("expected_cases")
        raise "matrix expected_cases must be 96, got #{expected.inspect}" unless expected == 96
        raise "matrix product is #{product}, documented as #{expected}" unless product == expected
        raise "representative matrix must contain 12 cases" unless matrix.fetch("representative_cases") == 12
        unless declared.fetch("representative") == 12 && declared.fetch("full") == true
          raise "test/matrix.yml representative/full policy is stale"
        end

        roles = { "normal" => "representative", "scheduled" => "full", "promotion" => "full_review" }
        raise "matrix roles are stale" unless matrix.fetch("roles") == roles
      end

      def verify_interactions
        interactions = @contract.fetch("interactions")
        raise "interactions must be a non-empty list" unless interactions.is_a?(Array) && !interactions.empty?

        ids = interactions.map { |entry| entry.fetch("id") }
        raise "interaction inventory is stale or incomplete" unless ids.sort == INTERACTIONS.sort
        raise "interaction ids must be unique" unless ids.uniq.length == ids.length

        interactions.each { |entry| verify_interaction(entry) }
      rescue KeyError => e
        raise "interaction is missing a required field: #{e.message}"
      end

      def verify_interaction(entry)
        exact_keys!(entry, %w[axes coverage id tests], "interaction #{entry['id']}")
        axes = entry.fetch("axes")
        unless axes.is_a?(Array) && !axes.empty? && (axes - AXES).empty? && axes.uniq.length == axes.length
          raise "interaction #{entry.fetch('id')} has invalid or missing axes"
        end

        raise "interaction #{entry.fetch('id')} has invalid coverage" unless COVERAGE.include?(entry.fetch("coverage"))

        verify_test_paths(entry)
      end

      def verify_test_paths(entry)
        tests = entry.fetch("tests")
        unless tests.is_a?(Array) && !tests.empty? && tests.all?(String)
          raise "interaction #{entry.fetch('id')} must own tests"
        end

        missing = tests.reject { |test| File.file?(path(test)) }
        raise "interaction #{entry.fetch('id')} has missing tests: #{missing.join(', ')}" unless missing.empty?
      end

      def verify_schedule
        gates = @contract.fetch("scheduled_long_gates")
        raise "scheduled long gates are stale" unless gates == LONG_GATES

        workflow = File.binread(path(".github/workflows/main.yml"))
        raise "CI schedule is missing" unless workflow.match?(/^\s+schedule:\s*$/)

        LONG_GATES.each do |gate|
          command = "bundle exec rake #{gate}"
          raise "scheduled CI is missing #{command}" unless workflow.include?(command)
        end
        raise "normal CI is missing representative matrix" unless workflow.include?("bundle exec rake test:matrix\n")
        raise "normal CI is missing zero-cost golden" unless workflow.include?("bundle exec rake test:zero_cost")
      end

      def verify_golden
        golden = @contract.fetch("golden")
        exact_keys!(golden, %w[digest_path policy sources task update_command], "golden contract")
        expected = {
          "task" => "test:zero_cost", "policy" => "feature_off_byte_identity",
          "digest_path" => "test/golden/digests.yml", "sources" => golden_sources,
          "update_command" => "bundle exec rake golden:update"
        }
        raise "golden zero-cost contract is stale" unless golden == expected
        raise "golden digest index is missing" unless File.file?(path(golden.fetch("digest_path")))

        rakefile = File.binread(path("Rakefile"))
        %w[test:zero_cost golden:update].each do |task|
          name = task.split(":").last
          raise "Rakefile is missing #{task}" unless rakefile.match?(/task :#{Regexp.escape(name)}\b/)
        end
      end

      def golden_sources
        source = File.binread(path("tool/quality/golden.rb"))
        match = source.match(/SOURCES = \[(.*?)\]\.freeze/m)
        raise "cannot find Golden::SOURCES" unless match

        match[1].scan(/"([^"]+)"/).flatten
      end

      def path(relative_path)
        File.join(@root, relative_path)
      end
    end
  end
end
