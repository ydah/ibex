# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeHooksCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class HookedCalc
    token NUM
    preclow
      left '+'
    prechigh
    rule
      expr : expr '+' expr { result = val[0] + val[2] }
           | NUM { result = val[0] }
    end
    ---- inner
    def parse(tokens) = (@tokens = tokens; do_parse)
    def next_token = @tokens.shift
    def hook_events = (@hook_events ||= [])
    def on_shift(token_id, value, state) = hook_events << [:shift, token_id, value, state]
    def on_reduce(production_id, values, result) = hook_events << [:reduce, production_id, values, result]
  GRAMMAR

  def test_generated_and_embedded_parsers_can_override_runtime_hooks
    [false, true].each do |embedded|
      parser = generate_parser(embedded: embedded).new

      assert_equal 5, parser.parse([[:NUM, 2], ["+", nil], [:NUM, 3]])
      shifts = parser.hook_events.filter_map { |event| event.drop(1) if event.first == :shift }
      reductions = parser.hook_events.filter_map { |event| event.drop(1) if event.first == :reduce }
      assert_equal [2, 3, 2], shifts.map(&:first)
      assert shifts.map(&:last).all?(Integer)
      assert_equal [[1, [2], 2], [1, [3], 3], [0, [2, nil, 3], 5]], reductions
    end
  end

  private

  def generate_parser(embedded:)
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "runtime_hooks.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    source = Ibex::Codegen::Ruby.new(automaton, embedded: embedded).generate
    container = Module.new
    container.module_eval(source, "runtime_hooks.rb")
    container.const_get(:HookedCalc)
  end
end
