# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "parser" unless defined?(Ibex::Runtime::Parser)

module Ibex
  module Runtime
    # Emits schema-v1 immutable runtime events as JSON Lines.
    class EventJSONLTracer
      # @rbs!
      #   interface _EventTraceOutput
      #     def puts: (String) -> untyped
      #   end

      attr_reader :parser #: Parser
      attr_reader :subscription #: Observation::Subscription

      # @rbs (Parser parser, _EventTraceOutput output) -> void
      def initialize(parser, output)
        @parser = parser
        @output = output
        @subscription = parser.observe { |event| output.puts(JSON.generate(event.to_h)) }
      end

      # @rbs () -> bool
      def detach
        @parser.unobserve(@subscription)
      end

      # @rbs [P < Parser] (P parser, io: _EventTraceOutput) -> EventJSONLTracer
      def self.attach(parser, io:)
        new(parser, io)
      end
    end
  end
end
