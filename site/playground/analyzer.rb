# frozen_string_literal: true

require "json"

# Browser-facing adapter that only parses grammar source and builds immutable IR.
# User action bodies are kept as data and are never evaluated.
module IbexPlayground
  MAX_SOURCE_BYTES = 100_000
  MAX_CONFLICTS = 100
  MAX_COUNTEREXAMPLE_TOKENS = 32
  MAX_COUNTEREXAMPLE_CONFIGURATIONS = 50_000
  ALGORITHMS = %w[lalr ielr lr1 slr].freeze

  module_function

  def analyze(source, algorithm)
    validate_input!(source, algorithm)
    result = Ibex::Frontend::Parser.new(source, file: "playground.y", mode: :extended)
                                   .parse_with_diagnostics(max_diagnostics: 20)
    return generate(ok: false, diagnostics: result.diagnostics.map(&:to_h)) unless result.success?

    grammar = Ibex::Normalizer.new(result.ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar, algorithm: algorithm.to_sym).build
    examples = Ibex::LALR::Counterexample.new(
      automaton,
      max_tokens: MAX_COUNTEREXAMPLE_TOKENS,
      max_configurations: MAX_COUNTEREXAMPLE_CONFIGURATIONS
    )
    conflicts = conflict_documents(automaton, examples)
    generate(
      ok: true,
      algorithm: automaton.algorithm,
      summary: summary(grammar, automaton),
      conflict_summary: automaton.conflict_summary,
      warnings: grammar.warnings,
      conflicts: conflicts,
      conflicts_truncated: automaton.states.sum { |state| state.conflicts.length } > conflicts.length,
      automaton: automaton.to_h
    )
  rescue Ibex::Error, ArgumentError => e
    generate(ok: false, diagnostics: [error_document(e.message)])
  rescue StandardError
    generate(
      ok: false,
      diagnostics: [error_document("The browser analyzer could not process this grammar.")]
    )
  end

  def validate_input!(source, algorithm)
    raise ArgumentError, "grammar source must be text" unless source.is_a?(String)
    raise ArgumentError, "grammar source is empty" if source.strip.empty?
    raise ArgumentError, "grammar source exceeds #{MAX_SOURCE_BYTES} bytes" if source.bytesize > MAX_SOURCE_BYTES
    raise ArgumentError, "unsupported parser algorithm #{algorithm.inspect}" unless ALGORITHMS.include?(algorithm)
  end
  private_class_method :validate_input!

  def summary(grammar, automaton)
    {
      terminals: grammar.terminals.length,
      nonterminals: grammar.nonterminals.length,
      productions: grammar.productions.length,
      states: automaton.states.length,
      conflicts: automaton.states.sum { |state| state.conflicts.length }
    }
  end
  private_class_method :summary

  def conflict_documents(automaton, examples)
    documents = []
    automaton.states.each do |state|
      state.conflicts.each_with_index do |conflict, index|
        return documents if documents.length >= MAX_CONFLICTS

        documents << {
          state: state.id,
          index: index,
          token: conflict_token(automaton, conflict),
          conflict: conflict,
          counterexample: examples.for_conflict(state.id, index)
        }
      end
    end
    documents
  end
  private_class_method :conflict_documents

  def conflict_token(automaton, conflict)
    symbol = automaton.grammar.symbol_by_id(conflict.fetch(:symbol))
    symbol&.display_name || symbol&.name
  end
  private_class_method :conflict_token

  def error_document(message)
    {
      code: "playground.analysis_error",
      severity: "error",
      phase: "analysis",
      message: message,
      location: { file: "playground.y", line: 1, column: 1 }
    }
  end
  private_class_method :error_document

  def generate(value)
    JSON.generate(value)
  end
  private_class_method :generate
end
