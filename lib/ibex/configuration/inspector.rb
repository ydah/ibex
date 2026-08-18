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
      extend self

      # @rbs (Frontend::Resolution resolution) -> Input
      def from_source(resolution)
        unless resolution.is_a?(Frontend::Resolution)
          raise ArgumentError, "source configuration inspection requires a Frontend::Resolution"
        end

        values = {} #: Hash[String, config_value]
        locations = {} #: Hash[String, Location]
        evidence = {} #: Hash[String, Array[Evidence]]
        root = resolution.root
        extended_loc = root.extended_loc
        add_source_fact(values, locations, evidence, "grammar.mode", :extended, extended_loc) if extended_loc
        add_source_fact(values, locations, evidence, "parser.superclass", root.superclass, root.loc) if root.superclass
        add_source_options(root, values, locations, evidence)
        add_source_parser_contract(root, values, locations, evidence)
        recordings = Registry.keys.to_h do |key|
          [key.name,
           Recording.new(:source, "the grammar source and contained import closure were inspected statically")]
        end
        Input.new(
          kind: :grammar_source, path: resolution.root_path, files: resolution.files,
          grammar_values: values, grammar_locations: locations, evidence: evidence, recordings: recordings
        )
      end

      # @rbs (IR::Grammar grammar, path: String) -> Input
      def from_grammar_ir(grammar, path:)
        raise ArgumentError, "configuration inspection requires Grammar IR" unless grammar.is_a?(IR::Grammar)

        values = {} #: Hash[String, config_value]
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

      module_function :from_source, :from_grammar_ir

      private

      # @rbs (Hash[String, config_value] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence, String name, config_value value,
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

      # @rbs (Frontend::AST::Root root, Hash[String, config_value] values, Hash[String, Location] locations,
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

      # @rbs (Frontend::AST::Root root, Hash[String, config_value] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence) -> void
      def add_source_parser_contract(root, values, locations, evidence)
        declaration = root.declarations.grep(Frontend::AST::ParserConfiguration).first
        return unless declaration.is_a?(Frontend::AST::ParserConfiguration)

        declaration.settings.each do |setting|
          key = setting.key == :cst_trivia ? "cst.trivia" : "parser.#{setting.key}"
          add_source_fact(
            values, locations, evidence, key, setting.value, setting.loc
          )
        end
      end

      # @rbs (String name) -> bool?
      def option_value(name)
        return true if name == "omit_action_call"
        return false if name == "no_omit_action_call"

        nil
      end

      # @rbs (Frontend::Location | Location location) -> Location
      def configuration_location(location)
        return location if location.is_a?(Ibex::Location)

        Ibex::Location.new(file: location.file, line: location.line, column: location.column)
      end

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

      # @rbs (Hash[String, config_value] values, Hash[String, Array[Evidence]] evidence,
      #   Hash[String, Recording] recordings, String name, config_value value) -> void
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

      # @rbs (IR::Grammar grammar, Hash[String, config_value] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence, Hash[String, Recording] recordings) -> void
      def add_parser_contract(grammar, values, locations, evidence, recordings)
        contract = grammar.parser_contract
        contract_entries(contract).each do |name, entry|
          add_contract_entry(name, entry, values, locations, evidence, recordings)
        end
      end

      # @rbs (String name, IR::ParserContract::Entry entry, Hash[String, config_value] values,
      #   Hash[String, Location] locations, Hash[String, Array[Evidence]] evidence,
      #   Hash[String, Recording] recordings) -> void
      def add_contract_entry(name, entry, values, locations, evidence, recordings)
        unless entry.explicit
          recordings[name] = Recording.new(
            :unspecified,
            "The current Grammar IR marks this parser contract field unspecified; " \
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
                 reason: "selected by the current Grammar IR parser contract"
          )
        ]
        recordings[name] = Recording.new(:recorded, "The current Grammar IR records an explicit parser contract")
      end

      # @rbs (IR::ParserContract contract) -> Hash[String, IR::ParserContract::Entry]
      def contract_entries(contract)
        {
          "parser.algorithm" => contract.algorithm,
          "parser.entries" => contract.entries,
          "cst.trivia" => contract.cst_trivia
        }
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
