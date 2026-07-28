# frozen_string_literal: true

require_relative "../test_helper"

class CSTEditingTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class EditingParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: expression
    expression: term PLUS term
    term: NUM
    end
  GRAMMAR

  def test_path_copying_preserves_untouched_green_subtrees # rubocop:disable Metrics/AbcSize
    root = parse("1 + 2")
    expression = root.children.fetch(0).children.fetch(0)
    first, plus, second = expression.tokens
    edited = first.with_text("10")
    edited_expression = edited.children.fetch(0).children.fetch(0)

    assert_equal "10 + 2", edited.to_source
    assert_equal "1 + 2", root.to_source
    refute_same root.green, edited.green
    refute_same expression.green, edited_expression.green
    assert_same plus.green, edited_expression.tokens.fetch(1).green
    assert_same second.green, edited_expression.tokens.fetch(2).green
    assert_equal root.green.descendant_count, edited.green.descendant_count
    assert_equal occurrence_depth(first), changed_green_count(root.green, edited.green)
  end

  def test_node_and_trivia_primitives_return_new_roots
    root = parse("1+2")
    expression = root.children.fetch(0).children.fetch(0)
    first = expression.first_token
    whitespace = Ibex::Runtime::CST::GreenTrivia.new(
      kind: root.kinds.fetch(:whitespace), text: " "
    )
    with_trivia = first.with_leading([whitespace])
    with_trailing = first.with_trailing([whitespace])
    without_middle = expression.remove_child(1)
    restored_expression = without_middle.children.fetch(0).children.fetch(0)
    restored = restored_expression.insert_child(1, expression.children.fetch(1))

    assert_equal " 1+2", with_trivia.to_source
    assert_equal "1 +2", with_trailing.to_source
    assert_equal "12", without_middle.to_source
    assert_equal "1+2", restored.to_source
  end

  def test_identity_rewriter_reuses_the_root_and_kind_dispatch_changes_tokens
    root = parse("1+2")
    identity = Ibex::Runtime::CST::SyntaxRewriter.new.rewrite(root)
    rewriter = Class.new(Ibex::Runtime::CST::SyntaxRewriter) do
      private

      def visit_NUM(token) # rubocop:disable Naming/MethodName
        return token.green unless token.text == "2"

        Ibex::Runtime::CST::GreenToken.new(
          kind: token.kind, text: "20", leading: token.green.leading, trailing: token.green.trailing,
          flags: token.green.flags, expected_kind: token.green.expected_kind
        )
      end
    end.new

    assert_same root, identity
    assert_equal "1+20", rewriter.rewrite(root).to_source
  end

  def test_editor_applies_independent_replacements_and_outer_edits_win
    root = parse("1+2")
    first, _plus, second = root.tokens
    editor = Ibex::Runtime::CST::SyntaxEditor.new(root)
    editor.replace(first, token_like(first, "10"))
    editor.replace(second, token_like(second, "20"))

    assert_equal "10+20", editor.apply.to_source

    expression = root.children.fetch(0).children.fetch(0)
    outer = Ibex::Runtime::CST::GreenNode.new(kind: expression.kind, children: [])
    outer_editor = Ibex::Runtime::CST::SyntaxEditor.new(root)
    outer_editor.replace(expression, outer)
    outer_editor.replace(first, token_like(first, "ignored"))

    assert_equal "", outer_editor.apply.children.fetch(0).children.fetch(0).to_source
  end

  def test_editor_rejects_conflicting_replacements_for_one_occurrence
    root = parse("1+2")
    first = root.first_token
    editor = Ibex::Runtime::CST::SyntaxEditor.new(root)
    editor.replace(first, token_like(first, "10"))

    assert_raises(Ibex::Runtime::CST::EditConflictError) do
      editor.replace(first, token_like(first, "11"))
    end
  end

  def test_annotation_is_path_copied_without_leaking_between_shared_occurrences # rubocop:disable Metrics/AbcSize
    root = parse("1+1")
    expression = root.children.fetch(0).children.fetch(0)
    first_term, second_term = expression.child_nodes

    assert_same first_term.green, second_term.green

    annotation = Ibex::Runtime::CST::SyntaxAnnotation.new
    edited = first_term.annotate(annotation)
    edited_terms = edited.children.fetch(0).children.fetch(0).child_nodes

    assert_equal [edited_terms.fetch(0)], edited.annotated(annotation).to_a
    assert_empty edited_terms.fetch(1).green.annotations
    assert_empty root.annotated(annotation).to_a
    assert edited_terms.fetch(0).green.flags.anybits?(Ibex::Runtime::CST::Flags::HAS_ANNOTATION)
    shareable = TestRuntimeCapabilities.ractor_shareable?(edited.green)
    assert shareable unless shareable.nil?

    cache = Ibex::Runtime::CST::NodeCache.new
    duplicate = Ibex::Runtime::CST::GreenNode.new(
      kind: edited_terms.fetch(0).kind, children: edited_terms.fetch(0).green.children,
      annotations: [annotation]
    )
    refute_same cache.intern_node(edited_terms.fetch(0).green), cache.intern_node(duplicate)
  end

  def test_diff_edits_reconstruct_the_new_source
    old_root = parse("1 + 2")
    new_root = old_root.first_token.with_text("100")
    edits = Ibex::Runtime::CST::Diff.text_edits(old_root, new_root)

    assert_equal new_root.to_source, old_root.source_text.apply(edits).text
    assert_equal 1, edits.length
    assert_equal [1, 0, "00"], edits.map { |edit| [edit.start, edit.delete_length, edit.insert_text] }.fetch(0)
  end

  private

  def parser_class
    @parser_class ||= begin
      ast = Ibex::Frontend::Parser.new(SOURCE, file: "editing.y").parse
      grammar = Ibex::Normalizer.new(ast).normalize
      automaton = Ibex::LALR::Builder.new(grammar).build
      namespace = Module.new
      namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "editing_parser.rb")
      namespace.const_get(:EditingParser)
    end
  end

  def parse(source)
    parser_class.new.parse_with_syntax(source).syntax_root
  end

  def token_like(token, text)
    Ibex::Runtime::CST::GreenToken.new(
      kind: token.kind, text: text, leading: token.green.leading, trailing: token.green.trailing,
      flags: token.green.flags, expected_kind: token.green.expected_kind
    )
  end

  def changed_green_count(old_green, new_green)
    return 0 if old_green.equal?(new_green)
    return 1 unless old_green.is_a?(Ibex::Runtime::CST::GreenNode) &&
                    new_green.is_a?(Ibex::Runtime::CST::GreenNode)

    1 + old_green.children.each_index.sum do |index|
      changed_green_count(old_green.children.fetch(index), new_green.children.fetch(index))
    end
  end

  def occurrence_depth(element)
    depth = 1
    parent = element.parent
    while parent
      depth += 1
      parent = parent.parent
    end
    depth
  end
end
