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

      # @rbs @index: Integer
      # @rbs @active: bool

      # @rbs () -> void
      def initialize
        @phase = :initialized
        @index = 0 #: Integer
        @active = false #: bool
      end

      # @rbs (Symbol phase) -> void
      def begin_phase!(phase)
        raise "normalization is already complete" if @index == PHASES.length
        raise "normalization phase already active: #{@phase}" if @active

        expected = PHASES.fetch(@index)
        raise "normalization phase order drift: expected #{expected}, got #{phase}" unless phase == expected

        @phase = phase
        @active = true
      end

      # @rbs () -> void
      def complete_phase!
        raise "normalization phase completion without an active phase" unless @active

        @index += 1
        @active = false
        @phase = :complete if @index == PHASES.length
      end
    end
  end
end
