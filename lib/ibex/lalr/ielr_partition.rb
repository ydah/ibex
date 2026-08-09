# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Ibex
  module LALR
    # Deterministically merges compatible canonical LR(1) states and splits
    # partitions until their outgoing transitions are congruent.
    class IELRPartition
      # @rbs! type contribution_action = [:shift] | [:reduce, Integer] | [:accept]

      AUGMENTED_PRODUCTION = -1 #: Integer

      # @rbs @grammar: IR::Grammar
      # @rbs @states: Array[item_set]
      # @rbs @transitions: transitions
      # @rbs @contributions: Array[Hash[Integer, Set[contribution_action]]]
      # @rbs @initial_partition_count: Integer?
      # @rbs @final_partition_count: Integer?
      # @rbs @profile: bool

      attr_reader :initial_partition_count #: Integer?
      attr_reader :final_partition_count #: Integer?

      # @rbs (IR::Grammar grammar, Array[item_set] states, transitions transitions, ?profile: bool) -> void
      def initialize(grammar, states, transitions, profile: false)
        @grammar = grammar
        @states = states
        @transitions = transitions
        @contributions = Array.new(states.length) { |state_id| action_contributions(state_id) }
        @initial_partition_count = nil
        @final_partition_count = nil
        @profile = profile
      end

      # @rbs () -> [Array[packed_items], transitions]
      def build
        partitions = initial_partitions
        @initial_partition_count = partitions.length if @profile
        partitions = refine_transitions(partitions)
        @final_partition_count = partitions.length if @profile
        indexes = partition_indexes(partitions)
        items = partitions.map { |members| merge_items(members) }
        transitions = partitions.map do |members|
          @transitions.fetch(members.first).to_h do |symbol_id, target|
            [symbol_id, indexes.fetch(target)]
          end
        end
        [items, transitions]
      end

      private

      # @rbs () -> Array[state_partition]
      def initial_partitions
        cores = {} #: Hash[Array[item_core], Array[Integer]]
        @states.each_with_index do |items, state_id|
          cores[core_key(items)] ||= []
          cores.fetch(core_key(items)) << state_id
        end
        cores.values.flat_map { |members| compatible_partitions(members) }
      end

      # @rbs (Array[Integer] members) -> Array[state_partition]
      def compatible_partitions(members)
        partitions = [] #: Array[state_partition]
        members.each do |state_id|
          partition = partitions.find { |candidate| compatible?(candidate + [state_id]) }
          partition ? partition << state_id : partitions << [state_id]
        end
        partitions
      end

      # A canonical member may gain an action only where it previously had no
      # action. Every nonempty member cell must equal the merged cell.
      # @rbs (state_partition members) -> bool
      def compatible?(members)
        merged = Hash.new { |hash, key| hash[key] = Set.new } #: Hash[Integer, Set[contribution_action]]
        members.each do |state_id|
          @contributions.fetch(state_id).each { |token_id, actions| merged[token_id].merge(actions) }
        end
        merged.all? do |token_id, actions|
          members.all? do |state_id|
            member_actions = @contributions.fetch(state_id)[token_id]
            member_actions.nil? || member_actions.empty? || member_actions == actions
          end
        end
      end

      # @rbs (Array[state_partition] partitions) -> Array[state_partition]
      def refine_transitions(partitions)
        loop do
          indexes = partition_indexes(partitions)
          refined = partitions.flat_map do |members|
            members.group_by { |state_id| transition_signature(state_id, indexes) }.values
          end
          return partitions if refined == partitions

          partitions = refined
        end
      end

      # @rbs (Integer state_id, Hash[Integer, Integer] indexes) -> Array[[Integer, Integer]]
      def transition_signature(state_id, indexes)
        @transitions.fetch(state_id).map do |symbol_id, target|
          [symbol_id, indexes.fetch(target)] #: [Integer, Integer]
        end.sort
      end

      # @rbs (Array[state_partition] partitions) -> Hash[Integer, Integer]
      def partition_indexes(partitions)
        indexes = {} #: Hash[Integer, Integer]
        partitions.each_with_index do |members, partition_id|
          members.each { |state_id| indexes[state_id] = partition_id }
        end
        indexes
      end

      # @rbs (state_partition members) -> packed_items
      def merge_items(members)
        merged = Hash.new { |hash, key| hash[key] = Set.new } #: packed_items
        members.each do |state_id|
          @states.fetch(state_id).each do |production_id, dot, lookahead|
            merged[[production_id, dot]] << lookahead
          end
        end
        merged
      end

      # @rbs (Integer state_id) -> Hash[Integer, Set[contribution_action]]
      def action_contributions(state_id)
        actions = Hash.new { |hash, key| hash[key] = Set.new } #: Hash[Integer, Set[contribution_action]]
        @transitions.fetch(state_id).each_key do |symbol_id|
          symbol = @grammar.symbol_by_id(symbol_id)
          actions[symbol_id] << [:shift] if symbol&.terminal?
        end
        @states.fetch(state_id).each do |production_id, dot, lookahead|
          next unless dot == rhs_for(production_id).length

          action = production_id.negative? ? [:accept] : [:reduce, production_id]
          actions[lookahead] << action
        end
        actions
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        if production_id.negative?
          name = @grammar.starts.fetch(-production_id - 1)
          start = @grammar.symbol(name) || raise(Ibex::Error, "missing start symbol #{name}")
          return [start.id]
        end

        @grammar.productions.fetch(production_id).rhs
      end

      # @rbs (item_set items) -> Array[item_core]
      def core_key(items)
        items.map do |production_id, dot, _lookahead|
          [production_id, dot] #: item_core
        end.uniq.sort
      end
    end
  end
end
