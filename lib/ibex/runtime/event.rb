# frozen_string_literal: true
# rbs_inline: enabled

require_relative "event_sanitizer" unless defined?(Ibex::Runtime::EventSanitizer)

module Ibex
  module Runtime
    # One immutable versioned parser observation.
    class Event
      SCHEMA_VERSION = 1 #: Integer
      IDENTIFIER = "runtime-event" #: String
      TYPES = %i[
        start shift reduce error recover discard accept reject cst_built cst_fallback cst_reuse
      ].freeze #: Array[Symbol]

      attr_reader :type #: Symbol
      attr_reader :sequence #: Integer
      attr_reader :data #: Hash[String, untyped]

      # @rbs (type: Symbol, sequence: Integer, data: Hash[untyped, untyped]) -> void
      def initialize(type:, sequence:, data:)
        raise ArgumentError, "unknown runtime event type #{type.inspect}" unless TYPES.include?(type)
        raise ArgumentError, "runtime event sequence must be positive" unless sequence.positive?

        @type = type
        @sequence = sequence
        @data = EventSanitizer.data(data)
        @document = {
          "ibex_runtime_event" => IDENTIFIER,
          "schema_version" => SCHEMA_VERSION,
          "sequence" => @sequence,
          "event" => @type.to_s.freeze,
          "data" => @data
        }.freeze #: Hash[String, untyped]
        freeze
      end

      # @rbs () -> Hash[String, untyped]
      def to_h
        @document
      end
    end
  end
end
