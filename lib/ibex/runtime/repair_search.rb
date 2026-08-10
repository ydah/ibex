# frozen_string_literal: true
# rbs_inline: enabled

require_relative "repair_priority_queue" unless defined?(Ibex::Runtime::RepairPriorityQueue)

module Ibex
  module Runtime
    # Bounded Dijkstra search over LR state stacks. Semantic actions never run.
    # rubocop:disable Metrics/ClassLength -- queue policy and LR transitions form one bounded search invariant.
    class RepairSearch
      # @rbs!
      #   type configuration_key = [Array[Integer], Integer, Integer, bool]
      #   type priority = Array[untyped]
      #   type lookup_table = Tables::action_table | Tables::goto_table
      #   type lookup_value = IR::runtime_action | Integer?

      NEED_INPUT = Object.new.freeze #: Object
      LIMIT = Object.new.freeze #: Object
      Configuration = Struct.new(
        :stack, #: Array[Integer]
        :input_index, #: Integer
        :shifts, #: Integer
        :cost, #: Integer
        :edits, #: Array[RepairEdit]
        :goal, #: bool
        keyword_init: true
      )

      # @rbs @tables: Hash[Symbol, Object?]
      # @rbs @policy: RepairPolicy
      # @rbs @tokens: Array[RepairInput]
      # @rbs @complete: bool
      # @rbs @configurations: Integer
      # @rbs @heap: RepairPriorityQueue
      # @rbs @best: Hash[configuration_key, priority]
      # @rbs @candidate_ids: Array[Integer]

      # @rbs (Hash[Symbol, Object?] tables, RepairPolicy policy, Array[RepairInput] tokens,
      #   complete: bool) -> void
      def initialize(tables, policy, tokens, complete:)
        @tables = tables
        @policy = policy
        @tokens = tokens
        @complete = complete
        @configurations = 0
        @heap = RepairPriorityQueue.new
        @best = {}
        reserved = [Parser::EOF_TOKEN, Parser::ERROR_TOKEN]
        token_names = tables.fetch(:token_names) #: Hash[Integer, String]
        @candidate_ids = token_names.keys.reject { |id| reserved.include?(id) }.sort.freeze
      end

      # Compatibility projection used by the semantic runtime path.
      # @rbs (Array[Integer] state_stack) -> (RepairPlan | Object | nil)
      def search(state_stack)
        result = search_result(state_stack)
        return result.plan if result.selected?
        return NEED_INPUT if result.status == :need_input

        nil
      end

      # Preserve the bounded outcome for syntax tooling and diagnostics.
      # @rbs (Array[Integer] state_stack) -> RepairSearchResult
      def search_result(state_stack)
        empty_edits = [] #: Array[RepairEdit]
        push(
          Configuration.new(
            stack: state_stack.dup.freeze,
            input_index: 0,
            shifts: 0,
            cost: 0,
            edits: empty_edits.freeze,
            goal: false
          )
        )
        needs_input = false
        until @heap.empty?
          configuration = pop
          return outcome(:exhausted) if configuration.equal?(LIMIT)
          next unless configuration.is_a?(Configuration)

          result = visit(configuration)
          return outcome(:exhausted) if result.equal?(LIMIT)
          return outcome(:selected, plan: result) if result.is_a?(RepairPlan)

          needs_input = true if result.equal?(NEED_INPUT)
        end
        outcome(needs_input ? :need_input : :not_found)
      end

      private

      # @rbs (Configuration configuration) -> (RepairPlan | Object | nil)
      def visit(configuration)
        @configurations += 1
        return LIMIT if @configurations > @policy.max_configurations
        return plan(configuration.edits) if configuration.goal
        if configuration.input_index >= @tokens.length
          return @complete ? nil : NEED_INPUT
        end

        expand(configuration)
      end

      # @rbs (Configuration configuration) -> (RepairPlan | Object | nil)
      def expand(configuration)
        current = @tokens.fetch(configuration.input_index)
        unchanged = advance(configuration.stack, current.token_id)
        return LIMIT if unchanged.equal?(LIMIT)

        if unchanged.is_a?(RepairAdvance)
          if unchanged.status == :accept && !configuration.edits.empty?
            push(configuration_with(configuration, stack: unchanged.stack, goal: true))
            return
          end

          if unchanged.status == :shift
            shifts = configuration.shifts + 1
            if shifts >= @policy.success_shifts && !configuration.edits.empty?
              push(configuration_with(configuration, stack: unchanged.stack, shifts: shifts, goal: true))
              return
            end

            push(
              configuration_with(
                configuration, stack: unchanged.stack, input_index: configuration.input_index + 1, shifts: shifts
              )
            )
          end
        end
        return unless configuration.cost < @policy.max_cost

        expand_edits(configuration, current)
      end

      # @rbs (Configuration configuration, RepairInput current) -> (RepairPlan | Object | nil)
      def expand_edits(configuration, current)
        push_delete(configuration, current) unless current.eof?
        inserted = expand_candidates(configuration, :insert)
        return inserted if inserted

        unless current.eof?
          replaced = expand_candidates(configuration, :replace)
          return replaced if replaced
        end
        nil
      end

      # @rbs (Configuration configuration, :insert | :replace kind)
      #   -> (RepairPlan | Object | nil)
      def expand_candidates(configuration, kind)
        cost = kind == :insert ? @policy.insert_cost : @policy.replace_cost
        return if configuration.cost + cost > @policy.max_cost

        @candidate_ids.each do |token_id|
          result = expand_candidate(configuration, kind, token_id, cost)
          return LIMIT if result.equal?(LIMIT)
        end
        nil
      end

      # @rbs (Configuration configuration, :insert | :replace kind, Integer token_id, Integer cost) -> Object?
      def expand_candidate(configuration, kind, token_id, cost)
        advanced = advance(configuration.stack, token_id)
        return LIMIT if advanced.equal?(LIMIT)
        return unless advanced

        edits = candidate_edits(configuration, kind, token_id, cost)
        return unless advanced.is_a?(RepairAdvance)

        shifts = kind == :replace ? configuration.shifts + 1 : configuration.shifts
        input_index = kind == :replace ? configuration.input_index + 1 : configuration.input_index
        push(
          configuration_with(
            configuration,
            stack: advanced.stack,
            input_index: input_index,
            shifts: shifts,
            cost: configuration.cost + cost,
            edits: edits,
            goal: advanced.status == :accept || shifts >= @policy.success_shifts
          )
        )
        nil
      end

      # @rbs (Configuration configuration, Symbol kind, Integer token_id, Integer cost) -> Array[RepairEdit]
      def candidate_edits(configuration, kind, token_id, cost)
        edit = RepairEdit.new(
          kind: kind,
          position: configuration.input_index,
          token_id: token_id,
          token_name: token_name(token_id),
          cost: cost
        )
        (configuration.edits + [edit]).freeze
      end

      # @rbs (Configuration configuration, RepairInput current) -> void
      def push_delete(configuration, current)
        cost = configuration.cost + @policy.delete_cost
        return if cost > @policy.max_cost

        edit = RepairEdit.new(
          kind: :delete,
          position: configuration.input_index,
          token_id: current.token_id,
          token_name: current.token_name,
          cost: @policy.delete_cost
        )
        push(
          configuration_with(
            configuration, input_index: configuration.input_index + 1,
                           cost: cost,
                           edits: (configuration.edits + [edit]).freeze
          )
        )
      end

      # @rbs (Array[Integer] stack, Integer token_id) -> (RepairAdvance | Object | nil)
      def advance(stack, token_id)
        states = stack.dup
        seen = {} #: Hash[Array[Integer], bool]
        loop do
          return nil if seen[states]

          seen[states.dup.freeze] = true
          @configurations += 1
          return LIMIT if @configurations > @policy.max_configurations

          action = action_for(states.last, token_id)
          case action.first
          when :shift
            target = action.fetch(1)
            return nil unless target.is_a?(Integer)

            states << target
            return nil if states.length > @policy.max_stack

            return RepairAdvance.new(status: :shift, stack: states.freeze)
          when :reduce
            production_id = action.fetch(1)
            return nil unless production_id.is_a?(Integer)

            return nil unless apply_reduction(states, production_id)
          when :accept then return RepairAdvance.new(status: :accept, stack: states.freeze)
          else return nil
          end
        end
      end

      # @rbs (Array[Integer] states, Integer production_id) -> Array[Integer]?
      def apply_reduction(states, production_id)
        productions = @tables.fetch(:productions) #: Array[Hash[Symbol, Object?]]
        production = productions.fetch(production_id)
        length = production.fetch(:length) #: Integer
        return if length >= states.length

        states.pop(length)
        gotos = @tables.fetch(:gotos) #: Tables::goto_table
        lhs = production.fetch(:lhs) #: Integer
        goto = goto_table_lookup(gotos, states.last, lhs)
        return unless goto.is_a?(Integer)

        states << goto
        states if states.length <= @policy.max_stack
      end

      # @rbs (Integer state, Integer token_id) -> IR::runtime_action
      def action_for(state, token_id)
        actions = @tables.fetch(:actions) #: Tables::action_table
        explicit = action_table_lookup(actions, state, token_id)
        return explicit if explicit

        defaults = @tables.fetch(:default_actions, Parser::EMPTY_ROW) #: Array[IR::runtime_action?]
        defaults[state] || [:error]
      end

      # @rbs (Tables::action_table table, Integer row, Integer column) -> IR::runtime_action?
      def action_table_lookup(table, row, column)
        if table.is_a?(Tables::CompactActions)
          value = table.__send__(:lookup, row, column)
          return value #: IR::runtime_action?
        end

        rows = table #: Array[Hash[Integer, IR::runtime_action]]
        empty_row = Parser::EMPTY_ROW #: Hash[Integer, IR::runtime_action]
        rows.fetch(row, empty_row)[column]
      end

      # @rbs (Tables::goto_table table, Integer row, Integer column) -> Integer?
      def goto_table_lookup(table, row, column)
        if table.is_a?(Tables::Compact)
          value = table.__send__(:lookup, row, column)
          return value #: Integer?
        end

        rows = table #: Array[Hash[Integer, Integer]]
        empty_row = Parser::EMPTY_ROW #: Hash[Integer, Integer]
        rows.fetch(row, empty_row)[column]
      end

      # @rbs (Configuration source, ?stack: Array[Integer], ?input_index: Integer, ?shifts: Integer,
      #   ?cost: Integer, ?edits: Array[RepairEdit], ?goal: bool) -> Configuration
      def configuration_with(source, stack: source.stack, input_index: source.input_index, shifts: source.shifts,
                             cost: source.cost, edits: source.edits, goal: source.goal)
        Configuration.new(
          stack: stack, input_index: input_index, shifts: shifts, cost: cost, edits: edits, goal: goal
        )
      end

      # @rbs (Array[RepairEdit] edits) -> RepairPlan
      def plan(edits)
        RepairPlan.new(edits: edits, configurations: @configurations)
      end

      # @rbs (Symbol status, ?plan: RepairPlan?) -> RepairSearchResult
      def outcome(status, plan: nil)
        RepairSearchResult.new(status: status, plan: plan, configurations: @configurations)
      end

      # @rbs (Integer token_id) -> String
      def token_name(token_id)
        token_names = @tables.fetch(:token_names) #: Hash[Integer, String]
        token_names.fetch(token_id, token_id.to_s)
      end

      # @rbs (Configuration configuration) -> void
      def push(configuration)
        priority = priority_for(configuration)
        key = [configuration.stack, configuration.input_index, configuration.shifts,
               configuration.goal] #: configuration_key
        previous = @best[key]
        comparison = previous <=> priority if previous
        return if comparison && comparison <= 0

        @best[key] = priority
        @heap.push(priority, configuration)
      end

      # @rbs () -> (Configuration | Object)
      def pop
        loop do
          entry = @heap.pop
          return LIMIT unless entry

          priority, configuration = entry
          return LIMIT unless configuration.is_a?(Configuration)

          key = [configuration.stack, configuration.input_index, configuration.shifts,
                 configuration.goal] #: configuration_key
          return configuration if @best[key] == priority
        end
      end

      # @rbs (Configuration configuration) -> priority
      def priority_for(configuration)
        edit_key = configuration.edits.map do |edit|
          rank = { delete: 0, insert: 1, replace: 2 }.fetch(edit.kind)
          [edit.position, rank, edit.token_id] #: [Integer, Integer, Integer]
        end
        goal_rank = configuration.goal ? 0 : 1
        risk = configuration.edits.sum { |edit| semantic_value_risk(edit) }
        [
          configuration.cost, risk, edit_key, goal_rank, -configuration.shifts,
          configuration.input_index, configuration.stack
        ] #: priority
      end

      # Prefer punctuation edits when equal-cost repairs are otherwise
      # ambiguous; inventing or discarding a word-like token is more likely to
      # fabricate or lose an application semantic value.
      # @rbs (RepairEdit edit) -> Integer
      def semantic_value_risk(edit)
        edit.token_name.delete_prefix(":").match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) ? 1 : 0
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
