# frozen_string_literal: true

require_relative "ir/grammar_ir"
require_relative "ir/lexer_ir"
require_relative "ir/migration"
require_relative "ir/automaton_ir"
require_relative "ir/serialize"
require_relative "ir/validator"

module Ibex
  module IR
    # Shared static shapes used across analysis, automaton construction, and code generation.
    # @rbs!
    #   type location = { file: String, line: Integer, column: Integer }
    #   type precedence = { associativity: Symbol, level: Integer }
    #   type named_ref = { name: String, index: Integer }
    #   type byte_span = { start: Integer, end: Integer }
    #   type source_provenance = { file: String?, root: String?, byte_span: byte_span? }
    #   type parser_parameter = { name: String, semantic_type: String? }
    #   type value_printer = { symbol: String, code: String, loc: location }
    #   type recovery_policy = {
    #     sync_tokens: Array[String],
    #     on_error_reduce: Array[Array[String]]
    #   }
    #   type grammar_test = { expectation: :accept | :reject, source: String, loc: location }
    #   type lexer_warning = { type: :redos, rule: Integer, loc: location }
    #   type parameter_expansion = { rule: String, arguments: Array[String] }
    #   type inline_expansion = { rule: String }
    #   type production_expansion = {
    #     parameter: parameter_expansion?,
    #     inline: inline_expansion?,
    #     include_chain: Array[source_provenance]
    #   }
    #   type action_fragment = { kind: :rule | :inline, source: source_provenance? }
    #   type action_composition_step = {
    #     kind: :rule | :inline,
    #     rule: String?,
    #     code: String?,
    #     loc: location,
    #     named_refs: Array[named_ref],
    #     context_length: Integer,
    #     inputs: Array[Integer],
    #     stack_inputs: Array[Integer],
    #     lookahead: Integer?,
    #     result_var: bool,
    #     result_type: String?
    #   }
    #   type action_composition_plan = {
    #     version: Integer,
    #     physical: Integer,
    #     steps: Array[action_composition_step]
    #   }
    #   type action_composition = {
    #     strategy: String,
    #     fragments: Array[action_fragment],
    #     ?plan: action_composition_plan
    #   }
    #   type migration_metadata = { from_schema_version: Integer, unavailable: Array[String] }
    #   type user_code_chunks = Hash[String, Array[UserCodeChunk]]
    #   type grammar_options = { result_var: bool, omit_action_call: bool, ?cst: bool }
    #   type grammar_mode = :racc | :extended
    #   type grammar_warning = {
    #     type: Symbol,
    #     ?symbol: String,
    #     ?production: Integer,
    #     ?original: Integer,
    #     loc: location?
    #   }
    #   type shift_action = { type: :shift, state: Integer }
    #   type reduce_action = { type: :reduce, production: Integer }
    #   type accept_action = { type: :accept }
    #   type error_action = { type: :error }
    #   type parser_action = shift_action | reduce_action | accept_action | error_action
    #   type runtime_action = [:shift, Integer] | [:reduce, Integer] | [:accept] | [:error]
    #   type conflict_resolution = { by: Symbol, chose: Symbol | Integer, ?associativity: Symbol }
    #   type shift_reduce_conflict =
    #     { type: :shift_reduce, symbol: String, shift_to: Integer, reduce: Integer,
    #       resolution: conflict_resolution, ?midrule_origins: Array[location],
    #       ?entries: Array[String], ?composite: bool }
    #   type reduce_reduce_conflict =
    #     { type: :reduce_reduce, symbol: String, reductions: Array[Integer],
    #       resolution: conflict_resolution, ?midrule_origins: Array[location],
    #       ?entries: Array[String], ?composite: bool }
    #   type conflict = shift_reduce_conflict | reduce_reduce_conflict
    #   type conflict_summary = {
    #     sr: Integer,
    #     resolved_sr: Integer,
    #     rr: Integer,
    #     expected_sr: Integer,
    #     expectation_met: bool,
    #     ?expected_rr: Integer,
    #     ?rr_expectation_met: bool
    #   }
    #   type interpretation = Hash[Symbol, untyped]
    #   type counterexample = {
    #     state: Integer,
    #     type: Symbol,
    #     symbol_path: Array[String],
    #     sentence: Array[String],
    #     lookahead_index: Integer,
    #     unifying: bool,
    #     interpretations: Array[interpretation]
    #   }
  end
end
