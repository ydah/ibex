# frozen_string_literal: true

require_relative "ir/grammar_ir"
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
    #   type user_code_chunks = Hash[String, Array[UserCodeChunk]]
    #   type grammar_options = { result_var: bool, omit_action_call: bool }
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
    #     { type: :shift_reduce, symbol: String, shift_to: Integer, reduce: Integer, resolution: conflict_resolution }
    #   type reduce_reduce_conflict =
    #     { type: :reduce_reduce, symbol: String, reductions: Array[Integer], resolution: conflict_resolution }
    #   type conflict = shift_reduce_conflict | reduce_reduce_conflict
    #   type conflict_summary = {
    #     sr: Integer,
    #     resolved_sr: Integer,
    #     rr: Integer,
    #     expected_sr: Integer,
    #     expectation_met: bool
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
