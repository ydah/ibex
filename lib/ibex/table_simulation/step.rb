# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module TableSimulation
    # One immutable parser-table action.
    class Step
      attr_reader :sequence #: Integer
      attr_reader :state #: Integer
      attr_reader :token_id #: Integer
      attr_reader :token #: String
      attr_reader :action #: String
      attr_reader :action_source #: String
      attr_reader :production_id #: Integer?
      attr_reader :lhs #: String?
      attr_reader :rhs_length #: Integer?
      attr_reader :target_state #: Integer?
      attr_reader :stack_depth_before #: Integer
      attr_reader :stack_depth_after #: Integer

      # @rbs (sequence: Integer, state: Integer, token_id: Integer, token: String, action: String,
      #   action_source: String, production_id: Integer?, lhs: String?, rhs_length: Integer?,
      #   target_state: Integer?, stack_depth_before: Integer, stack_depth_after: Integer) -> void
      def initialize(sequence:, state:, token_id:, token:, action:, action_source:, production_id:, lhs:, rhs_length:,
                     target_state:, stack_depth_before:, stack_depth_after:)
        @sequence = sequence
        @state = state
        @token_id = token_id
        @token = token.dup.freeze
        @action = action.dup.freeze
        @action_source = action_source.dup.freeze
        @production_id = production_id
        @lhs = lhs&.dup&.freeze
        @rhs_length = rhs_length
        @target_state = target_state
        @stack_depth_before = stack_depth_before
        @stack_depth_after = stack_depth_after
        freeze
      end

      # @rbs () -> Hash[String, untyped]
      def to_h
        {
          "sequence" => @sequence,
          "state" => @state,
          "token_id" => @token_id,
          "token" => @token,
          "action" => @action,
          "action_source" => @action_source,
          "production_id" => @production_id,
          "lhs" => @lhs,
          "rhs_length" => @rhs_length,
          "target_state" => @target_state,
          "stack_depth_before" => @stack_depth_before,
          "stack_depth_after" => @stack_depth_after
        }.freeze
      end
    end
  end
end
