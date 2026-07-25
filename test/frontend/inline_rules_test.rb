# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"
require "tmpdir"

class FrontendInlineRulesTest < Minitest::Test
  def test_parses_inline_rules_without_changing_ordinary_rules
    ast = parse(<<~GRAMMAR)
      class P
      pragma extended
      rule
      %inline helper: ITEM
      start: helper
      end
    GRAMMAR

    helper, start = ast.rules
    assert_predicate helper, :inline
    refute_predicate start, :inline
    assert_equal "helper", helper.lhs
    assert_includes helper.to_h, :inline
  end

  def test_inline_rules_are_extended_only_but_pragma_enables_them
    source = "class P\nrule\n%inline helper: ITEM\nstart: helper\nend\n"
    error = assert_raises(Ibex::Error) { parse(source, mode: :racc) }
    assert_equal "inline.y:3:1: inline rules require extended mode", error.message

    source = "class P\npragma extended\nrule\n%inline helper: ITEM\nstart: helper\nend\n"
    assert_predicate parse(source, mode: :racc).rules.first, :inline
  end

  def test_bootstrap_and_generated_frontends_agree_for_roots_and_fragments
    sources = [
      <<~GRAMMAR,
        class P
        pragma extended
        rule
        %inline pair(X): X X
        start: pair(ITEM)
        end
      GRAMMAR
      <<~GRAMMAR
        fragment
        rule
        %inline helper:
          ITEM
        end
      GRAMMAR
    ]

    sources.each do |source|
      generated = Ibex::Frontend::Parser.new(source, file: "inline.y", mode: :extended)
      bootstrap = Ibex::Frontend::BootstrapParser.new(source, file: "inline.y", mode: :extended)
      generated_node = source.start_with?("fragment") ? generated.parse_fragment : generated.parse
      bootstrap_node = source.start_with?("fragment") ? bootstrap.parse_fragment : bootstrap.parse
      assert_equal generated_node.to_h, bootstrap_node.to_h
    end
  end

  def test_percent_inside_actions_is_not_a_directive
    ast = parse(<<~GRAMMAR)
      class P
      pragma extended
      rule
      %inline helper: ITEM { result = val[0] % 2 }
      start: helper
      end
    GRAMMAR

    assert_equal " result = val[0] % 2 ", ast.rules.first.alternatives.first.action.code
  end

  def test_inline_directive_is_exact
    error = assert_raises(Ibex::Error) do
      parse("class P\npragma extended\nrule\n%inline_helper: ITEM\nend\n")
    end
    assert_includes error.message, "unexpected character \"%\""
  end

  def test_constructor_documentation_and_resolver_freezing_preserve_inline
    location = Ibex::Frontend::Location.new(file: "legacy.rb", line: 1, column: 1)
    keyword_rule = Ibex::Frontend::AST::Rule.new(lhs: "start", alternatives: [], loc: location)
    hash_rule = Ibex::Frontend::AST::Rule.new({ lhs: "start", alternatives: [], loc: location })
    nil_rule = Ibex::Frontend::AST::Rule.new(lhs: "start", alternatives: [], loc: location, inline: nil)
    assert_equal [false, false, false], [keyword_rule.inline, hash_rule.inline, nil_rule.inline]

    Dir.mktmpdir("ibex-inline") do |directory|
      root = File.join(directory, "root.y")
      File.write(root, <<~GRAMMAR)
        class P
        pragma extended
        rule
        ## Flattened helper.
        %inline
        helper: ITEM
        start: helper
        end
      GRAMMAR

      helper = Ibex::Frontend::Resolver.new(root).resolve.root.rules.first
      assert_predicate helper, :inline
      assert_equal "Flattened helper.", helper.documentation
      assert_predicate helper, :frozen?
    end
  end

  private

  def parse(source, mode: :extended)
    Ibex::Frontend::Parser.new(source, file: "inline.y", mode: mode).parse
  end
end
