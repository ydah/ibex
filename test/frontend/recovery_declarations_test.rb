# frozen_string_literal: true

require_relative "../test_helper"

class FrontendRecoveryDeclarationsTest < Minitest::Test
  def test_parses_sync_recovery_and_on_error_reduction_declarations
    source = <<~GRAMMAR
      class P
      pragma extended
      %recover sync: ';' '}'
      %on_error_reduce expression statement
      rule
      statement: expression ';'
      expression: NUM
      end
    GRAMMAR
    recovery, reductions = parse(source).declarations

    assert_instance_of Ibex::Frontend::AST::Recovery, recovery
    assert_equal ["';'", "'}'"], recovery.sync_tokens
    assert_instance_of Ibex::Frontend::AST::OnErrorReduce, reductions
    assert_equal %w[expression statement], reductions.names
  end

  def test_declarations_require_extended_mode
    {
      "%recover sync: ';'" => "%recover require extended mode",
      "%on_error_reduce expression" => "%on_error_reduce require extended mode"
    }.each do |declaration, message|
      error = assert_raises(Ibex::Error) do
        parse("class P\n#{declaration}\nrule\nstart: TOKEN\nend\n")
      end
      assert_includes error.message, message
    end
  end

  def test_recovery_declaration_requires_the_sync_kind
    error = assert_raises(Ibex::Error) do
      parse("class P\npragma extended\n%recover retry: ';'\nrule\nstart: TOKEN\nend\n")
    end

    assert_equal "grammar.y:3:10: expected sync, got retry", error.message
  end

  def test_formatter_keeps_recovery_declarations_separate_and_idempotent
    source = "class P pragma extended token ITEM BAD %recover sync:';' '}' " \
             "%on_error_reduce expression statement rule expression:ITEM end"
    expected = <<~GRAMMAR
      class P
      pragma extended
      token ITEM BAD
      %recover sync:';' '}'
      %on_error_reduce expression statement
      rule
        expression : ITEM
      end
    GRAMMAR

    formatted = Ibex::Frontend::Formatter.format(source, file: "grammar.y", mode: :extended)

    assert_equal expected, formatted
    assert_equal formatted, Ibex::Frontend::Formatter.format(formatted, file: "grammar.y", mode: :extended)
  end

  private

  def parse(source)
    Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
  end
end
