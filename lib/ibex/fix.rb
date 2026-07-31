# frozen_string_literal: true
# rbs_inline: enabled

require_relative "equiv"
require_relative "error_messages"

module Ibex
  # Bounded conflict-repair candidate generation and safety evaluation.
  # rubocop:disable Metrics/ClassLength -- candidate generation and its three safety gates share one target identity.
  class Fix
    SCHEMA_VERSION = 2 #: Integer
    CATEGORIES = %w[
      precedence_declaration precedence_override algorithm_change
      mechanical_rewrite expectation_declaration recovery_quality
    ].freeze #: Array[String]

    class BudgetExceeded < Ibex::Error
      attr_reader :details #: Hash[Symbol, untyped]

      # @rbs (Hash[Symbol, untyped] details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        super("(fix):1:1: candidate or build budget was exhausted")
      end
    end

    attr_reader :sources #: Hash[String, String]

    # @rbs (String source, file: String, grammar: IR::Grammar, automaton: IR::Automaton, algorithm: Symbol,
    #   mode: Symbol, ?state: Integer?, ?conflict_index: Integer?, ?max_candidates: Integer, ?max_builds: Integer,
    #   ?equiv_max_tokens: Integer, ?equiv_max_configurations: Integer, ?equiv_samples: Integer,
    #   ?verify_max_states: Integer, ?verify_max_items: Integer,
    #   ?messages: ErrorMessages::Document?, ?message_file: String?) -> void
    # rubocop:disable Metrics/ParameterLists
    def initialize(source, file:, grammar:, automaton:, algorithm:, mode:, state: nil, conflict_index: nil,
                   max_candidates: 32, max_builds: 32, equiv_max_tokens: 8,
                   equiv_max_configurations: 50_000, equiv_samples: 100,
                   verify_max_states: 100_000, verify_max_items: 1_000_000,
                   messages: nil, message_file: nil)
      { max_candidates: max_candidates, max_builds: max_builds, equiv_max_tokens: equiv_max_tokens,
        equiv_max_configurations: equiv_max_configurations, equiv_samples: equiv_samples,
        verify_max_states: verify_max_states, verify_max_items: verify_max_items }.each do |name, value|
        raise ArgumentError, "#{name} must be positive" unless value.positive?
      end

      @source = source
      if source.match?(/^# #{Regexp.escape(BisonImport::STRUCTURAL_STATUS_MARKER)}: incomplete$/)
        raise Ibex::Error,
              "(fix):1:1: cannot propose repairs for a structurally incomplete Bison import"
      end
      @file = file
      @grammar = grammar
      @automaton = automaton
      @algorithm = algorithm
      @mode = mode
      @requested_state = state
      @requested_conflict_index = conflict_index
      @max_candidates = max_candidates
      @max_builds = max_builds
      @equiv_max_tokens = equiv_max_tokens
      @equiv_max_configurations = equiv_max_configurations
      @equiv_samples = equiv_samples
      @verify_max_states = verify_max_states
      @verify_max_items = verify_max_items
      @messages = messages
      @message_file = message_file
      @sources = {}
      @builds = 0
    end
    # rubocop:enable Metrics/ParameterLists

    # @rbs () -> Hash[Symbol, untyped]
    def run
      state, index, conflict = select_target
      candidates = candidate_space(conflict)
      if candidates.length > @max_candidates
        details = {
          result: "budget_exhausted", phase: "candidate_enumeration",
          bounds: bounds, enumerated_candidates: candidates.length
        }
        raise BudgetExceeded, details
      end

      proposals = [] #: Array[Hash[Symbol, untyped]]
      rejections = [] #: Array[Hash[Symbol, untyped]]
      incomplete = false
      candidates.each do |candidate|
        outcome = evaluate_candidate(candidate, conflict)
        if outcome.fetch(:status) == "safe"
          proposals << proposal(candidate, outcome, conflict, proposals.length + 1)
        else
          incomplete ||= %w[equivalence_budget_exhausted verification_budget_exhausted]
                         .include?(outcome.fetch(:reason))
          rejections << rejection(candidate, outcome)
        end
      end
      report = report_for(state, index, conflict, candidates, proposals, rejections)
      raise BudgetExceeded, report.merge(result: "budget_exhausted", phase: "candidate_evaluation") if incomplete

      report
    end

    private

    # @rbs () -> [IR::AutomatonState, Integer, IR::conflict]
    def select_target
      states = @requested_state ? [@automaton.states.fetch(@requested_state)] : @automaton.states
      states.each do |state|
        state.conflicts.each_with_index do |conflict, index|
          next if @requested_conflict_index && index != @requested_conflict_index
          next unless active_conflict?(conflict)

          return [state, index, conflict]
        end
      end
      raise Ibex::Error, "(fix):1:1: no unresolved conflict matches the requested target"
    rescue IndexError
      raise Ibex::Error, "(fix):1:1: requested state does not exist"
    end

    # @rbs (IR::conflict conflict) -> Array[Hash[Symbol, untyped]]
    def candidate_space(conflict)
      candidates = precedence_declaration_candidates(conflict)
      override = precedence_override_candidate(conflict)
      candidates << override if override
      candidates.concat(algorithm_candidates)
      rewrite = inline_candidate(conflict)
      candidates << rewrite if rewrite
      candidates << expectation_candidate(conflict)
      recovery = recovery_candidate(conflict)
      candidates << recovery if recovery
      candidates
    end

    # @rbs (IR::conflict conflict) -> Array[Hash[Symbol, untyped]]
    def precedence_declaration_candidates(conflict)
      return [] unless conflict.fetch(:type).to_sym == :shift_reduce

      %w[left right nonassoc %precedence].map do |associativity|
        block = "preclow\n  #{associativity} #{conflict.fetch(:symbol)}\nprechigh\n"
        edited = update_expectation(insert_before_rule(block), conflict)
        candidate(
          "precedence_declaration",
          "declare #{associativity} precedence for #{conflict.fetch(:symbol)}",
          source: edited
        )
      end
    end

    # @rbs (IR::conflict conflict) -> Hash[Symbol, untyped]?
    def precedence_override_candidate(conflict)
      return unless conflict.fetch(:type).to_sym == :shift_reduce

      value = conflict #: IR::shift_reduce_conflict
      production = @grammar.productions.fetch(value.fetch(:reduce))
      return if production.node

      line = production.origin.dig(:loc, :line)
      return unless line

      edited = update_expectation(append_to_line(line, " = #{value.fetch(:symbol)}"), conflict)
      candidate(
        "precedence_override",
        "override production #{production.id} precedence with #{value.fetch(:symbol)}",
        source: edited
      )
    end

    # @rbs () -> Array[Hash[Symbol, untyped]]
    def algorithm_candidates
      %i[ielr lr1].reject { |algorithm| algorithm == @algorithm }.map do |algorithm|
        candidate("algorithm_change", "construct with #{algorithm}", algorithm: algorithm)
      end
    end

    # @rbs (IR::conflict conflict) -> Hash[Symbol, untyped]?
    def inline_candidate(conflict)
      production_id = if conflict.fetch(:type).to_sym == :shift_reduce
                        shift_reduce = conflict #: IR::shift_reduce_conflict
                        shift_reduce.fetch(:reduce)
                      else
                        reduce_reduce = conflict #: IR::reduce_reduce_conflict
                        reduce_reduce.fetch(:reductions).first
                      end
      production = @grammar.productions.fetch(production_id)
      lhs = @grammar.symbol_by_id(production.lhs)&.name
      return unless lhs && !@grammar.starts.include?(lhs)

      pattern = /^(\s*)#{Regexp.escape(lhs)}\s*:/
      return unless @source.match?(pattern)

      edited = update_expectation(@source.sub(pattern, "\\1%inline #{lhs}:"), conflict)
      candidate("mechanical_rewrite", "inline nonterminal #{lhs}", source: edited)
    end

    # @rbs (IR::conflict conflict) -> Hash[Symbol, untyped]
    def expectation_candidate(conflict)
      directive = if conflict.fetch(:type).to_sym == :reduce_reduce
                    "%expect-rr #{@automaton.conflict_summary.fetch(:rr)}\n"
                  else
                    "expect #{@automaton.conflict_summary.fetch(:sr)}\n"
                  end
      candidate(
        "expectation_declaration", "acknowledge the current conflict count",
        source: replace_or_insert_expectation(directive)
      )
    end

    # @rbs (IR::conflict conflict) -> Hash[Symbol, untyped]?
    def recovery_candidate(conflict)
      production_id = if conflict.fetch(:type).to_sym == :shift_reduce
                        shift_reduce = conflict #: IR::shift_reduce_conflict
                        shift_reduce.fetch(:reduce)
                      else
                        reduce_reduce = conflict #: IR::reduce_reduce_conflict
                        reduce_reduce.fetch(:reductions).first
                      end
      production = @grammar.productions.fetch(production_id)
      lhs = @grammar.symbol_by_id(production.lhs)&.name
      return unless lhs

      candidate(
        "recovery_quality", "prefer #{lhs} during error recovery",
        source: insert_before_rule("%on_error_reduce #{lhs}\n")
      )
    end

    # @rbs (String category, String description, ?source: String?, ?algorithm: Symbol?) -> Hash[Symbol, untyped]
    def candidate(category, description, source: nil, algorithm: nil)
      { category: category, description: description, source: source, algorithm: algorithm || @algorithm }
    end

    # @rbs (Hash[Symbol, untyped] candidate, IR::conflict target) -> Hash[Symbol, untyped]
    def evaluate_candidate(candidate, target)
      candidate_automaton = build_candidate(candidate)
      failure = conflict_safety_failure(candidate_automaton, target)
      return failure if failure

      failure = verification_safety_failure(candidate_automaton)
      return failure if failure

      equivalence = Equiv.new(
        @automaton, candidate_automaton,
        sample_count: @equiv_samples, max_tokens: @equiv_max_tokens,
        max_configurations: @equiv_max_configurations,
        rule_map: identity_rule_map(candidate_automaton.grammar)
      ).run
      {
        status: "safe", automaton: candidate_automaton, equivalence: equivalence,
        removed_conflicts: active_conflicts(@automaton).length - active_conflicts(candidate_automaton).length
      }
    rescue Equiv::Difference
      { status: "rejected", reason: "bounded_language_or_tree_difference" }
    rescue Equiv::BudgetExceeded
      { status: "rejected", reason: "equivalence_budget_exhausted" }
    rescue Verify::BudgetExceeded
      { status: "rejected", reason: "verification_budget_exhausted" }
    rescue BudgetExceeded
      raise
    rescue Ibex::Error, ArgumentError => e
      { status: "rejected", reason: "candidate_build_failed", message: e.message }
    end

    # @rbs (IR::Automaton candidate, IR::conflict target) -> Hash[Symbol, String]?
    def conflict_safety_failure(candidate, target)
      fingerprint = conflict_fingerprint(@grammar, target)
      active = active_conflicts(candidate)
      original_active = active_conflicts(@automaton)
      return { status: "rejected", reason: "target_conflict_remains" } if
        active.any? { |_state, conflict| conflict_fingerprint(candidate.grammar, conflict) == fingerprint }
      return { status: "rejected", reason: "conflict_count_did_not_decrease" } unless
        active.length < original_active.length

      { status: "rejected", reason: "other_conflicts_increased" } if
        increased_other_conflict?(candidate, fingerprint)
    end

    # @rbs (IR::Automaton candidate) -> Hash[Symbol, String]?
    def verification_safety_failure(candidate)
      verification = Verify::Verifier.new(
        candidate, max_states: @verify_max_states, max_items: @verify_max_items
      ).verify
      return { status: "rejected", reason: "candidate_failed_verification" } unless verification.valid?
      return { status: "rejected", reason: "conflict_expectation_mismatch" } unless
        candidate.conflict_summary.fetch(:expectation_met)
      return unless candidate.conflict_summary.key?(:rr_expectation_met) &&
                    !candidate.conflict_summary.fetch(:rr_expectation_met)

      { status: "rejected", reason: "conflict_expectation_mismatch" }
    end

    # @rbs (Hash[Symbol, untyped] candidate) -> IR::Automaton
    def build_candidate(candidate)
      raise BudgetExceeded, { result: "budget_exhausted", phase: "builds", bounds: bounds } if @builds >= @max_builds

      @builds += 1
      grammar = if candidate[:source]
                  ast = Frontend::Parser.new(candidate.fetch(:source), file: @file, mode: @mode).parse
                  Normalizer.new(ast, mode: @mode).normalize
                else
                  @grammar
                end
      LALR::Builder.new(grammar, algorithm: candidate.fetch(:algorithm)).build
    end

    # @rbs (Hash[Symbol, untyped] candidate, Hash[Symbol, untyped] outcome, IR::conflict conflict, Integer number) ->
    #   Hash[Symbol, untyped]
    def proposal(candidate, outcome, conflict, number)
      id = format("FX%03d", number)
      source = candidate[:source]
      @sources[id] = source if source
      candidate_automaton = outcome.fetch(:automaton)
      {
        id: id, category: candidate.fetch(:category), description: candidate.fetch(:description),
        algorithm: candidate.fetch(:algorithm), applyable: !source.nil?,
        unified_diff: source ? unified_diff(@source, source) : nil,
        eliminates: [conflict_fingerprint(@grammar, conflict)],
        equivalence: outcome.fetch(:equivalence),
        side_effects: {
          states: {
            before: @automaton.states.length, after: candidate_automaton.states.length,
            delta: candidate_automaton.states.length - @automaton.states.length
          },
          removed_conflicts: outcome.fetch(:removed_conflicts),
          message_catalog: message_catalog_impact(candidate_automaton)
        }
      }
    end

    # @rbs (IR::Automaton candidate) -> Hash[Symbol, untyped]
    def message_catalog_impact(candidate)
      unless @messages
        empty = [] #: Array[String]
        return { status: "not_configured", moved: empty, uncovered: empty, unreachable: empty }
      end

      file = @message_file || "(messages)"
      baseline = ErrorMessages.update(@automaton, existing: @messages)
      changed = ErrorMessages.update(candidate, existing: @messages)
      {
        status: "evaluated", file: file,
        moved: changed.moved - baseline.moved,
        uncovered: changed.uncovered - baseline.uncovered,
        unreachable: changed.unreachable - baseline.unreachable
      }
    end

    # @rbs (Hash[Symbol, untyped] candidate, Hash[Symbol, untyped] outcome) -> Hash[Symbol, untyped]
    def rejection(candidate, outcome)
      {
        category: candidate.fetch(:category), description: candidate.fetch(:description),
        reason: outcome.fetch(:reason), message: outcome[:message]
      }
    end

    # @rbs (IR::AutomatonState state, Integer index, IR::conflict conflict, Array[Hash[Symbol, untyped]] candidates,
    #   Array[Hash[Symbol, untyped]] proposals, Array[Hash[Symbol, untyped]] rejections) -> Hash[Symbol, untyped]
    def report_for(state, index, conflict, candidates, proposals, rejections)
      inventory = CATEGORIES.to_h do |category|
        values = candidates.select { |candidate| candidate.fetch(:category) == category }
        rejected = rejections.count { |entry| entry.fetch(:category) == category }
        [category, { enumerated: values.length, rejected: rejected,
                     safe: proposals.count { |entry| entry.fetch(:category) == category } }]
      end
      {
        ibex_report: "fix", schema_version: SCHEMA_VERSION,
        result: proposals.empty? ? "no_safe_proposal" : "proposals_found",
        target: {
          id: "state-#{state.id}-conflict-#{index}", state: state.id, index: index,
          type: conflict.fetch(:type), symbol: conflict.fetch(:symbol),
          fingerprint: conflict_fingerprint(@grammar, conflict)
        },
        candidate_space: inventory,
        proposals: proposals, rejections: rejections,
        bounds: bounds,
        statement: Equiv::CAVEAT
      }
    end

    # @rbs (IR::Automaton automaton) -> Array[[IR::AutomatonState, IR::conflict]]
    def active_conflicts(automaton)
      automaton.states.flat_map do |state|
        state.conflicts.filter_map { |conflict| [state, conflict] if active_conflict?(conflict) }
      end
    end

    # @rbs (IR::conflict conflict) -> bool
    def active_conflict?(conflict)
      return true if conflict.fetch(:type).to_sym == :reduce_reduce

      conflict.fetch(:resolution).fetch(:by).to_sym == :default_shift
    end

    # @rbs (IR::Automaton candidate, String target_fingerprint) -> bool
    def increased_other_conflict?(candidate, target_fingerprint)
      before = conflict_counts(@automaton)
      after = conflict_counts(candidate)
      after.any? do |fingerprint, count|
        fingerprint != target_fingerprint && count > before.fetch(fingerprint, 0)
      end
    end

    # @rbs (IR::Automaton automaton) -> Hash[String, Integer]
    def conflict_counts(automaton)
      active_conflicts(automaton).each_with_object(Hash.new(0)) do |(_state, conflict), counts|
        counts[conflict_fingerprint(automaton.grammar, conflict)] += 1
      end
    end

    # @rbs (IR::Grammar grammar, IR::conflict conflict) -> String
    def conflict_fingerprint(grammar, conflict)
      if conflict.fetch(:type).to_sym == :shift_reduce
        shift_reduce = conflict #: IR::shift_reduce_conflict
        "shift_reduce:#{shift_reduce.fetch(:symbol)}:" \
          "#{production_shape(grammar, shift_reduce.fetch(:reduce))}"
      else
        reduce_reduce = conflict #: IR::reduce_reduce_conflict
        shapes = reduce_reduce.fetch(:reductions).map { |id| production_shape(grammar, id) }.sort
        "reduce_reduce:#{reduce_reduce.fetch(:symbol)}:#{shapes.join('|')}"
      end
    end

    # @rbs (IR::Grammar grammar, Integer id) -> String
    def production_shape(grammar, id)
      production = grammar.productions.fetch(id)
      lhs = grammar.symbol_by_id(production.lhs)&.name || production.lhs.to_s
      rhs = production.rhs.map { |symbol| grammar.symbol_by_id(symbol)&.name || symbol.to_s }
      "#{lhs}->#{rhs.join(' ')}"
    end

    # @rbs (IR::Grammar candidate_grammar) -> Hash[String, String]
    def identity_rule_map(candidate_grammar)
      left = @grammar.nonterminals.map(&:name)
      right = candidate_grammar.nonterminals.map(&:name)
      (left & right).to_h { |name| [name, name] }
    end

    # @rbs (String insertion) -> String
    def insert_before_rule(insertion)
      insert_before_rule_in(@source, insertion)
    end

    # @rbs (String source, String insertion) -> String
    def insert_before_rule_in(source, insertion)
      match = source.match(/^rule\b/)
      raise Ibex::Error, "(fix):1:1: source has no rule section" unless match

      offset = match.begin(0)
      raise Ibex::Error, "(fix):1:1: rule section has no source offset" unless offset

      source.dup.insert(offset, insertion)
    end

    # @rbs (Integer line_number, String suffix) -> String
    def append_to_line(line_number, suffix)
      lines = @source.lines
      line = lines.fetch(line_number - 1)
      ending = line.end_with?("\n") ? "\n" : ""
      lines[line_number - 1] = "#{line.delete_suffix("\n")}#{suffix}#{ending}"
      lines.join
    rescue IndexError
      raise Ibex::Error, "(fix):1:1: production source line is outside the root file"
    end

    # @rbs (String directive) -> String
    def replace_or_insert_expectation(directive)
      pattern = directive.start_with?("%expect-rr") ? /^%expect-rr\s+\d+\s*$/ : /^expect\s+\d+\s*$/
      return @source.sub(pattern, directive.chomp) if @source.match?(pattern)

      insert_before_rule(directive)
    end

    # @rbs (String source, IR::conflict conflict) -> String
    def update_expectation(source, conflict)
      if conflict.fetch(:type).to_sym == :reduce_reduce
        current = @automaton.conflict_summary.fetch(:rr)
        directive = "%expect-rr #{[current - 1, 0].max}"
        pattern = /^%expect-rr\s+\d+\s*$/
      else
        current = @automaton.conflict_summary.fetch(:sr)
        directive = "expect #{[current - 1, 0].max}"
        pattern = /^expect\s+\d+\s*$/
      end
      return source.sub(pattern, directive) if source.match?(pattern)

      insert_before_rule_in(source, "#{directive}\n")
    end

    # @rbs (String before, String after) -> String
    def unified_diff(before, after)
      before_lines = before.lines
      after_lines = after.lines
      [
        "--- #{@file}", "+++ #{@file}",
        "@@ -1,#{before_lines.length} +1,#{after_lines.length} @@",
        *before_lines.map { |line| "-#{line.delete_suffix("\n")}" },
        *after_lines.map { |line| "+#{line.delete_suffix("\n")}" }
      ].join("\n") << "\n"
    end

    # @rbs () -> Hash[Symbol, Integer]
    def bounds
      {
        max_candidates: @max_candidates, max_builds: @max_builds,
        equiv_samples: @equiv_samples, equiv_max_tokens: @equiv_max_tokens,
        equiv_max_configurations: @equiv_max_configurations,
        verify_max_states: @verify_max_states, verify_max_items: @verify_max_items
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
