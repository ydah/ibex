# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Normalize
    # Verifies the ordered boundaries of normalization phases.
    class PhaseGuard
      PHASES = %i[
        declarations parameter_templates inline_rules symbols parser_contract
        productions expansions validation build
      ].freeze

      attr_reader :phase #: Symbol

      # @rbs () -> void
      def initialize
        @phase = :initialized
        @index = 0
      end

      # @rbs (Symbol phase) -> void
      def begin_phase!(phase)
        expected = PHASES.fetch(@index)
        raise "normalization phase order drift: expected #{expected}, got #{phase}" unless phase == expected

        @phase = phase
      end

      # @rbs () -> void
      def complete_phase!
        @index += 1
        @phase = :complete if @index == PHASES.length
      end
    end
  end
end
