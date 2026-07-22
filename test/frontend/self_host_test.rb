# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"

class FrontendSelfHostTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/grammar/comprehensive.y", __dir__)
  GENERATED = File.expand_path("../../lib/ibex/frontend/generated_parser.rb", __dir__)

  def test_public_parser_uses_generated_implementation
    parser = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n")

    assert_instance_of Ibex::Frontend::GeneratedParser, parser.implementation
  end

  def test_generated_parser_matches_bootstrap_for_comprehensive_grammar
    source = File.read(FIXTURE)

    assert_equal bootstrap(source, file: "comprehensive.y").to_h,
                 generated(source, file: "comprehensive.y").to_h
  end

  def test_generated_parser_matches_bootstrap_for_extended_and_edge_grammars
    grammars = [
      "class P\nrule\nvalues: (A (B | C)?)+ separated_list(D, ',')\nend\n",
      "class P\ntoken A B\nrule\nfirst: A\nsecond: | B ;\nend\n"
    ]

    grammars.each do |source|
      assert_equal bootstrap(source, mode: :extended).to_h, generated(source, mode: :extended).to_h
    end
  end

  def test_generated_parser_matches_bootstrap_errors
    malformed = [
      "class P\ntoken X\n",
      "class P\nrule\ns: X\n",
      "class P\nprechigh\nmiddle X\npreclow\nrule\ns: X\nend\n",
      "class P\nrule\ns: ITEM*\nend\n"
    ]

    malformed.each do |source|
      bootstrap_error = assert_raises(Ibex::Error) { bootstrap(source) }
      generated_error = assert_raises(Ibex::Error) { generated(source) }
      assert_equal bootstrap_error.message, generated_error.message
    end
  end

  def test_committed_parser_matches_deterministic_regeneration
    assert_equal File.binread(GENERATED), Ibex::Frontend::Regenerator.generate
  end

  private

  def bootstrap(source, file: "grammar.y", mode: :racc)
    Ibex::Frontend::BootstrapParser.new(source, file: file, mode: mode).parse
  end

  def generated(source, file: "grammar.y", mode: :racc)
    Ibex::Frontend::Parser.new(source, file: file, mode: mode).parse
  end
end
