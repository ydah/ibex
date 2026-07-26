# frozen_string_literal: true

require_relative "../test_helper"

class FrontendLegacyRuleTerminationTest < Minitest::Test
  def test_accepts_a_user_code_section_as_the_rule_terminator
    source = <<~GRAMMAR
      class P
      rule
      start: TOKEN
      ---- header
      require "set"
      ---- inner
      def helper = true
    GRAMMAR

    ast = Ibex::Frontend::Parser.new(source, file: "legacy.y").parse

    assert_equal %w[header inner], ast.user_code.keys
    assert_equal "require \"set\"\n", ast.user_code.fetch("header").first.code
    assert_equal "def helper = true\n", ast.user_code.fetch("inner").first.code
  end
end
