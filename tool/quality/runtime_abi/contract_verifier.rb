# frozen_string_literal: true

require "yaml"
require_relative "document"
require_relative "evidence_verifier"
require_relative "reviewed_policy"
require_relative "test_contract_verifier"

module Ibex
  module Quality
    # Cross-checks documented ABI versions against implementation authorities.
    class RuntimeABIContractVerifier
      include RuntimeABIDocument

      attr_reader :abi_contract, :test_contract

      ABI_KEYS = %w[assessment contract_version ir parser_tables runtime_paths versions].freeze
      IR_KEYS = %w[automaton grammar lexer].freeze
      VERSION_FIELDS = %w[current_writer readable migrations preserve_loaded_version].freeze
      LEXER_FIELDS = %w[current_writer embedded_in_grammar migrations readable standalone].freeze

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def verify!
        @abi_contract = load_contract(path("docs/policy/runtime-abi-evolution.md"), "runtime-abi")
        @test_contract = load_contract(path("docs/records/test-interactions.md"), "test-interaction")
        verify_abi(@abi_contract)
        RuntimeABITestContractVerifier.new(root: @root, contract: @test_contract).verify!
        self
      end

      private

      def verify_abi(contract)
        exact_keys!(contract, ABI_KEYS, "runtime ABI contract")
        raise "runtime ABI contract_version must be 1" unless contract["contract_version"] == 1

        verify_ir(contract.fetch("ir"))
        verify_tables(contract.fetch("parser_tables"))
        verify_versions(contract.fetch("versions"))
        verify_paths(contract.fetch("runtime_paths"))
        unless contract.fetch("assessment") == RuntimeABIReviewedPolicy::ASSESSMENT
          raise "runtime ABI assessment vocabulary is stale"
        end

        RuntimeABIEvidenceVerifier.new(root: @root).verify!
      end

      def verify_ir(ir_contract)
        exact_keys!(ir_contract, IR_KEYS, "runtime ABI ir")
        current = integer_constant("lib/ibex/ir/grammar_ir.rb", "SCHEMA_VERSION")
        readable = numeric_array_constant(
          "lib/ibex/ir/grammar_ir.rb", "SUPPORTED_SCHEMA_VERSIONS", current, "SCHEMA_VERSION"
        )
        verify_versioned_ir(ir_contract.fetch("grammar"), "Grammar", current, readable)
        verify_versioned_ir(ir_contract.fetch("automaton"), "Automaton", current, readable)
        verify_schemas("grammar", readable)
        verify_schemas("automaton", readable)

        lexer = ir_contract.fetch("lexer")
        exact_keys!(lexer, LEXER_FIELDS, "Lexer IR")
        lexer_current = integer_constant("lib/ibex/ir/lexer_ir.rb", "LEXER_SCHEMA_VERSION")
        lexer_readable = numeric_array_constant(
          "lib/ibex/ir/lexer_ir.rb", "SUPPORTED_LEXER_SCHEMA_VERSIONS", lexer_current, "LEXER_SCHEMA_VERSION"
        )
        expected = {
          "current_writer" => lexer_current, "readable" => lexer_readable, "migrations" => [],
          "standalone" => true, "embedded_in_grammar" => true
        }
        raise "Lexer IR policy is stale" unless lexer == expected

        verify_schemas("lexer", lexer_readable)
      end

      def verify_versioned_ir(value, label, current, readable)
        exact_keys!(value, VERSION_FIELDS, "#{label} IR")
        expected = {
          "current_writer" => current, "readable" => readable,
          "migrations" => [], "preserve_loaded_version" => false
        }
        raise "#{label} IR policy is stale" unless value == expected
      end

      def verify_tables(tables)
        exact_keys!(tables, %w[cst_readable current_writer fail_before_input readable], "parser tables")
        current = integer_constant("lib/ibex/runtime/table_format.rb", "PARSER_TABLE_FORMAT_VERSION")
        readable = numeric_array_constant(
          "lib/ibex/runtime/table_format.rb", "SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS", current,
          "PARSER_TABLE_FORMAT_VERSION"
        )
        expected = {
          "current_writer" => current, "readable" => readable,
          "cst_readable" => [current], "fail_before_input" => true
        }
        raise "parser-table format policy is stale" unless tables == expected
      end

      def verify_versions(versions)
        exact_keys!(versions, %w[generator runtime runtime_dependency], "runtime ABI versions")
        generator = string_constant("lib/ibex/version.rb", "VERSION")
        runtime = string_constant("lib/ibex/runtime/version.rb", "VERSION")
        expected = { "generator" => generator, "runtime" => runtime, "runtime_dependency" => "~> #{runtime}" }
        raise "generator/runtime version matrix is stale" unless versions == expected

        gemspec = File.binread(path("ibex.gemspec"))
        marker = "spec.add_dependency \"ibex-runtime\", \"~> \#{Ibex::Runtime::VERSION}\""
        raise "ibex.gemspec runtime dependency is not bound to Runtime::VERSION" unless gemspec.include?(marker)
      end

      def verify_paths(paths)
        unless paths.is_a?(Array) && !paths.empty? && paths.all? { |item| item.is_a?(String) && !item.empty? }
          raise "runtime_paths must be a non-empty string list"
        end
        raise "runtime_paths must be unique" unless paths.uniq.length == paths.length

        missing = RuntimeABIReviewedPolicy::REQUIRED_RUNTIME_PATHS - paths
        raise "runtime_paths cannot omit required protections: #{missing.join(', ')}" unless missing.empty?
      end

      def verify_schemas(kind, versions)
        versions.each do |version|
          schema_name = if %w[grammar
                              automaton].include?(kind)
                          "#{kind}-ir.schema.json"
                        else
                          "#{kind}-ir-v#{version}.schema.json"
                        end
          schema = path("schema/#{schema_name}")
          raise "missing #{relative(schema)}" unless File.file?(schema)
        end
      end

      def integer_constant(relative_path, name)
        source = File.binread(path(relative_path))
        match = source.match(/^\s*#{Regexp.escape(name)} = (\d+)\b/)
        raise "cannot find #{name} in #{relative_path}" unless match

        Integer(match[1], 10)
      end

      def string_constant(relative_path, name)
        source = File.binread(path(relative_path))
        match = source.match(/^\s*#{Regexp.escape(name)} = "([^"]+)"/)
        raise "cannot find #{name} in #{relative_path}" unless match

        match[1]
      end

      def numeric_array_constant(relative_path, name, current, current_name)
        source = File.binread(path(relative_path))
        match = source.match(/^\s*#{Regexp.escape(name)} = \[(.*?)\]\.freeze/)
        raise "cannot find #{name} in #{relative_path}" unless match

        match[1].split(",").map do |token|
          stripped = token.strip
          next Integer(stripped, 10) if stripped.match?(/\A\d+\z/)
          next current if stripped == current_name

          raise "unsupported token #{stripped.inspect} in #{name}"
        end
      end

      def path(relative_path)
        File.join(@root, relative_path)
      end
    end
  end
end
