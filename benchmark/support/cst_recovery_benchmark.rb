# frozen_string_literal: true

module CSTRecoveryBenchmark
  module_function

  INPUT = "i x x; i;"

  def measure(iterations)
    red_green = CSTBenchmark.build_parser(grammar_source(cst: true))
    plain = recovery_parser(CSTBenchmark.build_parser(grammar_source(cst: false)))
    plain_result = CSTBenchmark.measure(plain, INPUT, iterations)
    red_green_result = CSTBenchmark.measure(red_green, INPUT, iterations)
    {
      input_bytes: INPUT.bytesize,
      measurements: {
        plain: plain_result,
        red_green_cst: red_green_result
      },
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

  def recovery_parser(parser_class)
    Class.new(parser_class) do
      def on_error(_token_id, _value, _value_stack); end
    end
  end
end
