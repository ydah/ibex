# frozen_string_literal: true

require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- cases cover one normalization boundary.
class NormalizerTest < Minitest::Test
  def normalize(source, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "normalize.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def test_reserves_symbols_and_round_trips_stably
    grammar = normalize("class P\ntoken INT\nrule\nstart: INT\nend\n")
    assert_equal 2, grammar.schema_version
    assert_equal :default, grammar.mode
    assert_equal({ file: "normalize.y", root: nil, byte_span: nil }, grammar.source_provenance)
    assert_equal ["$eof", "error"], grammar.symbols.first(2).map(&:name)
    assert_equal [0, 1], grammar.symbols.first(2).map(&:id)

    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal dumped, Ibex::IR::Serialize.dump(Ibex::IR::Serialize.load(dumped))
    assert_raises(FrozenError) { grammar.options[:result_var] = false }
    assert_nil grammar.symbol_by_id(10_000)
  end

  def test_extended_mode_round_trips_as_optional_v2_metadata
    grammar = normalize("class P\nrule\nstart: TOKEN\nend\n", mode: :extended)
    dumped = Ibex::IR::Serialize.dump(grammar)

    assert_equal :extended, grammar.mode
    assert_includes dumped, '"mode": "extended"'
    assert_equal :extended, Ibex::IR::Serialize.load(dumped).mode

    compatible = Ibex::IR::Serialize.dump(normalize("class P\nrule\nstart: TOKEN\nend\n"))
    refute_includes compatible, '"mode"'
  end

  def test_extended_pragma_sets_the_normalized_mode
    grammar = normalize("class P\npragma extended\nrule\nstart: TOKEN\nend\n")

    assert_equal :extended, grammar.mode
  end

  def test_cst_pragma_round_trips_as_optional_v2_metadata
    grammar = normalize("class P\npragma cst\nrule\nstart: TOKEN\nend\n")
    dumped = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Validator.validate(dumped)

    assert_equal :extended, grammar.mode
    assert_equal true, grammar.options.fetch(:cst)
    assert_equal true, loaded.options.fetch(:cst)
    assert_includes dumped, '"cst": true'
    refute_includes Ibex::IR::Serialize.dump(normalize("class P\nrule\nstart: TOKEN\nend\n")), '"cst"'
  end

  def test_multiple_start_symbols_round_trip_as_optional_v2_metadata
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class P
      pragma extended
      start program expression
      rule
      program: PROGRAM
      expression: EXPRESSION
      end
    GRAMMAR
    dumped = Ibex::IR::Serialize.dump(grammar)

    assert_equal "program", grammar.start
    assert_equal %w[program expression], grammar.starts
    assert_equal grammar.starts, Ibex::IR::Serialize.load(dumped).starts
    assert_includes dumped, '"starts"'
    refute(grammar.warnings.any? { |warning| warning[:type] == :unreachable_nonterminal })
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
    expressions = grammar.productions.filter_map { |production| production.origin[:expression] }
    assert_includes expressions, "ITEM?"
    assert_includes expressions, "ITEM*"
    assert_includes expressions, "ITEM+"
    assert_includes expressions, "separated_list(ITEM, ',')"
  end

  def test_desugars_nested_grouped_ebnf
    grammar = normalize("class P\nrule\nstart: ((A B) | C)+\nend\n", mode: :extended)
    origins = grammar.productions.map { |production| production.origin[:kind] }
    assert_operator origins.count(:group_expansion), :>=, 3
    assert_includes origins, :plus_expansion
    expressions = grammar.productions.filter_map { |production| production.origin[:expression] }
    assert_includes expressions, "((A B) | C)+"
    assert_includes expressions, "(A B)"
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

  def test_constructor_parameters_round_trip_as_optional_v2_metadata
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class P
      pragma extended
      %param context "Hash[Symbol, Integer]"
      %param lexer
      rule
      start: TOKEN
      end
    GRAMMAR

    expected = [
      { name: "context", semantic_type: "Hash[Symbol, Integer]" },
      { name: "lexer", semantic_type: nil }
    ]
    assert_equal expected, grammar.parser_parameters
    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal expected, Ibex::IR::Serialize.load(dumped).parser_parameters
    assert_includes dumped, '"params"'

    plain = normalize("class P\nrule\nstart: TOKEN\nend\n")
    refute_includes Ibex::IR::Serialize.dump(plain), '"params"'
  end

  def test_value_printers_round_trip_as_optional_v2_metadata
    grammar = normalize(<<~'GRAMMAR', mode: :extended)
      class P
      pragma extended
      %printer TOKEN { "token=#{value}" }
      %printer start { value.inspect }
      rule
      start: TOKEN
      end
    GRAMMAR

    assert_equal(
      %w[TOKEN start],
      grammar.value_printers.map { |printer| printer[:symbol] }
    )
    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal grammar.value_printers, Ibex::IR::Serialize.load(dumped).value_printers
    assert_includes dumped, '"printers"'

    plain = normalize("class P\nrule\nstart: TOKEN\nend\n")
    refute_includes Ibex::IR::Serialize.dump(plain), '"printers"'
  end

  def test_recovery_policy_round_trips_as_optional_v2_metadata
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class P
      pragma extended
      %recover sync: ';' NUM
      %on_error_reduce expression
      %on_error_reduce statement
      rule
      statement: expression ';'
      expression: NUM
      end
    GRAMMAR
    expected = {
      sync_tokens: ["';'", "NUM"],
      on_error_reduce: [%w[expression], %w[statement]]
    }

    assert_equal expected, grammar.recovery
    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal expected, Ibex::IR::Serialize.load(dumped).recovery
    assert_includes dumped, '"recovery"'

    plain = normalize("class P\nrule\nstart: TOKEN\nend\n")
    assert_equal({ sync_tokens: [], on_error_reduce: [] }, plain.recovery)
    refute_includes Ibex::IR::Serialize.dump(plain), '"recovery"'
  end

  def test_grammar_tests_round_trip_as_optional_v2_metadata
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      %test accept "ok"
      %test reject "bad"
      rule
      start: TOKEN
      end
    GRAMMAR

    assert_equal(
      [[:accept, "ok"], [:reject, "bad"]],
      grammar.grammar_tests.map { |test| [test[:expectation], test[:source]] }
    )
    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal grammar.grammar_tests, Ibex::IR::Serialize.load(dumped).grammar_tests
    assert_includes dumped, '"tests"'

    plain = normalize("class P\nrule\nstart: TOKEN\nend\n")
    assert_empty plain.grammar_tests
    refute_includes Ibex::IR::Serialize.dump(plain), '"tests"'
  end

  def test_rejects_duplicate_grammar_tests
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        pragma extended
        %test accept "same"
        %test accept "same"
        rule
        start: TOKEN
        end
      GRAMMAR
    end

    assert_includes error.message, "duplicate %test accept source"
  end

  def test_rejects_missing_sync_tokens
    missing = <<~GRAMMAR
      class P
      pragma extended
      %recover sync: MISSING
      rule
      start: TOKEN
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) { normalize(missing) }
    assert_includes error.message, "%recover sync references nonterminal or missing token MISSING"
  end

  def test_rejects_terminal_on_error_reduction_symbols
    terminal = <<~GRAMMAR
      class P
      pragma extended
      %on_error_reduce TOKEN
      rule
      start: TOKEN
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) { normalize(terminal) }
    assert_includes error.message, "%on_error_reduce references terminal or missing nonterminal TOKEN"
  end

  def test_rejects_duplicate_on_error_reduction_symbols
    duplicate = <<~GRAMMAR
      class P
      pragma extended
      %on_error_reduce expression
      %on_error_reduce expression
      rule
      start: expression
      expression: TOKEN
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) { normalize(duplicate) }
    assert_includes error.message, "duplicate %on_error_reduce symbol expression"
  end

  def test_rejects_duplicate_or_missing_value_printer_symbols
    duplicate = <<~GRAMMAR
      class P
      pragma extended
      %printer TOKEN { value }
      %printer TOKEN { value.inspect }
      rule
      start: TOKEN
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) { normalize(duplicate) }
    assert_includes error.message, "duplicate %printer declaration for TOKEN"

    missing = "class P\npragma extended\n%printer MISSING { value }\nrule\nstart: TOKEN\nend\n"
    error = assert_raises(Ibex::Error) { normalize(missing) }
    assert_includes error.message, "%printer references missing symbol MISSING"
  end

  def test_rejects_duplicate_or_keyword_constructor_parameters
    duplicate = <<~GRAMMAR
      class P
      pragma extended
      %param context
      %param context
      rule
      start: TOKEN
      end
    GRAMMAR
    error = assert_raises(Ibex::Error) { normalize(duplicate) }
    assert_includes error.message, "duplicate %param declaration for context"

    keyword = "class P\npragma extended\n%param class\nrule\nstart: TOKEN\nend\n"
    error = assert_raises(Ibex::Error) { normalize(keyword) }
    assert_includes error.message, '%param name "class" is a Ruby keyword'

    constant = "class P\npragma extended\n%param Context\nrule\nstart: TOKEN\nend\n"
    error = assert_raises(Ibex::Error) { normalize(constant) }
    assert_includes error.message, '%param name "Context" must be a Ruby local identifier'
  end

  def test_preserves_each_user_code_chunk_location_through_ir
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: TOKEN
      end
      ---- header
      HEADER
      ---- header
      MORE
    GRAMMAR
    chunks = grammar.user_code_chunks["header"]
    assert_equal %W[HEADER\n MORE\n], chunks.map(&:code)
    chunk_lines = chunks.map { |chunk| chunk.location[:line] }
    assert_equal [6, 8], chunk_lines

    dumped = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Serialize.load(dumped)
    assert_equal dumped, Ibex::IR::Serialize.dump(loaded)
    loaded_lines = loaded.user_code_chunks["header"].map { |chunk| chunk.location[:line] }
    assert_equal [6, 8], loaded_lines
  end

  def test_loads_schema_v2_grammar_without_user_code_chunks
    grammar = normalize("class P\nrule\nstart: TOKEN\nend\n")
    data = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    data.delete("user_code_chunks")

    loaded = Ibex::IR::Serialize.load(JSON.generate(data))

    assert_empty loaded.user_code_chunks
    refute_includes Ibex::IR::Serialize.dump(loaded), "user_code_chunks"
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

  def test_explicit_empty_suppresses_the_implicit_empty_warning
    explicit = normalize("class P\npragma extended\nrule\nstart: %empty\nend\n", mode: :extended)
    implicit = normalize("class P\npragma extended\nrule\nstart:\nend\n", mode: :extended)

    refute_includes explicit.warnings.map { |warning| warning[:type] }, :implicit_empty
    assert_includes implicit.warnings.map { |warning| warning[:type] }, :implicit_empty
  end

  def test_rejects_empty_marker_mixed_with_rhs_symbols
    error = assert_raises(Ibex::Error) do
      normalize("class P\npragma extended\nrule\nstart: %empty TOKEN\nend\n", mode: :extended)
    end
    assert_equal "normalize.y:4:8: %empty must be the only item in an alternative", error.message
  end

  def test_rejects_unknown_schema_version_with_position
    error = assert_raises(Ibex::Error) do
      Ibex::IR::Serialize.load('{"ibex_ir":"grammar","schema_version":99}')
    end
    assert_equal "(ir):1:1: unsupported schema_version 99; expected one of 1, 2, 3", error.message
  end
end
# rubocop:enable Metrics/ClassLength
