# frozen_string_literal: true

module CSTRecoveryBenchmark
  module_function

  INPUT = "i x x; i;"

  def measure(iterations)
    red_green = CSTBenchmark.build_parser(grammar_source(cst: true))
    legacy = legacy_parser(red_green)
    plain = recovery_parser(CSTBenchmark.build_parser(grammar_source(cst: false)))
    plain_result = CSTBenchmark.measure(plain, INPUT, iterations)
    legacy_result = CSTBenchmark.measure(legacy, INPUT, iterations, suppress_legacy_warning: true)
    red_green_result = CSTBenchmark.measure(red_green, INPUT, iterations)
    {
      input_bytes: INPUT.bytesize,
      measurements: {
        plain: plain_result,
        legacy_cst: legacy_result,
        red_green_cst: red_green_result
      },
      legacy_cst_overhead_ratio: legacy_result.fetch(:elapsed_ms) / plain_result.fetch(:elapsed_ms),
      red_green_cst_overhead_ratio: red_green_result.fetch(:elapsed_ms) / plain_result.fetch(:elapsed_ms)
    }
  end

  def grammar_source(cst:)
    pragma = cst ? "pragma cst" : ""
    <<~GRAMMAR
      class CSTRecoveryBenchmarkParser
      pragma extended
      #{pragma}
      token ITEM BAD SEMI
      %recover sync: SEMI
      lexer
        skip /[[:space:]]+/
        ITEM 'i'
        BAD 'x'
        SEMI ';'
      end
      rule
      program: statements
      statements: statements statement | statement
      statement: ITEM SEMI
      end
    GRAMMAR
  end

  def legacy_parser(parser_class)
    current = parser_class.parser_tables
    kinds = current.fetch(:cst).fetch(:kinds)
    start_kind = kinds.fetch(:nonterminal_range).fetch(0)
    tables = current.merge(
      format_version: 5,
      cst: true,
      cst_start: kinds.fetch(:names).fetch(start_kind),
      cst_trivia: :attach,
      symbol_names: kinds.fetch(:names)
    ).freeze
    Class.new(parser_class).tap do |legacy_class|
      legacy_class.define_singleton_method(:parser_tables) { tables }
    end
  end

  def recovery_parser(parser_class)
    Class.new(parser_class) do
      def on_error(_token_id, _value, _value_stack); end
    end
  end
end
