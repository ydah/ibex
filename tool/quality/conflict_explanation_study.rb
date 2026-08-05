# frozen_string_literal: true

require "digest"
require "ibex"
require "json"
require "json_schemer"

module Ibex
  module Quality
    # Captures the closed H004 machine corpus without assigning human usefulness labels.
    # rubocop:disable Metrics/ClassLength -- capture and fail-closed validation share one evidence contract.
    class ConflictExplanationStudy
      ROOT = File.expand_path("../..", __dir__)
      FIXTURE_ROOT = File.join(ROOT, "test/fixtures/conflict_explanations")
      SEARCH_BOUNDS = { max_tokens: 16, max_configurations: 100_000 }.freeze
      REPAIR_BOUNDS = {
        max_candidates: 32,
        max_builds: 32,
        equiv_max_tokens: 12,
        equiv_max_configurations: 50_000,
        equiv_samples: 10,
        verify_max_states: 100_000,
        verify_max_items: 1_000_000
      }.freeze
      CASES = [
        {
          id: "H004-EXPR", path: "expression.y", shape: "ambiguous_expression",
          cause: "missing operator associativity",
          repair_goal: "choose and declare the intended PLUS associativity"
        },
        {
          id: "H004-ELSE", path: "dangling_else.y", shape: "dangling_optional_clause",
          cause: "ELSE can attach to either unmatched IF",
          repair_goal: "make the intended ELSE attachment explicit"
        },
        {
          id: "H004-RR", path: "reduce_reduce.y", shape: "reduce_reduce_choice",
          cause: "the same WORD can reduce through left or right",
          repair_goal: "remove or semantically distinguish one reduction"
        },
        {
          id: "H004-MERGE", path: "lalr_merge.y", shape: "lr1_not_lalr_merge",
          cause: "LALR merges LR(1) contexts whose reductions require disjoint lookaheads",
          repair_goal: "use a compatible precise construction and update the expected RR count"
        }
      ].freeze

      # @rbs (root: String) -> void
      def initialize(root: ROOT)
        @root = File.expand_path(root)
        @fixture_root = File.join(@root, "test/fixtures/conflict_explanations")
      end

      # @rbs () -> Hash[String, untyped]
      def document
        cases = CASES.map { |entry| capture_case(entry) }
        conflicts = cases.flat_map { |entry| entry.fetch("conflicts") }
        {
          "ibex_conflict_explanation_study" => "h004",
          "schema_version" => 1,
          "capture" => {
            "algorithm" => "lalr",
            "mode" => "extended",
            "search_bounds" => stringify(SEARCH_BOUNDS),
            "repair_bounds" => stringify(REPAIR_BOUNDS),
            "executes_grammar_actions" => false
          },
          "coverage" => {
            "case_count" => cases.length,
            "conflict_count" => conflicts.length,
            "shapes" => cases.map { |entry| entry.fetch("shape") }.sort,
            "conflict_types" => conflicts.map { |entry| entry.dig("explanation", "type") }.uniq.sort,
            "witness_kinds" => conflicts.map { |entry| entry.dig("explanation", "witness", "kind") }.uniq.sort
          },
          "cases" => cases,
          "subjective_review" => {
            "status" => "external_pending",
            "required_tasks" => %w[identify_cause choose_edit],
            "registry_path" => "docs/conflict-explanation-review-status-v1.json"
          }
        }
      end

      # @rbs () -> String
      def render = "#{JSON.pretty_generate(document)}\n"

      # @rbs (?evidence_path: String, ?schema_path: String) -> Hash[String, untyped]
      def verify!(evidence_path: File.join(@fixture_root, "study-v1.json"),
                  schema_path: File.join(@root, "schema/conflict-explanation-study-v1.schema.json"),
                  review_path: File.join(@root, "docs/conflict-explanation-review-status-v1.json"),
                  review_schema_path: File.join(@root, "schema/conflict-explanation-review-v1.schema.json"))
        source = File.binread(evidence_path)
        committed = JSON.parse(source)
        schema = JSON.parse(File.binread(schema_path))
        errors = JSONSchemer.schema(schema).validate(committed).to_a
        raise "H004 evidence violates its schema: #{JSON.generate(errors)}" unless errors.empty?
        raise "H004 machine capture drift; run tool/conflict_explanation_study.rb --write" unless source == render

        validate_semantics!(committed)
        validate_review_registry!(source, review_path, review_schema_path)
        committed
      end

      private

      # @rbs (Hash[Symbol, String] entry) -> Hash[String, untyped]
      def capture_case(entry)
        relative_path = "test/fixtures/conflict_explanations/#{entry.fetch(:path)}"
        absolute_path = File.join(@root, relative_path)
        source = File.binread(absolute_path)
        grammar, automaton = build(source, relative_path)
        {
          "id" => entry.fetch(:id),
          "shape" => entry.fetch(:shape),
          "grammar" => {
            "path" => relative_path,
            "sha256" => Digest::SHA256.hexdigest(source),
            "bytes" => source.bytesize
          },
          "maintainer_hypothesis" => {
            "cause" => entry.fetch(:cause),
            "repair_goal" => entry.fetch(:repair_goal)
          },
          "automaton" => automaton_record(automaton),
          "conflicts" => captured_conflicts(entry, source, relative_path, grammar, automaton)
        }
      end

      # @rbs (Hash[Symbol, String] entry, String source, String path, IR::Grammar grammar,
      #   IR::Automaton automaton) -> Array[Hash[String, untyped]]
      def captured_conflicts(entry, source, path, grammar, automaton)
        explanations = Codegen::Explain.new(automaton, **SEARCH_BOUNDS).to_h.fetch(:conflicts)
        selections = conflict_selections(automaton)
        raise "H004 explanation selection drift for #{entry.fetch(:id)}" unless selections.length == explanations.length

        selections.zip(explanations).map do |(state, conflict_index), rendered|
          {
            "explanation" => stringify(rendered),
            "state_items" => state.items.map { |item| state_item_record(item, grammar) },
            "repair" => repair(source, path, grammar, automaton, state.id, conflict_index)
          }
        end
      end

      # @rbs (IR::Automaton automaton) -> Hash[String, untyped]
      def automaton_record(automaton)
        {
          "algorithm" => automaton.algorithm,
          "state_count" => automaton.states.length,
          "digest" => Digest::SHA256.hexdigest(IR::Serialize.dump(automaton)),
          "conflict_summary" => stringify(automaton.conflict_summary)
        }
      end

      # @rbs (IR::AutomatonItem item, IR::Grammar grammar) -> Hash[String, untyped]
      def state_item_record(item, grammar)
        production = grammar.productions.fetch(item.production)
        lhs = grammar.symbol_by_id(production.lhs)&.name || raise("H004 item lhs is unavailable")
        rhs = production.rhs.map do |symbol_id|
          grammar.symbol_by_id(symbol_id)&.name || raise("H004 item rhs symbol is unavailable")
        end
        stringify(item.to_h(grammar)).merge("lhs" => lhs, "rhs" => rhs)
      end

      # @rbs (String source, String path) -> [IR::Grammar, IR::Automaton]
      def build(source, path)
        ast = Frontend::Parser.new(source, file: path, mode: :extended).parse
        grammar = Normalizer.new(ast, mode: :extended).normalize
        [grammar, LALR::Builder.new(grammar, algorithm: :lalr).build]
      end

      # @rbs (IR::Automaton automaton) -> Array[[IR::AutomatonState, Integer]]
      def conflict_selections(automaton)
        automaton.states.flat_map do |state|
          state.conflicts.each_index.map { |index| [state, index] }
        end
      end

      # @rbs (String source, String path, IR::Grammar grammar, IR::Automaton automaton,
      #   Integer state, Integer conflict_index) -> Hash[String, untyped]
      def repair(source, path, grammar, automaton, state, conflict_index)
        report = Fix.new(
          source, file: path, grammar: grammar, automaton: automaton,
                  algorithm: :lalr, mode: :extended, state: state, conflict_index: conflict_index,
                  **REPAIR_BOUNDS
        ).run
        {
          "result" => report.fetch(:result),
          "bounds" => stringify(report.fetch(:bounds)),
          "proposals" => report.fetch(:proposals).map { |proposal| proposal_record(proposal) },
          "rejections" => report.fetch(:rejections).map { |rejection| rejection_record(rejection) },
          "advice" => report.fetch(:advice).map { |advice| advice_record(advice) }
        }
      rescue Fix::BudgetExceeded => e
        { "result" => "budget_exhausted", "details" => stringify(e.details) }
      end

      # @rbs (Hash[Symbol, untyped] proposal) -> Hash[String, untyped]
      def proposal_record(proposal)
        equivalence = proposal.fetch(:equivalence)
        side_effects = proposal.fetch(:side_effects)
        stringify(
          proposal.slice(:id, :category, :description, :applyable, :unified_diff).merge(
            verification: {
              equivalence_result: equivalence.fetch(:result),
              tree_result: equivalence.dig(:tree, :result),
              checked: equivalence.fetch(:checked),
              bounds: equivalence.fetch(:bounds),
              removed_conflicts: side_effects.fetch(:removed_conflicts),
              states: side_effects.fetch(:states)
            }
          )
        )
      end

      # @rbs (Hash[Symbol, untyped] rejection) -> Hash[String, untyped]
      def rejection_record(rejection)
        stringify(rejection.slice(:category, :description, :reason, :message))
      end

      # @rbs (Hash[Symbol, untyped] advice) -> Hash[String, untyped]
      def advice_record(advice)
        stringify(advice.slice(:category, :description, :statement, :source_change, :unified_diff))
      end

      # @rbs (untyped value) -> untyped
      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |item| stringify(item) }
        when Symbol then value.to_s
        else value
        end
      end

      # @rbs (Hash[String, untyped] committed) -> void
      def validate_semantics!(committed)
        cases = committed.fetch("cases")
        expected_ids = CASES.map { |entry| entry.fetch(:id) }
        raise "H004 case inventory drift" unless cases.map { |entry| entry.fetch("id") } == expected_ids

        validate_subjective_review!(committed.fetch("subjective_review"))
        validate_coverage!(committed.fetch("coverage"), cases)
        cases.each { |entry| validate_case!(entry) }
      end

      # @rbs (Hash[String, untyped] review) -> void
      def validate_subjective_review!(review)
        expected = {
          "status" => "external_pending",
          "required_tasks" => %w[identify_cause choose_edit],
          "registry_path" => "docs/conflict-explanation-review-status-v1.json"
        }
        return if review == expected

        raise "H004 subjective review boundary drift"
      end

      # @rbs (String evidence_source, String review_path, String schema_path) -> void
      def validate_review_registry!(evidence_source, review_path, schema_path)
        review = JSON.parse(File.binread(review_path))
        schema = JSON.parse(File.binread(schema_path))
        errors = JSONSchemer.schema(schema).validate(review).to_a
        raise "H004 review registry violates its schema: #{JSON.generate(errors)}" unless errors.empty?
        raise "H004 review registry evidence digest drift" unless
          review.fetch("study_sha256") == Digest::SHA256.hexdigest(evidence_source)

        records = review.fetch("records")
        validate_review_records!(review, records)
      end

      # @rbs (Hash[String, untyped] review, Array[Hash[String, untyped]] records) -> void
      def validate_review_records!(review, records)
        validate_reviewer_identities!(records)
        validate_review_case_ids!(records)
        return if review.fetch("status") == "HOLD"
        return if records.length >= 2

        raise "H004 review PASS requires at least two independent records"
      end

      # @rbs (Array[Hash[String, untyped]] records) -> void
      def validate_reviewer_identities!(records)
        reviewers = records.map { |record| record.fetch("reviewer").strip.downcase }
        raise "H004 reviewer identity must not be blank" if reviewers.any?(&:empty?)
        return if reviewers.uniq.length == reviewers.length

        raise "H004 reviewer identities must be unique"
      end

      # @rbs (Array[Hash[String, untyped]] records) -> void
      def validate_review_case_ids!(records)
        expected_ids = CASES.map { |entry| entry.fetch(:id) }.sort
        records.each do |record|
          ids = record.fetch("case_reviews").map { |entry| entry.fetch("case_id") }.sort
          raise "H004 review case inventory drift" unless ids == expected_ids
        end
      end

      # @rbs (Hash[String, untyped] coverage, Array[Hash[String, untyped]] cases) -> void
      def validate_coverage!(coverage, cases)
        conflicts = cases.flat_map { |entry| entry.fetch("conflicts") }
        raise "H004 case count drift" unless coverage.fetch("case_count") == cases.length
        raise "H004 conflict count drift" unless coverage.fetch("conflict_count") == conflicts.length
        raise "H004 conflict type coverage is incomplete" unless
          coverage.fetch("conflict_types") == %w[reduce_reduce shift_reduce]
        return if coverage.fetch("witness_kinds") == %w[nonunifying_witness unifying_counterexample]

        raise "H004 witness coverage is incomplete"
      end

      # @rbs (Hash[String, untyped] entry) -> void
      def validate_case!(entry)
        grammar = entry.fetch("grammar")
        validate_grammar_identity!(grammar)
        entry.fetch("conflicts").each { |conflict| validate_conflict!(entry, conflict) }
      end

      # @rbs (Hash[String, untyped] grammar) -> void
      def validate_grammar_identity!(grammar)
        path = File.join(@root, grammar.fetch("path"))
        source = File.binread(path)
        raise "H004 grammar byte count drift: #{grammar.fetch('path')}" unless source.bytesize == grammar.fetch("bytes")
        return if Digest::SHA256.hexdigest(source) == grammar.fetch("sha256")

        raise "H004 grammar digest drift: #{grammar.fetch('path')}"
      end

      # @rbs (Hash[String, untyped] entry, Hash[String, untyped] conflict) -> void
      def validate_conflict!(entry, conflict)
        explanation = conflict.fetch("explanation")
        raise "H004 state/item explanation is empty" if conflict.fetch("state_items").empty?
        raise "H004 explanation state is outside its automaton" unless
          explanation.fetch("state") < entry.dig("automaton", "state_count")

        validate_witness_search!(explanation.fetch("witness"))

        repair = conflict.fetch("repair")
        return if repair.fetch("result") == "budget_exhausted"

        proposals = repair.fetch("proposals")
        expected = proposals.empty? ? "no_safe_proposal" : "proposals_found"
        raise "H004 repair result/proposal mismatch" unless repair.fetch("result") == expected

        proposals.each { |proposal| validate_proposal!(proposal) }
      end

      # @rbs (Hash[String, untyped] witness) -> void
      def validate_witness_search!(witness)
        search = witness.fetch("search")
        raise "H004 explanation search bounds drift" unless search.fetch("bounds") == stringify(SEARCH_BOUNDS)
        if search.fetch("exhausted") || search.fetch("status") == "exhausted" || witness.fetch("kind") == "inconclusive"
          raise "H004 explanation search exhausted; recapture with sufficient fixed bounds"
        end

        expected_status = witness.fetch("kind") == "unifying_counterexample" ? "found" : "not_found"
        return if search.fetch("status") == expected_status

        raise "H004 explanation witness/search outcome mismatch"
      end

      # @rbs (Hash[String, untyped] proposal) -> void
      def validate_proposal!(proposal)
        verification = proposal.fetch("verification")
        raise "H004 proposal did not remove its target conflict" unless
          verification.fetch("removed_conflicts").positive?
        return if verification.fetch("equivalence_result") == "no_difference_within_bounds" &&
                  verification.fetch("tree_result") == "no_difference_within_bounds"

        raise "H004 proposal is not bounded-equivalent"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
