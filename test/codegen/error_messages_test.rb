# frozen_string_literal: true

require_relative "../test_helper"

class ErrorMessagesCodegenTest < Minitest::Test
  LOCATION = {
    file: "input.expr",
    line: 3,
    column: 4,
    source_line: "1 + nope"
  }.freeze

  def test_custom_state_messages_preserve_structured_error_context_across_output_modes
    automaton = build_automaton
    messages = Ibex::ErrorMessages.error_states(automaton).to_h do |state|
      [state.id, "Custom syntax message for state #{state.id}.\nUse an integer here."]
    end

    [{ table: :plain, embedded: false }, { table: :compact, embedded: false },
     { table: :plain, embedded: true }, { table: :compact, embedded: true }].each do |options|
      parser_class = evaluate(automaton, messages, **options)
      error = assert_raises(StandardError) do
        parser_class.new.parse_tokens([[:BAD, "payload", LOCATION]])
      end
      assert_structured_custom_error(error)
      assert_equal messages, parser_class::PARSER_TABLES.fetch(:error_messages)

      push_error = assert_raises(StandardError) { parser_class.new.push(:BAD, "payload", LOCATION) }
      assert_structured_custom_error(push_error)
    end
  end

  private

  def build_automaton
    source = <<~GRAMMAR
      class GeneratedMessagesParser
      rule
      start: INT '+' INT
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "messages.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def evaluate(automaton, messages, **options)
    generated = Ibex::Codegen::Ruby.new(automaton, error_messages: messages, **options).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated-messages.rb")
    namespace.const_get(:GeneratedMessagesParser)
  end

  def assert_structured_custom_error(error)
    assert_equal "ParseError", error.class.name.split("::").last
    assert_includes error.message, "input.expr:3:4: Custom syntax message for state #{error.state}."
    assert_includes error.message, "Use an integer here."
    assert_match(/1 \+ nope\n   \^/, error.message)
    assert_equal ":BAD", error.token_name
    assert_kind_of Integer, error.token_id
    assert_equal "payload", error.token_value
    assert_equal LOCATION, error.location
    assert_kind_of Integer, error.state
    assert_kind_of Array, error.expected_tokens
    assert_kind_of Array, error.suggestions
  end
end
