# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Mutable stack storage for one parser invocation.
    #
    # The parser keeps local aliases to these arrays in its hot paths. The
    # object owns their lifetime and replacement so recovery and push-session
    # reset cannot accidentally leave one stack behind.
    class ParseSessionState
      attr_reader :state_stack #: Array[Integer]
      attr_reader :value_stack #: Array[Object?]
      attr_reader :location_stack #: Array[Object?]?

      # @rbs () -> void
      def initialize
        reset!
      end

      # @rbs () -> void
      def reset!
        @state_stack = []
        @value_stack = []
        @location_stack = nil
      end

      # @rbs (Array[Integer], Array[Object?], Array[Object?]?) -> void
      def replace!(state_stack, value_stack, location_stack)
        @state_stack = state_stack
        @value_stack = value_stack
        @location_stack = location_stack
      end

      # @rbs (Array[Object?]) -> void
      def replace_value_stack!(value_stack)
        @value_stack = value_stack
      end

      # @rbs (Array[Object?]?) -> void
      def replace_location_stack!(location_stack)
        @location_stack = location_stack
      end
    end
  end
end
