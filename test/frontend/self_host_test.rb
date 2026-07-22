# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"
require "open3"
require "rbconfig"

class FrontendSelfHostTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/grammar/comprehensive.y", __dir__)
  EXTENDED_FIXTURES = %w[extended.y edge.y].map do |name|
    File.expand_path("../fixtures/grammar/#{name}", __dir__)
  end.freeze
  GENERATED = File.expand_path("../../lib/ibex/frontend/generated_parser.rb", __dir__)

  def test_public_parser_uses_generated_implementation
    parser = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n")

    assert_instance_of Ibex::Frontend::GeneratedParser, parser.implementation
  end

  def test_normal_load_does_not_load_bootstrap_parser
    script = <<~'RUBY'
      require "ibex"
      abort "bootstrap loaded" if defined?(Ibex::Frontend::BootstrapParser)
      parser = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n")
      abort "generated parser not selected" unless parser.implementation.is_a?(Ibex::Frontend::GeneratedParser)
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, stderr
  end

  def test_adapter_preserves_original_token_and_location
    tokens = Ibex::Frontend::Lexer.new("class P\nrule\ns: X\nend\n", file: "identity.y").tokenize
    external, semantic_value = Ibex::Frontend::TokenAdapter.new(tokens).next_token

    assert_equal :CLASS, external
    assert_same tokens.first, semantic_value
    assert_same tokens.first.location, semantic_value.location
  end

  def test_generated_parser_matches_bootstrap_for_comprehensive_grammar
    source = File.read(FIXTURE)

    assert_equal bootstrap(source, file: "comprehensive.y").to_h,
                 generated(source, file: "comprehensive.y").to_h
  end

  def test_generated_parser_matches_bootstrap_for_extended_and_edge_grammars
    EXTENDED_FIXTURES.each do |path|
      source = File.read(path)
      file = File.basename(path)
      assert_equal bootstrap(source, file: file, mode: :extended).to_h,
                   generated(source, file: file, mode: :extended).to_h
    end
  end

  def test_generated_parser_matches_bootstrap_errors
    malformed = [
      ["class P\ntoken X\n", :racc],
      ["class P\nrule\ns: X\n", :racc],
      ["class P\nprechigh\nmiddle X\npreclow\nrule\ns: X\nend\n", :racc],
      ["class P\nprechigh\nleft X\n", :racc],
      ["class P\nconvert\nX 'x'\n", :racc],
      ["class P\nrule\nend\n", :racc],
      ["class P\nrule\ns: ITEM*\nend\n", :racc],
      ["class P\nrule\ns: (A { x })\nend\n", :extended],
      ["class P\nrule\ns: (A\nend\n", :extended],
      ["class P\nrule\ns A\nend\n", :racc],
      ["class P\nconvert\nX abc\nend\nrule\ns: X\nend\n", :racc],
      ["class P\nconvert\nX 'one' 'two'\nend\nrule\ns: X\nend\n", :racc]
    ]

    malformed.each do |source, mode|
      bootstrap_error = assert_raises(Ibex::Error) { bootstrap(source, mode: mode) }
      generated_error = assert_raises(Ibex::Error) { generated(source, mode: mode) }
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
