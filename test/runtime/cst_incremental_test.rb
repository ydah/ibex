# frozen_string_literal: true

require_relative "../test_helper"

class CSTIncrementalTest < Minitest::Test # rubocop:disable Metrics/ClassLength
  SOURCE = <<~GRAMMAR
    class IncrementalCSTParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression { raise "semantic action executed" }
    expression: term PLUS term { raise "semantic action executed" }
    term: NUM { raise "semantic action executed" }
    end
  GRAMMAR

  DROP_SOURCE = SOURCE.sub("class IncrementalCSTParser", "class DropIncrementalCSTParser")

  STATEFUL_SOURCE = <<~GRAMMAR
    class StatefulIncrementalCSTParser
    pragma extended
    pragma cst
    token STR_BEGIN STR_END CHUNK
    lexer
      state STRING do
        on '"' { pop_state; emit :STR_END }
        CHUNK /[^"]+/
      end
      on '"' { push_state :STRING; emit :STR_BEGIN }
    end
    rule
    start: STR_BEGIN CHUNK STR_END { raise "semantic action executed" }
    end
  GRAMMAR

  LIST_SOURCE = <<~GRAMMAR
    class ListIncrementalCSTParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: terms { raise "semantic action executed" }
    terms: terms PLUS term { raise "semantic action executed" }
         | term { raise "semantic action executed" }
    term: NUM { raise "semantic action executed" }
    end
  GRAMMAR

  SYNTAX_ONLY_SENTINEL_SOURCE = <<~GRAMMAR
    class SyntaxOnlySentinelParser
    pragma cst
    token WORD
    lexer
      WORD /[a-z]+/ { (@execution_sentinels ||= []) << :lexer; lexeme }
    end
    rule
    start: WORD { (@execution_sentinels ||= []) << :parser; result = val[0] }
    end
  GRAMMAR

  def test_session_is_syntax_only_from_the_initial_parse
    source = Ibex::Runtime::CST::SourceText.new("1 + 2", file: "input.txt")

    session = generate.incremental_session(source)

    assert_equal "1 + 2", session.result.syntax_root.to_source
    assert_empty session.result.diagnostics
    assert_equal 0.0, session.result.reused_ratio
    refute_respond_to session.result, :value
    assert_same source, session.source_text
    assert_equal session.result.syntax_root.green.descendant_count, session.parse_memo.left_states.length
    assert session.parse_memo.compatible?(generate.parser_tables)
  end

  def test_syntax_only_executes_lexer_action_but_not_parser_action
    parser_class = generate(SYNTAX_ONLY_SENTINEL_SOURCE)
    parser = parser_class.new

    result = parser.parse_syntax("word")

    assert_equal "word", result.syntax_root.to_source
    assert_equal [:lexer], parser.instance_variable_get(:@execution_sentinels)
    refute_respond_to result, :value

    semantic_parser = parser_class.new
    assert_equal "word", semantic_parser.parse("word")
    assert_equal %i[lexer parser], semantic_parser.instance_variable_get(:@execution_sentinels)
  end

  def test_incremental_initial_parse_and_edit_execute_only_lexer_actions
    parser_class = generate(SYNTAX_ONLY_SENTINEL_SOURCE)
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("word"))
    parser = session.instance_variable_get(:@parser)

    assert_equal [:lexer], parser.instance_variable_get(:@execution_sentinels)

    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 0, delete_length: 1, insert_text: "s")]
    )

    assert_equal "sord", result.syntax_root.to_source
    assert_equal %i[lexer lexer], parser.instance_variable_get(:@execution_sentinels)
    refute_includes parser.instance_variable_get(:@execution_sentinels), :parser
  end

  def test_leaf_parse_memo_entries_share_immutable_empty_children
    first = Ibex::Runtime::CST::ParseMemo::Entry.new(1)
    second = Ibex::Runtime::CST::ParseMemo::Entry.new(2)
    first_children = first.instance_variable_get(:@children)
    second_children = second.instance_variable_get(:@children)

    assert_same first_children, second_children
    assert_predicate first_children, :frozen?
  end

  def test_edits_match_a_fresh_syntax_only_parse_and_reuse_green_tokens # rubocop:disable Metrics/AbcSize
    parser_class = generate
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("1 + 2"))
    old_tokens = session.result.syntax_root.tokens
    old_left_term = session.result.syntax_root.children.fetch(0).children.fetch(0).child_nodes.fetch(0)

    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "3")]
    )
    batch = parser_class.incremental_session(session.source_text).result

    assert_equal "1 + 3", result.syntax_root.to_source
    assert_equal batch.syntax_root.green, result.syntax_root.green
    assert_equal batch.diagnostics, result.diagnostics
    assert_same old_tokens.fetch(0).green, result.syntax_root.tokens.fetch(0).green
    assert_same old_tokens.fetch(1).green, result.syntax_root.tokens.fetch(1).green
    new_left_term = result.syntax_root.children.fetch(0).children.fetch(0).child_nodes.fetch(0)
    assert_same old_left_term.green, new_left_term.green
    assert_operator session.last_blender.reused_descendants, :>, 0
    assert_operator result.reused_ratio, :>, 0.0
  end

  def test_incremental_trees_produce_a_minimal_applicable_text_diff
    parser_class = generate
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("1 + 2"))
    old_source = session.source_text
    old_root = session.result.syntax_root
    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "9")]
    )

    edits = Ibex::Runtime::CST::Diff.text_edits(old_root, result.syntax_root)
    edit_values = edits.map { |edit| [edit.start, edit.delete_length, edit.insert_text] }

    assert_equal "1 + 9", old_source.apply(edits).text
    assert_equal [[4, 1, "9"]], edit_values
  end

  def test_text_edits_are_sorted_merged_and_reject_overlap
    edit_class = Ibex::Runtime::CST::TextEdit
    normalized = edit_class.normalize(
      [
        edit_class.new(start: 3, delete_length: 1, insert_text: "c"),
        edit_class.new(start: 1, delete_length: 2, insert_text: "ab")
      ]
    )

    assert_equal 1, normalized.length
    assert_equal [1, 3, "abc"], [normalized.first.start, normalized.first.delete_length, normalized.first.insert_text]
    assert_raises(ArgumentError) do
      edit_class.normalize(
        [
          edit_class.new(start: 1, delete_length: 2, insert_text: ""),
          edit_class.new(start: 2, delete_length: 1, insert_text: "")
        ]
      )
    end
  end

  def test_trivia_edit_damages_its_owning_token
    session = generate.incremental_session(Ibex::Runtime::CST::SourceText.new("1  + 2"))
    memo = session.token_memo
    edit = Ibex::Runtime::CST::TextEdit.new(start: 1, delete_length: 1, insert_text: "\t")

    assert_equal 1, memo.damage_index([edit])
  end

  def test_token_memo_records_starting_generated_lexer_states
    session = generate(STATEFUL_SOURCE).incremental_session(
      Ibex::Runtime::CST::SourceText.new('"hello"')
    )

    assert_equal %i[INITIAL STRING STRING INITIAL], session.token_memo.states
  end

  def test_relexer_output_matches_a_fresh_stateful_lexical_pass
    parser_class = generate(STATEFUL_SOURCE)
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new('"hello"'))
    session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 2, delete_length: 1, insert_text: "a")]
    )
    batch = parser_class.incremental_session(session.source_text)
    relexed = session.last_relex_result.memo

    assert_equal batch.token_memo.tokens, relexed.tokens
    assert_equal batch.token_memo.offsets, relexed.offsets
    assert_equal batch.token_memo.states, relexed.states
  end

  def test_parse_memo_slices_by_preorder_occurrence
    session = generate.incremental_session(Ibex::Runtime::CST::SourceText.new("1 + 2"))
    root = session.result.syntax_root
    start = root.children.fetch(0)

    assert_equal root.green.descendant_count, session.parse_memo.slice(0, root.green).length
    assert_equal start.green.descendant_count, session.parse_memo.slice(1, start.green).length
    assert_instance_of Integer, session.parse_memo.left_state(0)
  end

  def test_repeated_stage_a_edits_equal_fresh_batch_parses # rubocop:disable Metrics/AbcSize
    parser_class = generate
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("1 + 2"))
    random = Random.new(20_260_727)
    source = +"1 + 2"

    300.times do
      index = [0, 1, 3, 4].fetch(random.rand(4))
      replacement = if [0, 4].include?(index)
                      random.rand(10).to_s
                    else
                      random.rand(2).zero? ? " " : "\t"
                    end
      edit = Ibex::Runtime::CST::TextEdit.new(start: index, delete_length: 1, insert_text: replacement)
      source[index] = replacement

      incremental = session.edit([edit])
      batch = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new(source)).result

      assert_equal source, incremental.syntax_root.to_source
      assert_equal batch.syntax_root.green, incremental.syntax_root.green
      assert_equal batch.syntax_root.green.flags, incremental.syntax_root.green.flags
      assert_equal batch.diagnostics.length, incremental.diagnostics.length
    end
  end

  def test_stage_b_random_structural_edits_equal_fresh_batch_parses # rubocop:disable Metrics/AbcSize
    parser_class = generate(LIST_SOURCE)
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("1+2+3"))
    random = Random.new(80_082)

    500.times do
      source = session.source_text.text
      numbers = source.enum_for(:scan, /[0-9]/).map { Regexp.last_match.begin(0) }
      edit = structural_edit(source, numbers, random)
      incremental = session.edit([edit])
      batch = parser_class.incremental_session(session.source_text).result

      assert_equal session.source_text.text, incremental.syntax_root.to_source
      assert_equal batch.syntax_root.green, incremental.syntax_root.green
      assert_equal batch.diagnostics.length, incremental.diagnostics.length
      assert_equal batch.syntax_root.green.flags, incremental.syntax_root.green.flags
      assert_equal batch.syntax_root.green.descendant_count, session.parse_memo.left_states.length
    end
  end

  def test_memo_budget_falls_back_deterministically_and_emits_an_event
    limits = Ibex::Runtime::ResourceLimits.new(max_session_memo_bytes: 32)
    session = generate.incremental_session(
      Ibex::Runtime::CST::SourceText.new("1 + 2"),
      resource_limits: limits
    )
    events = []
    session.observe { |event| events << event }

    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "3")]
    )

    fallback = events.find { |event| event.type == :cst_fallback }
    assert_equal "1 + 3", result.syntax_root.to_source
    assert_equal "memo_budget", fallback.data.fetch("reason")
    assert_equal 32, fallback.data.fetch("limit")
    assert_operator fallback.data.fetch("observed"), :>, fallback.data.fetch("limit")
  end

  def test_blender_can_be_disabled_without_changing_the_tree
    source = Ibex::Runtime::CST::SourceText.new("1 + 2")
    session = generate.incremental_session(source, blender: false)
    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "4")]
    )
    batch = generate.incremental_session(session.source_text, blender: false).result

    assert_equal batch.syntax_root.green, result.syntax_root.green
    assert_equal 0, session.last_blender.reused_descendants
    assert_operator result.reused_ratio, :>, 0.0
  end

  def test_decomposition_budget_falls_back_to_the_fresh_token_stream
    limits = Ibex::Runtime::ResourceLimits.new(max_incremental_decomposed_nodes: 0)
    session = generate.incremental_session(
      Ibex::Runtime::CST::SourceText.new("1 + 2"),
      resource_limits: limits
    )
    events = []
    session.observe { |event| events << event }

    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "5")]
    )
    fallback = events.find { |event| event.type == :cst_fallback }

    assert_equal "1 + 5", result.syntax_root.to_source
    assert_equal :decomposition_budget, session.last_blender.fallback_reason
    assert_equal "decomposition_budget", fallback.data.fetch("reason")
    assert_equal 0, session.last_blender.reused_descendants
  end

  def test_lexical_failure_falls_back_and_still_matches_batch_syntax
    session = generate.incremental_session(Ibex::Runtime::CST::SourceText.new("1 + 2"))
    result = session.edit(
      [Ibex::Runtime::CST::TextEdit.new(start: 2, delete_length: 1, insert_text: "?")]
    )
    batch = generate.incremental_session(session.source_text).result

    assert_equal batch.syntax_root.green, result.syntax_root.green
    assert_predicate result.syntax_root, :contains_error?
    assert_nil session.last_blender
  end

  def test_incremental_session_rejects_unsupported_sources
    source = Ibex::Runtime::CST::SourceText.new("1+2")

    error = assert_raises(Ibex::Runtime::CST::IncrementalUnsupportedError) do
      Class.new(Ibex::Runtime::Parser).incremental_session(source)
    end
    assert_match(/generated lexer/, error.message)

    error = assert_raises(Ibex::Runtime::CST::IncrementalUnsupportedError) do
      generate(DROP_SOURCE, cst_trivia: :drop).incremental_session(source)
    end
    assert_match(/drop trivia/, error.message)
  end

  private

  def structural_edit(source, numbers, random)
    edit_class = Ibex::Runtime::CST::TextEdit
    case random.rand(5)
    when 0
      edit_class.new(start: numbers.sample(random: random), delete_length: 1, insert_text: random.rand(10).to_s)
    when 1
      edit_class.new(start: source.bytesize, delete_length: 0, insert_text: "+#{random.rand(10)}")
    when 2
      return edit_class.new(start: source.bytesize, delete_length: 0, insert_text: "+1") if numbers.one?

      edit_class.new(start: numbers.last - 1, delete_length: 2, insert_text: "")
    when 3
      edit_class.new(start: 0, delete_length: 0, insert_text: "#{random.rand(10)}+")
    else
      return edit_class.new(start: 0, delete_length: 0, insert_text: "1+") if numbers.one?

      edit_class.new(start: 0, delete_length: 2, insert_text: "")
    end
  end

  def generate(source = SOURCE, cst_trivia: :leading)
    ast = Ibex::Frontend::Parser.new(source, file: "incremental.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton, cst_trivia: cst_trivia).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated_incremental.rb")
    namespace.const_get(grammar.class_name)
  end
end
