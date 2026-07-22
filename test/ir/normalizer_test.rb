# frozen_string_literal: true

require_relative "../test_helper"

class NormalizerTest < Minitest::Test
  def normalize(source, mode: :racc)
    ast = Ibex::Frontend::Parser.new(source, file: "normalize.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def test_reserves_symbols_and_round_trips_stably
    grammar = normalize("class P\ntoken INT\nrule\nstart: INT\nend\n")
    assert_equal ["$eof", "error"], grammar.symbols.first(2).map(&:name)
    assert_equal [0, 1], grammar.symbols.first(2).map(&:id)

    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal dumped, Ibex::IR::Serialize.dump(Ibex::IR::Serialize.load(dumped))
    assert_raises(FrozenError) { grammar.options[:result_var] = false }
    assert_nil grammar.symbol_by_id(10_000)
  end

  def test_desugars_inline_actions_with_stack_context
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: A { result = val[0] } B { result = val[0] + val[2] }
      end
    GRAMMAR
    inline = grammar.productions.find { |production| production.origin[:kind] == :inline_action }
    user = grammar.productions.find { |production| production.origin[:kind] == :user }
    assert_equal 1, inline.action.context_length
    assert_equal 3, user.rhs.length
    assert grammar.symbol_by_id(user.rhs[1]).name.start_with?("$inline_")
  end

  def test_desugars_extended_items_and_records_named_references
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class P
      token ITEM ','
      rule
      list: ITEM:first ITEM? ITEM* ITEM+ separated_list(ITEM, ',') { result = first }
      end
    GRAMMAR
    user = grammar.productions.last
    assert_equal [{ name: "first", index: 0 }], user.action.named_refs
    origins = grammar.productions.map { |production| production.origin[:kind] }
    assert_includes origins, :optional_expansion
    assert_includes origins, :star_expansion
    assert_includes origins, :plus_expansion
    assert_includes origins, :separated_list_expansion
  end

  def test_desugars_nested_grouped_ebnf
    grammar = normalize("class P\nrule\nstart: ((A B) | C)+\nend\n", mode: :extended)
    origins = grammar.productions.map { |production| production.origin[:kind] }
    assert_operator origins.count(:group_expansion), :>=, 3
    assert_includes origins, :plus_expansion
  end

  def test_rejects_named_references_hidden_inside_groups
    error = assert_raises(Ibex::Error) do
      normalize("class P\nrule\nstart: ((A:name B) | C)+\nend\n", mode: :extended)
    end
    assert_match(/named references inside EBNF groups are not supported/, error.message)
  end

  def test_options_precedence_conversions_and_user_code
    grammar = normalize(<<~GRAMMAR)
      class P
      token INT PLUS
      preclow
      left PLUS
      right UMINUS
      prechigh
      options no_result_var no_omit_action_call
      expect 2
      convert
      INT '"Number"'
      end
      rule
      start: INT = UMINUS
      end
      ---- header
      HEADER
      ---- header
      MORE
    GRAMMAR
    assert_equal({ result_var: false, omit_action_call: false }, grammar.options)
    assert_equal 2, grammar.expect
    assert_equal({ associativity: :left, level: 1 }, grammar.symbol("PLUS").precedence)
    assert_equal({ associativity: :right, level: 2 }, grammar.symbol("UMINUS").precedence)
    assert_equal "\"Number\"", grammar.conversions["INT"]
    assert_equal "HEADER\nMORE\n", grammar.user_code["header"]
  end

  def test_rejects_undefined_nonterminal_and_bad_named_references
    error = assert_raises(Ibex::Error) { normalize("class P\nrule\nstart: missing\nend\n") }
    assert_equal "normalize.y:3:8: undefined nonterminal missing", error.message

    source = "class P\nrule\nstart: X:a Y:a\nend\n"
    error = assert_raises(Ibex::Error) { normalize(source, mode: :extended) }
    assert_match(/normalize\.y:3:12: duplicate named reference a/, error.message)

    source = "class P\nrule\nstart: X:result\nend\n"
    error = assert_raises(Ibex::Error) { normalize(source, mode: :extended) }
    assert_match(/reserved named reference result/, error.message)
  end

  def test_warns_about_declared_and_unreachable_symbols
    grammar = normalize(<<~GRAMMAR)
      class P
      token USED UNUSED
      rule
      start: USED EXTRA
      dead: USED
      end
    GRAMMAR
    warning_types = grammar.warnings.map { |warning| warning[:type] }
    assert_includes warning_types, :undeclared_terminal
    assert_includes warning_types, :unused_terminal
    assert_includes warning_types, :unreachable_nonterminal
  end

  def test_warns_when_the_start_symbol_cannot_derive_a_terminal_sentence
    grammar = normalize("class P\nrule\nstart: loop\nloop: start\nend\n")
    warning = grammar.warnings.find { |item| item[:type] == :empty_language }
    assert_equal "start", warning[:symbol]
    assert_equal 3, warning.dig(:loc, :line)
  end

  def test_rejects_unknown_schema_version_with_position
    error = assert_raises(Ibex::Error) do
      Ibex::IR::Serialize.load('{"ibex_ir":"grammar","schema_version":99}')
    end
    assert_equal "(ir):1:1: unsupported schema_version 99; expected 1", error.message
  end
end
