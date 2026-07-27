# frozen_string_literal: true

require_relative "../test_helper"

class CSTRedTest < Minitest::Test
  def test_children_are_lazy_memoized_and_offsets_are_contiguous
    root = syntax_root
    expression = root.child_at(0)

    assert_same expression, root.child_at(0)
    assert_instance_of Ibex::Runtime::CST::SyntaxNode, expression
    assert_equal [0, 2, 3], expression.children.map(&:offset)
    assert_equal [0...2, 2...3, 3...5], expression.children.map(&:full_span)
    assert_equal " 1+ 2\n".b, root.to_source
  end

  def test_spans_locations_and_trivia_ownership_use_byte_offsets
    root = syntax_root
    first = root.first_token
    eof = root.last_token

    assert_equal 0...2, first.full_span
    assert_equal 1...2, first.span
    assert_equal first, root.token_at(0)
    assert_equal eof, root.token_at(5)
    assert_equal [1, 2], root.source_text.position(1)
    assert_equal 1, first.location.line
    assert_equal 2, first.location.column
  end

  def test_navigation_search_errors_and_covering
    root = syntax_root
    expression = root.child_at(0)
    middle = expression.child_at(1)

    assert_equal expression, middle.parent
    assert_equal expression.child_at(0), middle.prev_sibling
    assert_equal expression.child_at(2), middle.next_sibling
    assert_equal expression, root.covering(1...5)
    assert_equal middle, root.covering(2...3)
    assert_equal [middle], root.find(kind: 3).to_a
    assert_empty root.each_error.to_a
  end

  def test_walk_and_cursor_have_deterministic_enter_leave_order
    root = syntax_root
    events = []
    root.walk { |event, element| events << [event, element.kind] }

    assert_equal(
      [
        [:enter, kind(:source_file)], [:enter, 4],
        [:enter, 2], [:leave, 2], [:enter, 3], [:leave, 3],
        [:enter, 2], [:leave, 2], [:leave, 4],
        [:enter, 0], [:leave, 0], [:leave, kind(:source_file)]
      ],
      events
    )

    cursor = root.cursor
    assert cursor.goto_first_child
    assert_equal 4, cursor.kind
    assert cursor.goto_first_child
    assert_equal 2, cursor.kind
    assert cursor.goto_next_sibling
    assert_equal 3, cursor.kind
    assert cursor.goto_parent
    assert_equal 4, cursor.kind
  end

  def test_drop_policy_rejects_coordinate_apis
    root = syntax_root(trivia_policy: :drop)

    assert_raises(Ibex::Runtime::CST::TriviaDroppedError) { root.span }
    assert_raises(Ibex::Runtime::CST::TriviaDroppedError) { root.token_at(0) }
    assert_equal " 1+ 2\n".b, root.to_source
  end

  private

  def syntax_root(trivia_policy: :leading)
    first = green_token(2, "1", leading: " ")
    plus = green_token(3, "+")
    second = green_token(2, "2", leading: " ")
    expression = Ibex::Runtime::CST::GreenNode.new(kind: 4, children: [first, plus, second])
    eof = green_token(0, "", leading: "\n")
    green = Ibex::Runtime::CST::GreenNode.new(
      kind: kind(:source_file), children: [expression, eof],
      flags: Ibex::Runtime::CST::Flags::SYNTHETIC
    )
    source = Ibex::Runtime::CST::SourceText.new(green.to_source, file: "red.txt")
    Ibex::Runtime::CST::SyntaxNode.new(
      green: green, kinds: kinds, trivia_policy: trivia_policy, source_text: source
    )
  end

  def green_token(token_kind, text, leading: "")
    trivia = if leading.empty?
               []
             else
               [Ibex::Runtime::CST::GreenTrivia.new(kind: kind(:whitespace), text: leading)]
             end
    Ibex::Runtime::CST::GreenToken.new(kind: token_kind, text: text, leading: trivia)
  end

  def kind_metadata
    @kind_metadata ||= begin
      source = <<~GRAMMAR
        class RedParser
        pragma cst
        token NUM PLUS
        rule
        expression: NUM PLUS NUM
        end
      GRAMMAR
      ast = Ibex::Frontend::Parser.new(source, file: "red.y").parse
      grammar = Ibex::Normalizer.new(ast).normalize
      Ibex::Codegen::CSTMetadata.new(grammar).build
    end
  end

  def kinds
    @kinds ||= Ibex::Runtime::CST::Kind.new(kind_metadata.fetch(:kinds))
  end

  def kind(name)
    kinds.fetch(name)
  end
end
