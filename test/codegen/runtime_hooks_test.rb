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
    def on_shift_location(token_id, value, state, location)
      hook_events << [:shift_location, token_id, value, state, location]
    end
    def on_reduce_location(production_id, values, result, locations, result_location)
      hook_events << [:reduce_location, production_id, values, result, locations, result_location]
    end
  GRAMMAR

  def test_generated_and_embedded_parsers_can_override_runtime_hooks
    [false, true].each do |embedded|
      parser = generate_parser(embedded: embedded).new
      first = Ibex::Location.new(file: "hooks.txt", line: 1, column: 1, end_column: 2)
      second = Ibex::Location.new(file: "hooks.txt", line: 1, column: 3, end_column: 4)

      assert_equal 5, parser.parse([[:NUM, 2, first], ["+", nil], [:NUM, 3, second]])
      assert_hook_events(parser, first, second)
    end
  end

  private

  def assert_hook_events(parser, first, second)
    events = parser.hook_events
    shifts = event_payloads(events, :shift)
    reductions = event_payloads(events, :reduce)
    located_shifts = event_payloads(events, :shift_location)
    located_reductions = event_payloads(events, :reduce_location)
    assert_equal [2, 3, 2], shifts.map(&:first)
    assert shifts.map(&:last).all?(Integer)
    assert_equal [[1, [2], 2], [1, [3], 3], [0, [2, nil, 3], 5]], reductions
    assert_equal [first, nil, second], located_shifts.map(&:last)
    assert_equal 3, located_reductions.length
    assert_same first, located_reductions.first.fetch(3).first
    assert_same first, located_reductions.first.fetch(4).start
    assert_same second, located_reductions.last.fetch(4).finish
  end

  def event_payloads(events, kind)
    events.select { |event| event.first == kind }.map { |event| event.drop(1) }
  end

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
