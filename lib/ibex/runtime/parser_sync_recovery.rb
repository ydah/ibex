# frozen_string_literal: true

module Ibex
  module Runtime
    # Panic-mode synchronization used only when yacc's explicit `error` token
    # cannot be shifted. Included by Parser to share its table and event paths.
    module ParserSyncRecovery
      # @rbs!
      #   private def parser_tables: () -> Hash[Symbol, untyped]
      #   private def table_lookup: (untyped, Integer, Integer) -> untyped
      #   private def default_action: (Integer) -> untyped
      #   private def token_to_str: (untyped) -> String
      #   private def trace: (String) -> void
      #   private def continue_recovery: () -> untyped
      #   private def reject_recovery_eof: () -> [:done, CST::Node?]
      #   private def finish_recovery: (untyped, untyped, untyped, untyped, Integer, Array[untyped],
      #     Hash[String, untyped]?, String, Array[Proc]?) -> [:continue]

      private

      # @rbs () -> bool
      def sync_recovery_configured?
        tokens = parser_tables[:recovery_sync_tokens]
        tokens.is_a?(Array) && !tokens.empty?
      end

      # @rbs () -> bool
      def sync_recovery_active?
        !@sync_recovery_context.nil?
      end

      # @rbs (Hash[Symbol, untyped] context, Hash[String, untyped]? token_data,
      #   Array[Proc]? observers) -> untyped
      def begin_sync_recovery(context, token_data, observers)
        @sync_recovery_context = context
        @sync_recovery_token_data = token_data
        @sync_recovery_observers = observers
        continue_sync_recovery
      end

      # @rbs () -> untyped
      def continue_sync_recovery
        return reject_sync_recovery_eof if @lookahead == Parser::EOF_TOKEN
        return finish_sync_recovery if sync_token?(@lookahead) && synchronize_for_current_token

        continue_recovery
      end

      # @rbs (untyped token_id) -> bool
      def sync_token?(token_id)
        tokens = parser_tables[:recovery_sync_tokens]
        tokens.is_a?(Array) && tokens.include?(token_id)
      end

      # @rbs () -> bool
      def synchronize_for_current_token
        loop do
          action = sync_action(@state_stack.last, @lookahead)
          return true unless action.nil? || action.first == :error
          return false if @state_stack.length == 1

          trace("recover: pop state #{@state_stack.last} for sync token")
          @state_stack.pop
          @value_stack.pop
          @location_stack&.pop
        end
      end

      # @rbs (Integer state, Integer token_id) -> untyped
      def sync_action(state, token_id)
        return [:error] unless parser_tables.fetch(:token_names).key?(token_id)

        table_lookup(parser_tables.fetch(:actions), state, token_id) || default_action(state) || [:error]
      end

      # @rbs () -> [:continue]
      def finish_sync_recovery
        context = @sync_recovery_context || raise(ParseError, "(recovery):1:1: missing synchronization context")
        token_data = @sync_recovery_token_data
        observers = @sync_recovery_observers
        clear_sync_recovery
        @recovery_shifts = Parser::RECOVERY_SHIFTS
        trace("recover: synchronized before #{token_to_str(@lookahead)} in state #{@state_stack.last}")
        finish_recovery(
          context[:token_id], context[:token_display], context[:value], context[:location], context[:state],
          context.fetch(:value_stack), token_data, context.fetch(:reason), observers
        )
      end

      # @rbs () -> [:done, CST::Node?]
      def reject_sync_recovery_eof
        clear_sync_recovery
        reject_recovery_eof
      end

      # @rbs () -> void
      def clear_sync_recovery
        @sync_recovery_context = nil
        @sync_recovery_token_data = nil
        @sync_recovery_observers = nil
      end
    end
  end
end
