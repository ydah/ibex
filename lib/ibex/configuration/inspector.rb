# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../frontend/ast"
require_relative "../frontend/resolution"
require_relative "../ir/grammar_ir"
require_relative "explanation"

module Ibex
  module Configuration
    # Converts parsed source or validated Grammar IR into static configuration facts.
    # rubocop:disable Metrics/ModuleLength -- source and IR adapters share one closed evidence vocabulary.
    module Inspector
      PARSER_CONTRACT_KEYS = %w[parser.algorithm parser.entries cst.trivia].freeze #: Array[String]

      # @rbs (Frontend::Resolution resolution) -> Input
      def from_source(resolution)
        unless resolution.is_a?(Frontend::Resolution)
          raise ArgumentError, "source configuration inspection requires a Frontend::Resolution"
        end

        values = {} #: Hash[String, untyped]
        locations = {} #: Hash[String, Location]
        evidence = {} #: Hash[String, Array[Evidence]]
        root = resolution.root
        extended_loc = root.extended_loc
        add_source_fact(values, locations, evidence, "grammar.mode", :extended, extended_loc) if extended_loc
        add_source_fact(values, locations, evidence, "parser.superclass", root.superclass, root.loc) if root.superclass
        add_source_options(root, values, locations, evidence)
        recordings = Registry.keys.to_h do |key|
          [key.name,
           Recording.new(:source, "the grammar source and contained import closure were inspected statically")]
        end
        Input.new(
          kind: :grammar_source, path: resolution.root_path, files: resolution.files,
          grammar_values: values, grammar_locations: locations, evidence: evidence, recordings: recordings
        )
      end
      module_function :from_source

      # @rbs (IR::Grammar grammar, path: String) -> Input
      def from_grammar_ir(grammar, path:)
        raise ArgumentError, "configuration inspection requires Grammar IR" unless grammar.is_a?(IR::Grammar)

        values = {} #: Hash[String, untyped]
        locations = {} #: Hash[String, Location]
        evidence = {} #: Hash[String, Array[Evidence]]
        recordings = Registry.keys.to_h do |key|
          reason = "Grammar IR does not persist #{key.name}; " \
                   "current builtin or CLI selection is not historical evidence"
          [key.name, Recording.new(:unavailable, reason)]
        end
        add_ir_fact(values, evidence, recordings, "grammar.mode", grammar.mode) if grammar.mode != :default
        add_ir_fact(values, evidence, recordings, "parser.superclass", grammar.superclass) if grammar.superclass
        add_ir_fact(values, evidence, recordings, "actions.omit_calls", grammar.options.fetch(:omit_action_call))
        add_parser_contract(grammar, values, locations, evidence, recordings)
        Input.new(
          kind: :grammar_ir, path: path, schema_version: grammar.schema_version,
          grammar_values: values, grammar_locations: locations, evidence: evidence, recordings: recordings
        )
      end
      module_function :from_grammar_ir

      # @rbs (Hash[String, untyped] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence, String name, untyped value,
      #   Frontend::Location | Location location) -> void
      def add_source_fact(values, locations, evidence, name, value, location)
        key = Registry.fetch(name)
        location = configuration_location(location)
        values[name] = value
        locations[name] = location
        evidence[name] = [
          Evidence.new(
            key, source: :grammar, value: value, status: :accepted, location: location,
                 reason: "selected by the grammar source"
          )
        ]
      end
      module_function :add_source_fact
      private_class_method :add_source_fact

      # @rbs (Frontend::AST::Root root, Hash[String, untyped] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence) -> void
      def add_source_options(root, values, locations, evidence)
        occurrences = root.declarations.filter_map do |declaration|
          next unless declaration.is_a?(Frontend::AST::Options)

          declaration.names.filter_map do |name|
            value = option_value(name)
            [value, configuration_location(declaration.loc)] unless value.nil?
          end
        end.flatten(1)
        return if occurrences.empty?

        name = "actions.omit_calls"
        key = Registry.fetch(name)
        selected_value, selected_location = occurrences.last
        values[name] = selected_value
        locations[name] = selected_location
        evidence[name] = option_evidence(key, occurrences, selected_value)
      end
      module_function :add_source_options
      private_class_method :add_source_options

      # @rbs (String name) -> bool?
      def option_value(name)
        return true if name == "omit_action_call"
        return false if name == "no_omit_action_call"

        nil
      end
      module_function :option_value
      private_class_method :option_value

      # @rbs (Frontend::Location | Location location) -> Location
      def configuration_location(location)
        return location if location.is_a?(Ibex::Location)

        Ibex::Location.new(file: location.file, line: location.line, column: location.column)
      end
      module_function :configuration_location
      private_class_method :configuration_location

      # @rbs (Key key, Array[[bool, Location]] occurrences, bool selected_value) -> Array[Evidence]
      def option_evidence(key, occurrences, selected_value)
        occurrences.each_with_index.map do |(value, location), index|
          last = index == occurrences.length - 1
          status = if last
                     :accepted
                   else
                     (value == selected_value ? :duplicate : :conflicting)
                   end
          reason = if last
                     "last compatible options declaration selects the effective value"
                   elsif value == selected_value
                     "later identical source evidence selects the same value"
                   else
                     "later compatible source evidence supersedes this value"
                   end
          Evidence.new(key, source: :grammar, value: value, status: status, location: location, reason: reason)
        end
      end
      module_function :option_evidence
      private_class_method :option_evidence

      # @rbs (Hash[String, untyped] values, Hash[String, Array[Evidence]] evidence,
      #   Hash[String, Recording] recordings, String name, untyped value) -> void
      def add_ir_fact(values, evidence, recordings, name, value)
        key = Registry.fetch(name)
        values[name] = value
        evidence[name] = [
          Evidence.new(
            key, source: :grammar, value: value, status: :accepted,
                 reason: "selected by persisted Grammar IR configuration; original declaration location is unavailable"
          )
        ]
        recordings[name] = Recording.new(
          :recorded, "Grammar IR records the effective value but not the original declaration location"
        )
      end
      module_function :add_ir_fact
      private_class_method :add_ir_fact

      # @rbs (IR::Grammar grammar, Hash[String, untyped] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence, Hash[String, Recording] recordings) -> void
      def add_parser_contract(grammar, values, locations, evidence, recordings)
        contract = grammar.parser_contract
        if grammar.schema_version < 3 || contract.nil?
          record_unavailable_contract(grammar.schema_version, recordings)
          return
        end

        contract_entries(contract).each do |name, entry|
          add_contract_entry(name, entry, values, locations, evidence, recordings)
        end
      end
      module_function :add_parser_contract
      private_class_method :add_parser_contract

      # @rbs (Integer schema_version, Hash[String, Recording] recordings) -> void
      def record_unavailable_contract(schema_version, recordings)
        PARSER_CONTRACT_KEYS.each do |name|
          recordings[name] = Recording.new(
            :unavailable,
            "Grammar IR v#{schema_version} has no parser contract; " \
            "the current builtin or CLI value is not a historical fact"
          )
        end
      end
      module_function :record_unavailable_contract
      private_class_method :record_unavailable_contract

      # @rbs (String name, IR::ParserContract::Entry entry, Hash[String, untyped] values,
      #   Hash[String, Location] locations, Hash[String, Array[Evidence]] evidence,
      #   Hash[String, Recording] recordings) -> void
      def add_contract_entry(name, entry, values, locations, evidence, recordings)
        unless entry.explicit
          recordings[name] = Recording.new(
            :unspecified,
            "Grammar IR v3 marks this parser contract field unspecified; " \
            "the current builtin or CLI value is not a historical fact"
          )
          return
        end

        value = entry.value || raise("explicit parser contract entry has no value")
        location = entry.location || raise("explicit parser contract entry has no location")
        key = Registry.fetch(name)
        values[name] = value
        locations[name] = location
        evidence[name] = [
          Evidence.new(
            key, source: :grammar, value: value, status: :accepted, location: location,
                 reason: "selected by the Grammar IR v3 parser contract"
          )
        ]
        recordings[name] = Recording.new(:recorded, "Grammar IR v3 records an explicit parser contract")
      end
      module_function :add_contract_entry
      private_class_method :add_contract_entry

      # @rbs (IR::ParserContract contract) -> Hash[String, IR::ParserContract::Entry]
      def contract_entries(contract)
        {
          "parser.algorithm" => contract.algorithm,
          "parser.entries" => contract.entries,
          "cst.trivia" => contract.cst_trivia
        }
      end
      module_function :contract_entries
      private_class_method :contract_entries
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
