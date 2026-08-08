# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class IRDeclarativeParserContractTest < Minitest::Test
  def test_parser_declaration_writes_a_native_v3_contract_and_round_trips
    grammar = normalize(<<~GRAMMAR)
      class P
      parser
        algorithm ielr
        entries isolated
      end
      start program expression
      rule
      program: PROGRAM
      expression: EXPRESSION
      end
    GRAMMAR
    contract = grammar.parser_contract

    assert_equal 3, grammar.schema_version
    assert_explicit_contract(contract)
    assert_contract_round_trip(grammar, contract)
  end

  def test_parser_setting_order_does_not_change_the_contract_values
    first = normalize(grammar_with("algorithm lr1\n  entries shared"))
    second = normalize(grammar_with("entries shared\n  algorithm lr1"))

    assert_equal first.parser_contract.configuration_values, second.parser_contract.configuration_values
  end

  def test_cst_trivia_declaration_is_persisted_in_the_v3_contract
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma cst
      parser
        cst_trivia balanced
      end
      rule
      start: TOKEN
      end
    GRAMMAR
    contract = grammar.parser_contract

    assert_equal :balanced, contract.cst_trivia.value
    assert contract.cst_trivia.explicit
    assert_equal "normalize.y", contract.cst_trivia.location.file
    round_tripped = Ibex::IR::Serialize.load(Ibex::IR::Serialize.dump(grammar))
    assert_equal :balanced, round_tripped.parser_contract.cst_trivia.value
  end

  def test_declaration_free_grammar_remains_v2_without_a_parser_contract
    source = "class P\nrule\nstart: TOKEN\nend\n"
    grammar = normalize(source)
    dumped = Ibex::IR::Serialize.dump(grammar)

    assert_equal 2, grammar.schema_version
    assert_nil grammar.parser_contract
    refute_includes dumped, "parser_contract"
  end

  def test_isolated_entries_require_multiple_meaningful_start_symbols
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        parser
          entries isolated
        end
        rule
        start: TOKEN
        end
      GRAMMAR
    end

    assert_equal "normalize.y:3:3: parser.entries isolated requires at least two start symbols", error.message
  end

  def test_multiple_parser_blocks_are_rejected_at_the_second_block
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        parser
          algorithm lalr
        end
        parser
          entries shared
        end
        rule
        start: TOKEN
        end
      GRAMMAR
    end

    assert_equal "normalize.y:5:1: duplicate parser declaration", error.message
  end

  def test_root_contract_survives_fragment_resolution_without_transferring_ownership
    Dir.mktmpdir("ibex-parser-contract") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "part.y")
      File.binwrite(fragment, "fragment\nrule\npart: PART\nend\n")
      File.binwrite(root, <<~GRAMMAR)
        class P
        parser
          algorithm slr
        end
        include "part.y"
        rule
        start: part
        end
      GRAMMAR

      resolution = Ibex::Frontend::Resolver.new(root, mode: :extended).resolve
      grammar = Ibex::Normalizer.new(resolution, mode: :extended).normalize

      assert_equal :slr, grammar.parser_contract.algorithm.value
      assert grammar.symbol("part").nonterminal?
    end
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "normalize.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def grammar_with(settings)
    <<~GRAMMAR
      class P
      parser
        #{settings}
      end
      rule
      start: TOKEN
      end
    GRAMMAR
  end

  def assert_explicit_contract(contract)
    assert_equal :ielr, contract.algorithm.value
    assert_equal :isolated, contract.entries.value
    assert contract.algorithm.explicit
    assert contract.entries.explicit
    refute contract.cst_trivia.explicit
    assert_equal "normalize.y", contract.algorithm.location.file
    assert_equal [3, 3], [contract.algorithm.location.line, contract.algorithm.location.column]
  end

  def assert_contract_round_trip(grammar, contract)
    dumped = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Validator.validate(dumped)
    assert_equal dumped, Ibex::IR::Serialize.dump(loaded)
    assert_equal contract.to_h, loaded.parser_contract.to_h
  end
end
