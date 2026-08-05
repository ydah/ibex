# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # Structural and referential validation for a versioned Automaton IR JSON object.
      # rubocop:disable Metrics/ClassLength -- inline type contracts accompany one cohesive document validator.
      class AutomatonDocument < Base
        ROOT_REQUIRED = %w[
          ibex_ir schema_version algorithm grammar_digest grammar states conflict_summary
        ].freeze #: Array[String]
        V2_ROOT_OPTIONAL = %w[entry_states].freeze #: Array[String]
        V3_ROOT_REQUIRED = %w[entry_construction].freeze #: Array[String]
        STATE_REQUIRED = %w[id items transitions actions gotos default_action conflicts].freeze #: Array[String]
        ACTION_TYPES = %w[shift reduce accept error].freeze #: Array[String]
        RESOLUTION_KINDS = %w[definition_order default_shift precedence associativity].freeze #: Array[String]

        # @rbs @data: Hash[String, untyped]
        # @rbs @states_by_id: Hash[Integer, Hash[String, untyped]]
        # @rbs @grammar: GrammarDocument
        # @rbs @version: Integer

        # @rbs (Hash[String, untyped] data, ?version: Integer) -> void
        def initialize(data, version: data.fetch("schema_version"))
          super()
          @data = data
          @version = version
          @states_by_id = {} #: Hash[Integer, Hash[String, untyped]]
        end

        # @rbs () -> self
        def validate
          required = ROOT_REQUIRED + (@version >= 3 ? V3_ROOT_REQUIRED : [])
          record(@data, "$", required, @version >= 2 ? V2_ROOT_OPTIONAL : [])
          literal(@data["ibex_ir"], "$.ibex_ir", "automaton")
          literal(@data["schema_version"], "$.schema_version", @version)
          enum(@data["algorithm"], "$.algorithm", %w[slr lalr1 ielr1 lr1])
          validate_digest
          grammar = object(@data["grammar"], "$.grammar")
          literal(grammar["schema_version"], "$.grammar.schema_version", @version)
          @grammar = GrammarDocument.new(grammar, path: "$.grammar", version: @version).validate
          validate_construction_contract(grammar) if @version >= 3
          validate_state_records
          validate_entry_states
          validate_state_contents
          validate_conflict_summary
          self
        end

        private

        # @rbs () -> void
        def validate_entry_states
          value = @data["entry_states"]
          if value.nil?
            invalid("$.entry_states", "is required for multiple start symbols") if @data.dig("grammar", "starts")
            return
          end

          entries = object(value, "$.entry_states")
          expected = @data.dig("grammar", "starts") || [@data.dig("grammar", "start")]
          invalid("$.entry_states", "keys must equal grammar starts in order") unless entries.keys == expected
          entries.each do |name, state|
            nonnegative_integer(state, "$.entry_states.#{name}")
            invalid("$.entry_states.#{name}", "references missing state #{state}") unless @states_by_id[state]
          end
        end

        # @rbs (Hash[String, untyped] grammar) -> void
        def validate_construction_contract(grammar)
          entry_construction = enum(
            @data["entry_construction"], "$.entry_construction", %w[shared isolated unknown]
          )
          contract = grammar.fetch("parser_contract")
          algorithm = contract.fetch("algorithm")
          expected_algorithm = { "lalr" => "lalr1", "ielr" => "ielr1" }.fetch(
            algorithm["value"], algorithm["value"]
          )
          if algorithm["explicit"] && @data["algorithm"] != expected_algorithm
            invalid("$.algorithm", "must match the embedded parser contract")
          end

          entries = contract.fetch("entries")
          if entries["explicit"] && entry_construction != entries["value"]
            invalid("$.entry_construction", "must match the embedded parser contract")
          end
          return unless entry_construction == "unknown"

          unavailable = grammar.dig("migration", "unavailable") || []
          return if unavailable.include?("effective_parser_entries") && !entries["explicit"]

          invalid("$.entry_construction", "may be unknown only for migrated unavailable history")
        end

        # @rbs () -> void
        def validate_digest
          digest = string(@data["grammar_digest"], "$.grammar_digest")
          invalid("$.grammar_digest", "must be a sha256 digest") unless digest.match?(/\Asha256:[0-9a-f]{64}\z/)
        end

        # @rbs () -> void
        def validate_state_records
          states = array(@data["states"], "$.states")
          invalid("$.states", "must contain at least one state") if states.empty?
          states.each_with_index do |value, index|
            path = "$.states[#{index}]"
            state = record(value, path, STATE_REQUIRED)
            id = nonnegative_integer(state["id"], "#{path}.id")
            invalid("#{path}.id", "must equal its array index #{index}") unless id == index
            @states_by_id[id] = state
          end
        end

        # @rbs () -> void
        def validate_state_contents
          @states_by_id.each do |id, state|
            path = "$.states[#{id}]"
            validate_items(state["items"], "#{path}.items")
            validate_transitions(state["transitions"], "#{path}.transitions")
            validate_actions(state["actions"], "#{path}.actions")
            validate_gotos(state["gotos"], "#{path}.gotos")
            validate_parser_action(state["default_action"], "#{path}.default_action", nullable: true)
            validate_conflicts(state["conflicts"], "#{path}.conflicts")
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_items(value, path)
          array(value, path).each_with_index do |item, index|
            item_path = "#{path}[#{index}]"
            item = record(item, item_path, %w[production dot lookaheads])
            production = integer(item["production"], "#{item_path}.production")
            validate_item_production(production, item["dot"], item_path)
            validate_lookaheads(item["lookaheads"], "#{item_path}.lookaheads")
          end
        end

        # @rbs (Integer production_id, untyped dot_value, String path) -> void
        def validate_item_production(production_id, dot_value, path)
          dot = nonnegative_integer(dot_value, "#{path}.dot")
          if production_id == -1
            invalid("#{path}.dot", "must not exceed 1 for the augmented production") if dot > 1
            return
          end
          production = @grammar.productions_by_id[production_id]
          invalid("#{path}.production", "references missing production id #{production_id}") unless production
          invalid("#{path}.dot", "exceeds production #{production_id} length") if dot > production["rhs"].length
        end

        # @rbs (untyped value, String path) -> void
        def validate_lookaheads(value, path)
          array(value, path).each_with_index do |name, index|
            name = string(name, "#{path}[#{index}]")
            symbol = @grammar.symbols_by_name[name]
            invalid("#{path}[#{index}]", "references missing symbol #{name.inspect}") unless symbol
            invalid("#{path}[#{index}]", "must reference a terminal") unless symbol["kind"] == "terminal"
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_transitions(value, path)
          symbol_map(value, path) do |target, target_path, _symbol|
            validate_state_reference(target, target_path)
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_actions(value, path)
          symbol_map(value, path, kind: "terminal") do |action, action_path, _symbol|
            validate_parser_action(action, action_path)
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_gotos(value, path)
          symbol_map(value, path, kind: "nonterminal") do |target, target_path, _symbol|
            validate_state_reference(target, target_path)
          end
        end

        # @rbs (untyped value, String path, ?kind: String?) { (untyped, String, Hash[String, untyped]) -> void } -> void
        def symbol_map(value, path, kind: nil, &block)
          object(value, path).each do |name, item|
            item_path = child_path(path, name)
            symbol = @grammar.symbols_by_name[name]
            invalid(item_path, "references missing symbol #{name.inspect}") unless symbol
            invalid(item_path, "must reference a #{kind}") if kind && symbol["kind"] != kind
            block.call(item, item_path, symbol)
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_state_reference(value, path)
          id = nonnegative_integer(value, path)
          invalid(path, "references missing state id #{id}") unless @states_by_id.key?(id)
        end

        # @rbs (untyped value, String path, ?nullable: bool) -> void
        def validate_parser_action(value, path, nullable: false)
          return if nullable && value.nil?

          action = object(value, path)
          type = enum(field(action, "type", path), "#{path}.type", ACTION_TYPES)
          required = case type
                     when "shift" then %w[type state]
                     when "reduce" then %w[type production]
                     else %w[type]
                     end
          record(action, path, required)
          validate_state_reference(action["state"], "#{path}.state") if type == "shift"
          validate_production_reference(action["production"], "#{path}.production") if type == "reduce"
        end

        # @rbs (untyped value, String path) -> void
        def validate_production_reference(value, path)
          id = nonnegative_integer(value, path)
          invalid(path, "references missing production id #{id}") unless @grammar.productions_by_id.key?(id)
        end

        # @rbs (untyped value, String path) -> void
        def validate_conflicts(value, path)
          array(value, path).each_with_index do |conflict, index|
            conflict_path = "#{path}[#{index}]"
            conflict = object(conflict, conflict_path)
            type = enum(field(conflict, "type", conflict_path), "#{conflict_path}.type",
                        %w[shift_reduce reduce_reduce])
            if type == "shift_reduce"
              validate_shift_reduce(conflict, conflict_path)
            else
              validate_reduce_reduce(conflict, conflict_path)
            end
          end
        end

        # @rbs (Hash[String, untyped] conflict, String path) -> void
        def validate_shift_reduce(conflict, path)
          record(conflict, path, %w[type symbol shift_to reduce resolution], %w[midrule_origins entries composite])
          validate_conflict_symbol(conflict["symbol"], "#{path}.symbol")
          validate_state_reference(conflict["shift_to"], "#{path}.shift_to")
          validate_production_reference(conflict["reduce"], "#{path}.reduce")
          validate_resolution(conflict["resolution"], "#{path}.resolution")
          validate_midrule_origins(conflict["midrule_origins"], "#{path}.midrule_origins") if
            conflict.key?("midrule_origins")
          validate_conflict_entries(conflict, path)
        end

        # @rbs (Hash[String, untyped] conflict, String path) -> void
        def validate_reduce_reduce(conflict, path)
          record(conflict, path, %w[type symbol reductions resolution], %w[midrule_origins entries composite])
          validate_conflict_symbol(conflict["symbol"], "#{path}.symbol")
          reductions = array(conflict["reductions"], "#{path}.reductions")
          invalid("#{path}.reductions", "must contain at least two productions") if reductions.length < 2
          reductions.each_with_index do |id, index|
            validate_production_reference(id, "#{path}.reductions[#{index}]")
          end
          if reductions.uniq.length != reductions.length
            invalid("#{path}.reductions", "must contain unique production ids")
          end
          validate_resolution(conflict["resolution"], "#{path}.resolution", reductions: reductions)
          validate_midrule_origins(conflict["midrule_origins"], "#{path}.midrule_origins") if
            conflict.key?("midrule_origins")
          validate_conflict_entries(conflict, path)
        end

        # @rbs (Hash[String, untyped] conflict, String path) -> void
        def validate_conflict_entries(conflict, path)
          if conflict.key?("entries")
            starts = @data.dig("grammar", "starts") || [@data.dig("grammar", "start")]
            entries = array(conflict["entries"], "#{path}.entries")
            invalid("#{path}.entries", "must not be empty") if entries.empty?
            entries.each_with_index do |name, index|
              name = nonempty_string(name, "#{path}.entries[#{index}]")
              invalid("#{path}.entries[#{index}]", "is not a grammar start symbol") unless starts.include?(name)
            end
            invalid("#{path}.entries", "must be unique") unless entries.uniq.length == entries.length
          end
          boolean(conflict["composite"], "#{path}.composite") if conflict.key?("composite")
        end

        # @rbs (untyped value, String path) -> void
        def validate_midrule_origins(value, path)
          origins = array(value, path)
          invalid(path, "must not be empty") if origins.empty?
          origins.each_with_index { |origin, index| location(origin, "#{path}[#{index}]") }
        end

        # @rbs (untyped value, String path) -> void
        def validate_conflict_symbol(value, path)
          name = string(value, path)
          symbol = @grammar.symbols_by_name[name]
          invalid(path, "references missing symbol #{name.inspect}") unless symbol
          invalid(path, "must reference a terminal") unless symbol["kind"] == "terminal"
        end

        # @rbs (untyped value, String path, ?reductions: Array[Integer]?) -> void
        def validate_resolution(value, path, reductions: nil)
          resolution = record(value, path, %w[by chose], %w[associativity])
          enum(resolution["by"], "#{path}.by", RESOLUTION_KINDS)
          if reductions
            chosen = resolution["chose"]
            validate_production_reference(chosen, "#{path}.chose")
            invalid("#{path}.chose", "must be one of the reductions") unless reductions.include?(chosen)
          else
            enum(resolution["chose"], "#{path}.chose", %w[shift reduce error])
          end
          return unless resolution.key?("associativity")

          enum(resolution["associativity"], "#{path}.associativity", %w[left right nonassoc])
        end

        # @rbs () -> void
        def validate_conflict_summary
          path = "$.conflict_summary"
          summary = record(
            @data["conflict_summary"], path, %w[sr resolved_sr rr expected_sr expectation_met],
            %w[expected_rr rr_expectation_met]
          )
          %w[sr resolved_sr rr expected_sr].each do |key|
            nonnegative_integer(summary[key], "#{path}.#{key}")
          end
          boolean(summary["expectation_met"], "#{path}.expectation_met")
          if summary.key?("expected_rr") || summary.key?("rr_expectation_met")
            nonnegative_integer(summary["expected_rr"], "#{path}.expected_rr")
            boolean(summary["rr_expectation_met"], "#{path}.rr_expectation_met")
          end
          validate_conflict_counts(summary, path)
          validate_expectation(summary, path)
        end

        # @rbs (Hash[String, untyped] summary, String path) -> void
        def validate_conflict_counts(summary, path)
          conflicts = @states_by_id.values.flat_map { |state| state["conflicts"] }
          shift_reduce = conflicts.select { |conflict| conflict["type"] == "shift_reduce" }
          counts = {
            "sr" => shift_reduce.count { |conflict| conflict.dig("resolution", "by") == "default_shift" },
            "resolved_sr" => shift_reduce.count { |conflict| conflict.dig("resolution", "by") != "default_shift" },
            "rr" => conflicts.count { |conflict| conflict["type"] == "reduce_reduce" }
          }
          counts.each do |key, actual|
            next if summary[key] == actual

            label = key == "rr" ? "reduce/reduce" : "shift/reduce"
            invalid("#{path}.#{key}", "must equal the #{actual} recorded #{label} conflicts")
          end
        end

        # @rbs (Hash[String, untyped] summary, String path) -> void
        def validate_expectation(summary, path)
          grammar_expect = @data.fetch("grammar").fetch("expect")
          unless summary["expected_sr"] == grammar_expect
            invalid("#{path}.expected_sr", "must equal embedded grammar expect #{grammar_expect}")
          end
          expected_met = summary["sr"] == summary["expected_sr"]
          unless summary["expectation_met"] == expected_met
            invalid("#{path}.expectation_met", "must be #{expected_met} for the recorded shift/reduce count")
          end

          grammar_expect_rr = @data.fetch("grammar")["expect_rr"]
          return if grammar_expect_rr.nil?

          unless summary["expected_rr"] == grammar_expect_rr
            invalid("#{path}.expected_rr", "must equal embedded grammar expect_rr #{grammar_expect_rr}")
          end
          rr_expected_met = summary["rr"] == summary["expected_rr"]
          return if summary["rr_expectation_met"] == rr_expected_met

          invalid("#{path}.rr_expectation_met",
                  "must be #{rr_expected_met} for the recorded reduce/reduce count")
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
