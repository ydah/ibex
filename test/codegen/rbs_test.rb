# frozen_string_literal: true

require_relative "../test_helper"

class RBSCodegenTest < Minitest::Test
  def test_generates_namespaced_parser_contract
    source = "class API::Generated < Custom::Parser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "signature.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature, "module API"
    assert_includes signature, "class Generated < Custom::Parser"
    assert_includes signature, "TOKEN_IDS: Hash[untyped, Integer]"
    assert_includes signature, "DEFAULT_ACTIONS: Array[untyped]"
    assert_includes signature, "def self.parser_tables: () -> Hash[Symbol, untyped]"
  end
end
