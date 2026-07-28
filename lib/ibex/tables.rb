# frozen_string_literal: true

require "ibex/tables/compact"
require "ibex/tables/compact_actions"
require "ibex/tables/compact_productions"

module Ibex
  # Parser table construction and row-displacement compression.
  module Tables
    # @rbs!
    #   private def runtime_action: (IR::parser_action action) -> IR::runtime_action
    #   private def self.runtime_action: (IR::parser_action action) -> IR::runtime_action

    TableSet = Struct.new(:actions, :gotos, :default_actions, keyword_init: true)

    # @rbs (IR::Automaton automaton, ?format: Symbol | String) -> TableSet
    def build(automaton, format: :compact)
      action_rows = automaton.states.map do |state|
        state.actions.transform_values do |action|
          runtime_action(action)
        end
      end
      goto_rows = automaton.states.map(&:gotos)
      defaults = automaton.states.map do |state|
        runtime_action(state.default_action) if state.default_action
      end
      if format.to_sym == :plain
        return TableSet.new(actions: action_rows, gotos: goto_rows,
                            default_actions: defaults)
      end
      raise ArgumentError, "unknown table format #{format.inspect}" unless format.to_sym == :compact

      TableSet.new(
        actions: CompactActions.build(action_rows),
        gotos: Compact.build(goto_rows),
        default_actions: defaults
      )
    end
    module_function :build

    # @rbs skip
    private

    # @rbs skip
    def runtime_action(action)
      case action.fetch(:type).to_sym
      when :shift
        shift = action #: IR::shift_action
        [:shift, shift.fetch(:state)]
      when :reduce
        reduce = action #: IR::reduce_action
        [:reduce, reduce.fetch(:production)]
      when :accept then [:accept]
      when :error then [:error]
      else raise Ibex::Error, "unknown parser action #{action.inspect}"
      end
    end
    module_function :runtime_action

    class << self
      private :runtime_action
    end
  end
end
