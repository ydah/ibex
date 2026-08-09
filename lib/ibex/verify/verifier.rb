# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Verify
    # Checks Automaton IR semantics against an independently derived collection.
    # rubocop:disable Metrics/ClassLength -- V1-V8 share one violation and item-identity model.
    class Verifier
      # @type ivar @automaton: IR::Automaton
      # @type ivar @grammar: IR::Grammar
      # @type ivar @strict: bool
      # @type ivar @max_states: Integer
      # @type ivar @max_items: Integer
      DEFAULT_CHECKS = %w[V1 V3 V4 V6 V7 V8].freeze #: Array[String]
      STRICT_CHECKS = %w[V2 V5].freeze #: Array[String]
      ERROR_ACTION = { type: :error }.freeze #: IR::error_action

      # @rbs (IR::Automaton automaton, ?strict: bool, ?max_states: Integer, ?max_items: Integer) -> void
      def initialize(automaton, strict: false, max_states: 100_000, max_items: 1_000_000)
        @automaton = automaton
        @grammar = automaton.grammar
        @strict = strict
        @max_states = max_states
        @max_items = max_items
        @violations = [] #: Array[Violation]
        @sets = Analysis::Sets.new(grammar) #: Analysis::Sets
      end

      # @rbs () -> Result
      def verify
        @violations = [] #: Array[Violation]
        verify_grammar_digest
        verify_item_collection
        verify_transitions_and_actions
        verify_table_formats
        verify_reachability_and_productivity
        verify_epsilon_termination
        verify_conflict_determinism
        Result.new(
          algorithm: automaton.algorithm, strict: @strict,
          checks: DEFAULT_CHECKS + (@strict ? STRICT_CHECKS : []),
          violations: @violations,
          bounds: { max_states: @max_states, max_items: @max_items }
        )
      end

      private

      # @rbs () -> void
      def verify_grammar_digest
        require "digest"
        actual = "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(grammar))}"
        return if actual == automaton.grammar_digest

        violation("V1", "$.grammar_digest", "digest does not match the embedded Grammar IR")
      end

      # @rbs () -> void
      def verify_item_collection
        case automaton.algorithm
        when "slr" then compare_slr_states(reference.build(:lr0).states.map { |state| visible_state(state) })
        when "lalr1" then compare_expected_states(lalr_states)
        when "lr1" then compare_expected_states(lr1_states)
        when "ielr1" then compare_ielr_states(lalr_states)
        else violation("V1", "$.algorithm", "unsupported algorithm #{automaton.algorithm.inspect}")
        end
      end

      # SLR lookaheads affect completed items only. The builder may retain
      # propagation lookaheads on non-completed items, but they cannot select
      # an ACTION cell and therefore are outside the SLR semantic contract.
      # @rbs (Array[Set[Array[Integer]]] expected_states) -> void
      def compare_slr_states(expected_states)
        expected_by_core = expected_states.group_by { |state| state.to_a.sort }
        matched_cores = [] #: Array[Array[Array[Integer]]]
        automaton.states.each do |state|
          core = verify_slr_state(state, expected_by_core)
          matched_cores << core if core
        end
        return unless @strict

        expected_cores = expected_states.map { |state| state.to_a.sort }
        return if matched_cores.sort == expected_cores.sort

        violation("V2", "$.states", "SLR state collection is incomplete or contains duplicate LR(0) cores")
      end

      # @rbs (IR::AutomatonState state,
      #   Hash[Array[Array[Integer]], Array[Set[Array[Integer]]]] expected_by_core) ->
      #   Array[Array[Integer]]?
      def verify_slr_state(state, expected_by_core)
        actual_core = state.items.map { |item| [item.production, item.dot] }.uniq.sort
        unless expected_by_core.key?(actual_core)
          violation("V1", state_path(state), "item core is not in the independently derived LR(0) collection")
          return
        end

        state.items.each { |item| verify_slr_lookaheads(state, item) }
        actual_core
      end

      # @rbs (IR::AutomatonState state, IR::AutomatonItem item) -> void
      def verify_slr_lookaheads(state, item)
        return unless item.dot == rhs_for(item.production).length

        expected = item.production.negative? ? [eof_id] : follow_ids(item.production)
        return if item.lookaheads == expected.sort

        violation("V3", state_path(state), "completed item #{item.production} has invalid SLR lookaheads")
      end

      # @rbs () -> Array[Set[Array[Integer]]]
      def lr1_states
        canonical_lr1_states.map { |state| visible_state(state) }
      end

      # @rbs () -> Array[Set[Array[Integer]]]
      def lalr_states
        groups = canonical_lr1_states.group_by { |state| core_key(state) }
        groups.values.map do |states|
          merged = states.each_with_object(Set[]) do |state, result|
            state.each { |item| result << item }
          end #: Set[Array[Integer]]
          visible_state(merged)
        end
      end

      # @rbs () -> Array[Set[Array[Integer]]]
      def canonical_lr1_states
        reference.build(:lr1).states
      end

      # @rbs (Array[Set[Array[Integer]]] expected_states) -> void
      def compare_expected_states(expected_states)
        expected_by_core = expected_states.group_by { |state| core_key(state) }
        matched = [] #: Array[Set[Array[Integer]]]
        automaton.states.each do |state|
          actual = expanded_items(state)
          candidates = expected_by_core.fetch(core_key(actual), [])
          expected = candidates.find { |candidate| actual.subset?(candidate) }
          unless expected
            violation("V1", state_path(state), "item set is not a subset of an independently derived state")
            next
          end

          matched << expected
          expected_state = expected #: Set[Array[Integer]]
          missing = expected_state - actual
          violation("V2", state_path(state), "item set is missing #{missing.length} derived items") if
            @strict && !missing.empty?
        end
        return unless @strict

        expected_counts = multiset(expected_states)
        actual_counts = multiset(matched)
        return if expected_counts == actual_counts

        violation("V2", "$.states", "state collection is incomplete or contains duplicate derived states")
      end

      # @rbs (Array[Set[Array[Integer]]] expected_states) -> void
      def compare_ielr_states(expected_states)
        expected_by_core = expected_states.to_h { |state| [core_key(state), state] }
        actual_by_core = {} #: Hash[Array[Array[Integer]], Set[Array[Integer]]]
        automaton.states.each do |state|
          actual = expanded_items(state)
          core = core_key(actual)
          expected = expected_by_core[core]
          unless expected && actual.subset?(expected)
            violation("V1", state_path(state), "IELR state contains an item outside its canonical-core union")
            next
          end
          merged = actual_by_core[core] ||= Set[] #: Set[Array[Integer]]
          actual.each { |item| merged << item }
        end
        return unless @strict

        empty = Set[] #: Set[Array[Integer]]
        expected_by_core.each do |core, expected|
          next if actual_by_core.fetch(core, empty) == expected

          violation("V2", "$.states", "IELR partitions do not cover canonical lookaheads for core #{core.inspect}")
        end
      end

      # @rbs () -> void
      def verify_transitions_and_actions
        automaton.states.each do |state|
          verify_transition_items(state)
          verify_state_actions(state)
        end
      end

      # @rbs (IR::AutomatonState state) -> void
      def verify_transition_items(state)
        state.transitions.each do |symbol_id, target_id|
          symbol = grammar.symbol_by_id(symbol_id)
          target = automaton.states[target_id]
          unless symbol && target
            violation("V1", state_path(state), "transition references a missing symbol or state")
            next
          end

          expected = shifted_items(state, symbol_id)
          actual = expanded_items(target)
          missing = expected.reject { |item| actual.include?(item) }
          unless missing.empty?
            violation("V1", state_path(state),
                      "transition on #{symbol.name} loses #{missing.length} shifted items")
          end
          if symbol.nonterminal? && state.gotos[symbol_id] != target_id
            violation("V1", state_path(state), "nonterminal transition #{symbol.name} has no matching goto")
          end
        end
      end

      # @rbs (IR::AutomatonState state) -> void
      def verify_state_actions(state)
        candidates = action_candidates(state)
        conflict_tokens = state.conflicts.filter_map do |conflict|
          grammar.symbol(conflict.fetch(:symbol))&.id
        end
        if state.default_action && state.default_action[:type] != :reduce
          violation("V4", state_path(state), "default action must be a reduction")
        end

        grammar.terminals.each do |terminal|
          expected = candidates.fetch(terminal.id, []).uniq
          actual = effective_action(state, terminal.id)
          verify_terminal_action(state, terminal, expected, actual, conflict_tokens)
        end
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, Array[IR::parser_action] expected,
      #   IR::parser_action actual, Array[Integer] conflict_tokens) -> void
      def verify_terminal_action(state, terminal, expected, actual, conflict_tokens)
        if expected.empty?
          verify_error_cell(state, terminal, actual)
        elsif expected.one?
          verify_single_action(state, terminal, expected.fetch(0), actual)
        else
          verify_conflicted_action(state, terminal, expected, actual, conflict_tokens)
        end
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, IR::parser_action actual) -> void
      def verify_error_cell(state, terminal, actual)
        return if actual[:type] == :error

        violation("V4", state_path(state), "#{terminal.name} replaces an error cell with #{actual.inspect}")
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, IR::parser_action expected,
      #   IR::parser_action actual) -> void
      def verify_single_action(state, terminal, expected, actual)
        return if actual == expected

        violation("V1", state_path(state),
                  "#{terminal.name} selects #{actual.inspect}, expected #{expected.inspect}")
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, Array[IR::parser_action] expected,
      #   IR::parser_action actual, Array[Integer] conflict_tokens) -> void
      def verify_conflicted_action(state, terminal, expected, actual, conflict_tokens)
        unless expected.include?(actual) || actual[:type] == :error
          violation("V8", state_path(state), "#{terminal.name} selects an action outside its candidates")
        end
        return if conflict_tokens.include?(terminal.id)

        violation("V8", state_path(state), "#{terminal.name} has multiple actions without a declared resolver")
      end

      # @rbs () -> void
      def verify_table_formats
        plain = Tables.build(automaton, format: :plain)
        compact = Tables.build(automaton, format: :compact)
        automaton.states.each do |state|
          unless action_row(plain.actions, state.id) == action_row(compact.actions, state.id)
            violation(@strict ? "V5" : "V4", state_path(state), "plain/compact ACTION rows differ")
          end
          unless goto_row(plain.gotos, state.id) == goto_row(compact.gotos, state.id)
            violation(@strict ? "V5" : "V4", state_path(state), "plain/compact GOTO rows differ")
          end
          next if plain.default_actions.fetch(state.id) == compact.default_actions.fetch(state.id)

          violation(@strict ? "V5" : "V4", state_path(state), "plain/compact default actions differ")
        end
      rescue StandardError => e
        violation(@strict ? "V5" : "V4", "$.states", "table transformation failed: #{e.message}")
      end

      # @rbs (Tables::action_table table, Integer row) -> Hash[Integer, IR::runtime_action]
      def action_row(table, row)
        table.is_a?(Array) ? table.fetch(row) : table.row(row)
      end

      # @rbs (Tables::goto_table table, Integer row) -> Hash[Integer, Integer]
      def goto_row(table, row)
        table.is_a?(Array) ? table.fetch(row) : table.row(row)
      end

      # @rbs () -> void
      def verify_reachability_and_productivity
        reachable = reachable_states
        automaton.states.each do |state|
          unless reachable.include?(state.id)
            violation("V6", state_path(state),
                      "state is unreachable from every entry")
          end
        end

        productive = productive_nonterminals
        grammar.nonterminals.each do |symbol|
          unless productive.include?(symbol.id)
            violation("V6", "$.grammar.symbols[#{symbol.id}]",
                      "nonterminal #{symbol.name} derives no terminal sentence")
          end
        end
      end

      # @rbs () -> void
      def verify_epsilon_termination
        grammar.terminals.each do |terminal|
          edges = {} #: Hash[Integer, Integer]
          automaton.states.each do |state|
            action = effective_action(state, terminal.id)
            next unless action[:type] == :reduce

            production_id = action.fetch(:production) #: Integer
            production = grammar.productions[production_id]
            next unless production&.rhs&.empty?

            target = state.gotos[production.lhs]
            edges[state.id] = target if target
          end
          next unless directed_cycle?(edges)

          violation("V7", "$.states", "epsilon reductions can cycle without consuming #{terminal.name}")
        end
      end

      # @rbs () -> void
      def verify_conflict_determinism
        automaton.states.each do |state|
          grouped = state.conflicts.group_by { |conflict| conflict.fetch(:symbol) }
          grouped.each do |symbol, conflicts|
            violation("V8", state_path(state), "#{symbol} has more than one declared resolver") if conflicts.length > 1
            resolution = conflicts.first&.fetch(:resolution, nil)
            unless resolution&.key?(:by) && resolution.key?(:chose)
              violation("V8", state_path(state), "#{symbol} has an incomplete resolver")
              next
            end

            verify_conflict_resolution(state, conflicts.first)
          end
        end
      end

      # @rbs (IR::AutomatonState state, IR::conflict conflict) -> void
      def verify_conflict_resolution(state, conflict)
        terminal = grammar.symbol(conflict.fetch(:symbol))
        unless terminal&.terminal?
          violation("V8", state_path(state), "resolver references a missing terminal")
          return
        end

        candidates = action_candidates(state).fetch(terminal.id, []).uniq
        expected = resolved_conflict_action(conflict)
        unless conflict_candidates(conflict).all? { |candidate| candidates.include?(candidate) }
          violation("V8", state_path(state), "#{terminal.name} resolver names actions outside the cell")
        end
        return if expected && effective_action(state, terminal.id) == expected

        violation("V8", state_path(state), "#{terminal.name} resolver choice does not match the ACTION cell")
      end

      # @rbs (IR::conflict conflict) -> Array[IR::parser_action]
      def conflict_candidates(conflict)
        if conflict.fetch(:type).to_sym == :shift_reduce
          shift_reduce = conflict #: IR::shift_reduce_conflict
          [
            { type: :shift, state: shift_reduce.fetch(:shift_to) },
            { type: :reduce, production: shift_reduce.fetch(:reduce) }
          ]
        else
          reduce_reduce = conflict #: IR::reduce_reduce_conflict
          reduce_reduce.fetch(:reductions).map { |production| { type: :reduce, production: production } }
        end
      end

      # @rbs (IR::conflict conflict) -> IR::parser_action?
      def resolved_conflict_action(conflict)
        chosen = conflict.fetch(:resolution).fetch(:chose)
        return { type: :reduce, production: chosen } if chosen.is_a?(Integer) #: IR::reduce_action

        shift_reduce = conflict #: IR::shift_reduce_conflict
        case chosen.to_sym
        when :shift then { type: :shift, state: shift_reduce.fetch(:shift_to) }
        when :reduce then { type: :reduce, production: shift_reduce.fetch(:reduce) }
        when :error then ERROR_ACTION
        end
      end

      # @rbs (IR::AutomatonState state) -> Hash[Integer, Array[IR::parser_action]]
      def action_candidates(state)
        candidates = Hash.new { |hash, key| hash[key] = [] } #: Hash[Integer, Array[IR::parser_action]]
        state.transitions.each do |symbol_id, target|
          symbol = grammar.symbol_by_id(symbol_id)
          candidates[symbol_id] << { type: :shift, state: target } if symbol&.terminal?
        end
        state.items.each do |item|
          next unless item.dot == rhs_for(item.production).length

          item.lookaheads.each do |lookahead|
            action = if item.production.negative?
                       { type: :accept } #: IR::accept_action
                     else
                       { type: :reduce, production: item.production } #: IR::reduce_action
                     end
            candidates[lookahead] << action
          end
        end
        candidates
      end

      # @rbs (IR::AutomatonState state, Integer symbol_id) -> Array[Array[Integer]]
      def shifted_items(state, symbol_id)
        state.items.filter_map do |item|
          expected_symbol = rhs_for(item.production)[item.dot]
          if item.production.negative? && item.dot.zero?
            next unless start_symbol_ids.include?(symbol_id)
          else
            next unless expected_symbol == symbol_id
          end

          item.lookaheads.map { |lookahead| [item.production, item.dot + 1, lookahead] }
        end.flatten(1)
      end

      # @rbs (IR::AutomatonState state, Integer terminal_id) -> IR::parser_action
      def effective_action(state, terminal_id)
        state.actions.fetch(terminal_id, state.default_action || ERROR_ACTION)
      end

      # @rbs () -> Set[Integer]
      def reachable_states
        found = Set[] #: Set[Integer]
        queue = automaton.entry_states.values.dup
        until queue.empty?
          id = queue.shift
          next if found.include?(id)

          found << id
          state = automaton.states[id]
          next unless state

          queue.concat(state.transitions.values)
          queue.concat(state.gotos.values)
          state.actions.each_value do |action|
            next unless action[:type] == :shift

            shift = action #: IR::shift_action
            queue << shift.fetch(:state)
          end
        end
        found
      end

      # @rbs () -> Set[Integer]
      def productive_nonterminals
        productive = Set[] #: Set[Integer]
        pending = grammar.productions.dup
        loop do
          changed = false
          pending.delete_if do |production|
            ready = production.rhs.all? do |id|
              symbol = grammar.symbol_by_id(id)
              symbol&.terminal? || productive.include?(id)
            end
            productive << production.lhs if ready
            changed ||= ready
            ready
          end
          break unless changed
        end
        productive
      end

      # @rbs (Hash[Integer, Integer] edges) -> bool
      def directed_cycle?(edges)
        edges.each_key do |start|
          seen = Set[] #: Set[Integer]
          cursor = start
          while cursor && edges.key?(cursor)
            return true if seen.include?(cursor)

            seen << cursor
            cursor = edges[cursor]
          end
        end
        false
      end

      # @rbs (IR::AutomatonState state) -> Set[Array[Integer]]
      def expanded_items(state)
        state.items.each_with_object(Set[]) do |item, result|
          item.lookaheads.each { |lookahead| result << [item.production, item.dot, lookahead] }
        end #: Set[Array[Integer]]
      end

      # Automaton IR intentionally exposes every augmented production as -1,
      # even when construction internally assigned one per start symbol.
      # @rbs (Set[Array[Integer]] state) -> Set[Array[Integer]]
      def visible_state(state)
        state.each_with_object(Set[]) do |item, result|
          production = item.fetch(0)
          dot = item.fetch(1)
          lookahead = item[2]
          result << [production.negative? ? -1 : production, dot, lookahead].compact
        end #: Set[Array[Integer]]
      end

      # @rbs (Set[Array[Integer]] state) -> Array[Array[Integer]]
      def core_key(state)
        state.map { |item| [item.fetch(0), item.fetch(1)] }.uniq.sort
      end

      # @rbs (Array[Set[Array[Integer]]] states) -> Hash[Array[Array[Integer]], Integer]
      def multiset(states)
        states.each_with_object(Hash.new(0)) { |state, counts| counts[state.to_a.sort] += 1 }
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def follow_ids(production_id)
        production = grammar.productions.fetch(production_id)
        sets = @sets #: Analysis::Sets
        names = sets.follow(production.lhs)
        names.map { |name| grammar.symbol(name)&.id }.compact
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return [start_symbol(production_id).id] if production_id.negative?

        production = grammar.productions[production_id]
        production&.rhs || []
      end

      # @rbs (Integer production_id) -> IR::GrammarSymbol
      def start_symbol(production_id)
        name = grammar.starts.fetch(-production_id - 1)
        grammar.symbol(name) || raise(Ibex::Error, "(verify):1:1: missing start symbol #{name}")
      end

      # @rbs () -> Integer
      def eof_id
        grammar.symbol("$eof")&.id || raise(Ibex::Error, "(verify):1:1: grammar has no $eof terminal")
      end

      # @rbs () -> Array[Integer]
      def start_symbol_ids
        @start_symbol_ids ||= grammar.starts.map do |name|
          grammar.symbol(name)&.id || raise(Ibex::Error, "(verify):1:1: missing start symbol #{name}")
        end
      end

      # @rbs () -> ReferenceCollection
      def reference
        @reference ||= ReferenceCollection.new(grammar, max_states: @max_states, max_items: @max_items)
      end

      # @rbs (String id, String location, String message) -> void
      def violation(id, location, message)
        violations = @violations #: Array[Violation]
        @violations = violations + [Violation.new(id: id, location: location, message: message).freeze]
      end

      # @rbs () -> IR::Automaton
      def automaton
        @automaton
      end

      # @rbs () -> IR::Grammar
      def grammar
        @grammar
      end

      # @rbs (IR::AutomatonState state) -> String
      def state_path(state) = "$.states[#{state.id}]"
    end
    # rubocop:enable Metrics/ClassLength
  end
end
