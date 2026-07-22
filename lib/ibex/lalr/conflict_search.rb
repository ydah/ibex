# frozen_string_literal: true

module Ibex
  module LALR
    # Searches the parser state space for one input accepted through both sides of a conflict.
    class ConflictSearch
      include ConflictSearchLimits

      DEFAULT_MAX_TOKENS = ConflictSearchLimits::DEFAULT_MAX_TOKENS
      DEFAULT_MAX_CONFIGURATIONS = ConflictSearchLimits::DEFAULT_MAX_CONFIGURATIONS

      Configuration = Struct.new(:states, :nodes, keyword_init: true)

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

      def call
        return unless @lookahead

        queue = [[configuration([0], Array.new(0)), Array.new(0)]] #: Array[untyped]
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

      def conflict_configurations(current)
        advance(current, @lookahead, stop_at: @state.id, branch_conflicts: true)
          .filter_map { |status, candidate| candidate if status == :conflict }
      end

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

      def unify_from(current, prefix)
        return unless within_token_budget?(prefix, [])

        conflict_actions.combination(2) do |left_action, right_action|
          left_results = advance(current, @lookahead, forced_action: left_action, branch_conflicts: true)
          right_results = advance(current, @lookahead, forced_action: right_action, branch_conflicts: true)
          left_results.product(right_results).each do |left, right|
            result = search_common_suffix(left, right, prefix, left_action, right_action)
            return result if result
          end
        end
        nil
      end

      def search_common_suffix(left, right, prefix, left_action, right_action)
        return accepted_result(prefix, [], left, right, left_action, right_action) if accepted_pair?(left, right)
        return unless shifted_pair?(left, right)

        queue = [[left.last, right.last, Array.new(0)]] #: Array[untyped]
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

      def accept_with_eof(left_config, right_config)
        left = advance(left_config, 0, branch_conflicts: true).select { |entry| entry.first == :accepted }
        right = advance(right_config, 0, branch_conflicts: true).select { |entry| entry.first == :accepted }
        left.product(right).first
      end

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

      def shifted_results(current, token_id)
        advance(current, token_id, branch_conflicts: true)
          .filter_map { |status, candidate| candidate if status == :shifted }
      end

      def accepted_result(prefix, suffix, left, right, left_action, right_action)
        return unless within_token_budget?(prefix, suffix)

        sentence = prefix.dup
        sentence << @lookahead unless @lookahead.zero?
        sentence.concat(suffix)
        { sentence_ids: sentence, lookahead_index: prefix.length,
          interpretations: [interpretation(left_action, left.last), interpretation(right_action, right.last)] }
      end

      def interpretation(action, current)
        details = { kind: action[:type], tree: current.nodes.last }
        details[:state] = action[:state] if action[:type] == :shift
        details[:production] = action[:production] if action[:type] == :reduce
        details
      end

      def accepted_pair?(left, right)
        left.first == :accepted && right.first == :accepted
      end

      def shifted_pair?(left, right)
        left.first == :shifted && right.first == :shifted
      end

      def conflict_actions
        case @conflict[:type]
        when :shift_reduce
          [{ type: :shift, state: @conflict[:shift_to] },
           { type: :reduce, production: @conflict[:reduce] }]
        when :reduce_reduce
          @conflict[:reductions].map { |production| { type: :reduce, production: production } }
        else
          []
        end
      end

      def advance(initial, token_id, forced_action: nil, stop_at: nil, branch_conflicts: false)
        queue = [[initial, forced_action]]
        visited = {} #: Hash[untyped, untyped]
        results = [] #: Array[untyped]
        until queue.empty? || exhausted?
          current, forced = queue.shift
          if stop_at == current.states.last
            results << [:conflict, current]
            next
          end

          key = [current.states, !forced.nil?]
          next if visited[key]

          visited[key] = true
          count_configuration
          actions_for(current.states.last, token_id, forced, branch_conflicts).each do |action|
            apply_action(results, queue, current, action, token_id)
          end
        end
        results
      end

      def actions_for(state_id, token_id, forced, branch_conflicts)
        return [forced] if forced

        state = @automaton.states.fetch(state_id)
        actions = [state.actions[token_id] || state.default_action].compact
        return actions unless branch_conflicts

        token_name = @grammar.symbol_by_id(token_id).name
        state.conflicts.each do |conflict|
          next unless conflict[:symbol] == token_name

          actions.concat(actions_from(conflict))
        end
        actions.uniq
      end

      def actions_from(conflict)
        case conflict[:type]
        when :shift_reduce
          [{ type: :shift, state: conflict[:shift_to] }, { type: :reduce, production: conflict[:reduce] }]
        when :reduce_reduce
          conflict[:reductions].map { |production| { type: :reduce, production: production } }
        else
          []
        end
      end

      def apply_action(results, queue, current, action, token_id)
        case action[:type]
        when :shift
          results << [:shifted, shift(current, action[:state], token_id)]
        when :reduce
          reduced = reduce(current, action[:production])
          queue << [reduced, nil] if reduced
        when :accept
          results << [:accepted, current]
        end
      end

      def shift(current, state_id, token_id)
        symbol = @grammar.symbol_by_id(token_id).name
        configuration(current.states + [state_id], current.nodes + [{ symbol: symbol, token: symbol }])
      end

      def reduce(current, production_id)
        production = @grammar.productions.fetch(production_id)
        length = production.rhs.length
        return if length >= current.states.length

        states = current.states.take(current.states.length - length)
        children = current.nodes.last(length)
        nodes = current.nodes.take(current.nodes.length - length)
        target = @automaton.states.fetch(states.last).gotos[production.lhs]
        return unless target

        symbol = @grammar.symbol_by_id(production.lhs).name
        configuration(states + [target], nodes + [{ symbol: symbol, production: production_id, children: children }])
      end

      def configuration(states, nodes) = Configuration.new(states: states.freeze, nodes: nodes.freeze)

      def pair_key(left, right)
        [left.states, right.states]
      end

      def count_configuration = (@explored += 1)

      def exhausted? = @explored >= @max_configurations
    end
  end
end
