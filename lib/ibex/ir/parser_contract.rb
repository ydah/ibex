# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../location"

module Ibex
  module IR
    # Root-owned parser configuration persisted by Grammar IR version 3.
    class ParserContract
      DEFINITIONS = {
        algorithm: {
          configuration: "parser.algorithm", values: %i[slr lalr ielr lr1].freeze
        }.freeze,
        entries: {
          configuration: "parser.entries", values: %i[shared isolated].freeze
        }.freeze,
        cst_trivia: {
          configuration: "cst.trivia", values: %i[leading balanced drop].freeze
        }.freeze
      }.freeze #: Hash[Symbol, Hash[Symbol, untyped]]

      # One specified or explicitly unspecified contract field.
      class Entry
        attr_reader :key #: Symbol
        attr_reader :value #: Symbol?
        attr_reader :location #: Location?
        attr_reader :explicit #: bool

        # @rbs (Symbol key, ?value: Symbol?, ?location: Location?, ?explicit: bool) -> void
        def initialize(key, value: nil, location: nil, explicit: false)
          definition = DEFINITIONS.fetch(key) { raise ArgumentError, "unknown parser contract key #{key.inspect}" }
          validate_state!(key, definition.fetch(:values), value, location, explicit)

          @key = key
          @value = value
          @location = location
          @explicit = explicit
          freeze
        end

        # @rbs () -> Hash[Symbol, untyped]
        def to_h
          { value: @value&.to_s, explicit: @explicit, loc: serialized_location }
        end

        private

        # @rbs (Symbol key, Array[Symbol] allowed, Symbol? value, Location? location, bool explicit) -> void
        def validate_state!(key, allowed, value, location, explicit)
          raise ArgumentError, "explicit must be boolean" unless [true, false].include?(explicit)

          if explicit
            raise ArgumentError, "#{key} must be one of #{allowed.join(', ')}" unless allowed.include?(value)
            unless location.is_a?(Location) && location.file && !location.file.empty?
              raise ArgumentError, "explicit #{key} requires a source location with a file"
            end

            return
          end

          raise ArgumentError, "unspecified #{key} cannot carry a value" unless value.nil?
          raise ArgumentError, "unspecified #{key} cannot carry a source location" unless location.nil?
        end

        # @rbs () -> Hash[Symbol, untyped]?
        def serialized_location
          location = @location
          return unless location

          { file: location.file, line: location.line, column: location.column }
        end
      end

      attr_reader :algorithm #: Entry
      attr_reader :entries #: Entry
      attr_reader :cst_trivia #: Entry

      # @rbs (?algorithm: Entry?, ?entries: Entry?, ?cst_trivia: Entry?) -> void
      def initialize(algorithm: nil, entries: nil, cst_trivia: nil)
        @algorithm = normalize_entry(:algorithm, algorithm)
        @entries = normalize_entry(:entries, entries)
        @cst_trivia = normalize_entry(:cst_trivia, cst_trivia)
        freeze
      end

      # @rbs () -> Hash[Symbol, Hash[Symbol, untyped]]
      def to_h
        {
          algorithm: @algorithm.to_h,
          entries: @entries.to_h,
          cst_trivia: @cst_trivia.to_h
        }
      end

      # Values supplied to the typed resolver; unspecified fields are absent.
      # @rbs () -> Hash[String, untyped]
      def configuration_values
        specified_entries.to_h do |entry|
          [DEFINITIONS.fetch(entry.key).fetch(:configuration), entry.value]
        end
      end

      # Source locations supplied to the typed resolver.
      # @rbs () -> Hash[String, Location]
      def configuration_locations
        specified_entries.to_h do |entry|
          location = entry.location || raise("explicit parser contract entry is missing its location")
          [DEFINITIONS.fetch(entry.key).fetch(:configuration), location]
        end
      end

      private

      # @rbs (Symbol key, Entry? entry) -> Entry
      def normalize_entry(key, entry)
        entry ||= Entry.new(key)
        raise ArgumentError, "#{key} must be a ParserContract::Entry" unless entry.is_a?(Entry)
        raise ArgumentError, "#{key} entry has key #{entry.key.inspect}" unless entry.key == key

        entry
      end

      # @rbs () -> Array[Entry]
      def specified_entries
        [@algorithm, @entries, @cst_trivia].select(&:explicit)
      end
    end
  end
end
