# frozen_string_literal: true

module Ibex
  module LALR
    # Searches the parser state space for one input accepted through both sides of a conflict.
    # rubocop:disable Metrics/ClassLength -- inline type contracts make the focused search implementation longer.
    class ConflictSearch
      include ConflictSearchLimits

      DEFAULT_MAX_TOKENS = ConflictSearchLimits::DEFAULT_MAX_TOKENS #: Integer
      DEFAULT_MAX_CONFIGURATIONS = ConflictSearchLimits::DEFAULT_MAX_CONFIGURATIONS #: Integer

      Configuration = Struct.new(
        :states, #: Array[Integer]
        :nodes, #: Array[derivation_node]
        keyword_init: true
      )

      # @rbs @automaton: IR::Automaton
      # @rbs @grammar: IR::Grammar
      # @rbs @state: IR::AutomatonState
      # @rbs @conflict: IR::conflict
      # @rbs @lookahead: Integer?
      # @rbs @max_tokens: Integer
      # @rbs @max_configurations: Integer
      # @rbs @explored: Integer
      # @rbs @input_tokens: Array[Integer]

      # @rbs (IR::Automaton automaton, IR::AutomatonState state, IR::conflict conflict,
      #   ?max_tokens: Integer, ?max_configurations: Integer) -> void
      def initialize(automaton, state, conflict, max_tokens: DEFAULT_MAX_TOKENS,
                     max_configurations: DEFAULT_MAX_CONFIGURATIONS)
        ConflictSearchLimits.validate!(max_tokens: max_tokens, max_configurations: max_configurations)
        @automaton = automaton
        @grammar = automaton.grammar
        @state = state
        @conflict = conflict
        @lookahead = @grammar.symbol(conflict[:symbol])&.id
        @max_tokens = max_tokens
        @max_configurations = max_configurations
        @explored = 0
        @input_tokens = @grammar.terminals.reject(&:reserved).sort_by(&:name).map(&:id)
      end

      # @rbs () -> search_result?
      def call
        return unless @lookahead

        queue = [[configuration([0], Array.new(0)), Array.new(0)]] #: Array[[Configuration, Array[Integer]]]
        visited = { [0] => true }
        until queue.empty? || exhausted?
          current, prefix = queue.shift
          conflict_configurations(current).each do |candidate|
            result = unify_from(candidate, prefix)
            return result if result
          end
          enqueue_prefixes(queue, visited, current, prefix)
        end
        nil
      end

      private

      # @rbs (Configuration current) -> Array[Configuration]
      def conflict_configurations(current)
        advance(current, required_lookahead, stop_at: @state.id, branch_conflicts: true)
          .filter_map { |status, candidate| candidate if status == :conflict }
      end

      # @rbs (Array[[Configuration, Array[Integer]]] queue, Hash[Array[Integer], bool] visited,
      #   Configuration current, Array[Integer] prefix) -> void
      def enqueue_prefixes(queue, visited, current, prefix)
        return unless room_for_token?(prefix, [])

        @input_tokens.each do |token_id|
          advance(current, token_id, branch_conflicts: true).each do |status, candidate|
            next unless status == :shifted
            next if visited[candidate.states]

            visited[candidate.states] = true
            queue << [candidate, prefix + [token_id]]
          end
        end
      end

      # @rbs (Configuration current, Array[Integer] prefix) -> search_result?
      def unify_from(current, prefix)
        return unless within_token_budget?(prefix, [])

        conflict_actions.combination(2) do |left_action, right_action|
          next unless left_action && right_action

          left_results = advance(current, required_lookahead, forced_action: left_action, branch_conflicts: true)
          right_results = advance(current, required_lookahead, forced_action: right_action, branch_conflicts: true)
          left_results.product(right_results).each do |left, right|
            result = search_common_suffix(left, right, prefix, left_action, right_action)
            return result if result
          end
        end
        nil
      end

      # @rbs (search_entry left, search_entry right, Array[Integer] prefix, IR::parser_action left_action,
      #   IR::parser_action right_action) -> search_result?
      def search_common_suffix(left, right, prefix, left_action, right_action)
        return accepted_result(prefix, [], left, right, left_action, right_action) if accepted_pair?(left, right)
        return unless shifted_pair?(left, right)

        queue = [[left.last, right.last, Array.new(0)]] #: Array[[Configuration, Configuration, Array[Integer]]]
        visited = { pair_key(left.last, right.last) => true }
        until queue.empty? || exhausted?
          left_config, right_config, suffix = queue.shift
          accepted = accept_with_eof(left_config, right_config)
          return accepted_result(prefix, suffix, accepted[0], accepted[1], left_action, right_action) if accepted
          next unless room_for_token?(prefix, suffix)

          enqueue_suffixes(queue, visited, left_config, right_config, suffix)
        end
        nil
      end

      # @rbs (Configuration left_config, Configuration right_config) -> [search_entry, search_entry]?
      def accept_with_eof(left_config, right_config)
        left = advance(left_config, 0, branch_conflicts: true).select { |entry| entry.first == :accepted }
        right = advance(right_config, 0, branch_conflicts: true).select { |entry| entry.first == :accepted }
        left.product(right).first
      end

      # @rbs (Array[[Configuration, Configuration, Array[Integer]]] queue,
      #   Hash[[Array[Integer], Array[Integer]], bool] visited, Configuration left_config,
      #   Configuration right_config, Array[Integer] suffix) -> void
      def enqueue_suffixes(queue, visited, left_config, right_config, suffix)
        @input_tokens.each do |token_id|
          left = shifted_results(left_config, token_id)
          right = shifted_results(right_config, token_id)
          left.product(right).each do |left_candidate, right_candidate|
            key = pair_key(left_candidate, right_candidate)
            next if visited[key]

            visited[key] = true
            queue << [left_candidate, right_candidate, suffix + [token_id]]
          end
        end
      end

      # @rbs (Configuration current, Integer token_id) -> Array[Configuration]
      def shifted_results(current, token_id)
        advance(current, token_id, branch_conflicts: true)
          .filter_map { |status, candidate| candidate if status == :shifted }
      end

      # @rbs (Array[Integer] prefix, Array[Integer] suffix, search_entry left, search_entry right,
      #   IR::parser_action left_action, IR::parser_action right_action) -> search_result?
      def accepted_result(prefix, suffix, left, right, left_action, right_action)
        return unless within_token_budget?(prefix, suffix)

        sentence = prefix.dup
        lookahead = required_lookahead
        sentence << lookahead unless lookahead.zero?
        sentence.concat(suffix)
        { sentence_ids: sentence, lookahead_index: prefix.length,
          interpretations: [interpretation(left_action, left.last), interpretation(right_action, right.last)] }
      end

      # @rbs (IR::parser_action action, Configuration current) -> IR::interpretation
      def interpretation(action, current)
        details = { kind: action[:type], tree: current.nodes.last } #: IR::interpretation
        if action[:type] == :shift
          shift_action = action #: IR::shift_action
          details[:state] = shift_action[:state]
        elsif action[:type] == :reduce
          reduce_action = action #: IR::reduce_action
          details[:production] = reduce_action[:production]
        end
        details
      end

      # @rbs (search_entry left, search_entry right) -> bool
      def accepted_pair?(left, right)
        left.first == :accepted && right.first == :accepted
      end

      # @rbs (search_entry left, search_entry right) -> bool
      def shifted_pair?(left, right)
        left.first == :shifted && right.first == :shifted
      end

      # @rbs () -> Array[IR::parser_action]
      def conflict_actions
        case @conflict[:type]
        when :shift_reduce
          conflict = @conflict #: IR::shift_reduce_conflict
          shift = { type: :shift, state: conflict[:shift_to] } #: IR::shift_action
          reduce = { type: :reduce, production: conflict[:reduce] } #: IR::reduce_action
          [shift, reduce]
        when :reduce_reduce
          conflict = @conflict #: IR::reduce_reduce_conflict
          conflict[:reductions].map do |production|
            { type: :reduce, production: production } #: IR::reduce_action
          end
        else
          []
        end
      end

      # @rbs (Configuration initial, Integer token_id, ?forced_action: IR::parser_action?, ?stop_at: Integer?,
      #   ?branch_conflicts: bool) -> Array[search_entry]
      def advance(initial, token_id, forced_action: nil, stop_at: nil, branch_conflicts: false)
        queue = [[initial, forced_action]] #: Array[[Configuration, IR::parser_action?]]
        visited = {} #: Hash[[Array[Integer], bool], bool]
        results = [] #: Array[search_entry]
        until queue.empty? || exhausted?
          current, forced = queue.shift
          if stop_at == current.states.last
            results << [:conflict, current]
            next
          end

          key = [current.states, !forced.nil?] #: [Array[Integer], bool]
          next if visited[key]

          visited[key] = true
          count_configuration
          actions_for(current.states.last, token_id, forced, branch_conflicts).each do |action|
            apply_action(results, queue, current, action, token_id)
          end
        end
        results
      end

      # @rbs (Integer state_id, Integer token_id, IR::parser_action? forced, bool branch_conflicts) ->
      #   Array[IR::parser_action]
      def actions_for(state_id, token_id, forced, branch_conflicts)
        return [forced] if forced

        state = @automaton.states.fetch(state_id)
        actions = [state.actions[token_id] || state.default_action].compact
        return actions unless branch_conflicts

        token_name = symbol_name(token_id)
        state.conflicts.each do |conflict|
          next unless conflict[:symbol] == token_name

          actions.concat(actions_from(conflict))
        end
        actions.uniq
      end

      # @rbs (IR::conflict conflict) -> Array[IR::parser_action]
      def actions_from(conflict)
        case conflict[:type]
        when :shift_reduce
          shift_reduce = conflict #: IR::shift_reduce_conflict
          shift = { type: :shift, state: shift_reduce[:shift_to] } #: IR::shift_action
          reduce = { type: :reduce, production: shift_reduce[:reduce] } #: IR::reduce_action
          [shift, reduce]
        when :reduce_reduce
          reduce_reduce = conflict #: IR::reduce_reduce_conflict
          reduce_reduce[:reductions].map do |production|
            { type: :reduce, production: production } #: IR::reduce_action
          end
        else
          []
        end
      end

      # @rbs (Array[search_entry] results, Array[[Configuration, IR::parser_action?]] queue,
      #   Configuration current, IR::parser_action action, Integer token_id) -> void
      def apply_action(results, queue, current, action, token_id)
        case action[:type]
        when :shift
          shift_action = action #: IR::shift_action
          results << [:shifted, shift(current, shift_action[:state], token_id)]
        when :reduce
          reduce_action = action #: IR::reduce_action
          reduced = reduce(current, reduce_action[:production])
          queue << [reduced, nil] if reduced
        when :accept
          results << [:accepted, current]
        end
      end

      # @rbs (Configuration current, Integer state_id, Integer token_id) -> Configuration
      def shift(current, state_id, token_id)
        symbol = symbol_name(token_id)
        configuration(current.states + [state_id], current.nodes + [{ symbol: symbol, token: symbol }])
      end

      # @rbs (Configuration current, Integer production_id) -> Configuration?
      def reduce(current, production_id)
        production = @grammar.productions.fetch(production_id)
        length = production.rhs.length
        return if length >= current.states.length

        states = current.states.take(current.states.length - length)
        children = current.nodes.last(length)
        nodes = current.nodes.take(current.nodes.length - length)
        target = @automaton.states.fetch(states.last).gotos[production.lhs]
        return unless target

        symbol = symbol_name(production.lhs)
        configuration(states + [target], nodes + [{ symbol: symbol, production: production_id, children: children }])
      end

      # @rbs (Array[Integer] states, Array[derivation_node] nodes) -> Configuration
      def configuration(states, nodes) = Configuration.new(states: states.freeze, nodes: nodes.freeze)

      # @rbs () -> Integer
      def required_lookahead
        @lookahead || raise(Ibex::Error, "missing conflict lookahead")
      end

      # @rbs (Integer id) -> String
      def symbol_name(id)
        symbol = @grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
        symbol.name
      end

      # @rbs (Configuration left, Configuration right) -> [Array[Integer], Array[Integer]]
      def pair_key(left, right)
        [left.states, right.states]
      end

      # @rbs () -> Integer
      def count_configuration = (@explored += 1)

      # @rbs () -> bool
      def exhausted? = @explored >= @max_configurations
    end
    # rubocop:enable Metrics/ClassLength
  end
end
