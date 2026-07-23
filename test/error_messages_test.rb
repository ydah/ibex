# frozen_string_literal: true

require_relative "test_helper"

class ErrorMessagesTest < Minitest::Test
  def test_parses_utf8_multiline_comments_and_escapes
    document = Ibex::ErrorMessages.parse(<<~'MESSAGES', file: "grammar.messages")
      # ibex-messages v1
      # This comment is not part of the message.

      state 0
      # State-local comments are also ignored.
      | 日本語のエラー
      | path C:\\tmp\tvalue
      | # this is message text
      end

      removed 9
      | old\nmessage
      end
    MESSAGES

    active, removed = document.entries
    assert_equal [0, :active, "日本語のエラー\npath C:\\tmp\tvalue\n# this is message text"],
                 [active.state, active.status, active.message]
    assert_equal [9, :removed, "old\nmessage"], [removed.state, removed.status, removed.message]
  end

  def test_update_preserves_messages_and_moves_disappeared_states
    automaton = build_automaton
    active_state = Ibex::ErrorMessages.error_states(automaton).first.id
    existing = Ibex::ErrorMessages.parse(<<~MESSAGES, file: "grammar.messages")
      # ibex-messages v1
      state #{active_state}
      | Keep this message.
      end
      state 999
      | This state disappeared.
      end
    MESSAGES

    rendered = Ibex::ErrorMessages.render(automaton, existing: existing)
    updated = Ibex::ErrorMessages.parse(rendered, file: "grammar.messages")
    kept = updated.entries.find { |entry| entry.state == active_state }
    disappeared = updated.entries.find { |entry| entry.state == 999 }

    assert_equal :active, kept.status
    assert_equal "Keep this message.", kept.message
    assert_equal :removed, disappeared.status
    assert_equal "This state disappeared.", disappeared.message
    assert_equal updated.entries.sort_by { |entry| [entry.status == :removed ? 1 : 0, entry.state] },
                 updated.entries
    assert_includes rendered, "# expected:"
  end

  def test_rejects_malformed_duplicate_escape_and_invalid_utf8_with_positions
    duplicate = <<~MESSAGES
      # ibex-messages v1
      state 0
      end
      removed 0
      end
    MESSAGES
    error = assert_raises(Ibex::Error) { Ibex::ErrorMessages.parse(duplicate, file: "duplicate.messages") }
    assert_equal "duplicate.messages:4:1: duplicate state 0; first declared at line 2", error.message

    escaped = "# ibex-messages v1\nstate 0\n| bad\\q\nend\n"
    error = assert_raises(Ibex::Error) { Ibex::ErrorMessages.parse(escaped, file: "escape.messages") }
    assert_equal "escape.messages:3:6: unknown escape \\q", error.message

    malformed = "# ibex-messages v1\nstate nope\n"
    error = assert_raises(Ibex::Error) { Ibex::ErrorMessages.parse(malformed, file: "malformed.messages") }
    assert_equal "malformed.messages:2:1: expected `state N`, `removed N`, a comment, or a blank line", error.message

    invalid = "# ibex-messages v1\n".b << "\xFF"
    error = assert_raises(Ibex::Error) { Ibex::ErrorMessages.parse(invalid, file: "encoding.messages") }
    assert_equal "encoding.messages:1:1: messages file must be valid UTF-8", error.message
  end

  def test_messages_for_rejects_unknown_active_states_but_ignores_removed_states
    automaton = build_automaton
    removed_only = Ibex::ErrorMessages.parse(<<~MESSAGES, file: "grammar.messages")
      # ibex-messages v1
      removed 1000
      | archived message
      end
    MESSAGES
    assert_empty Ibex::ErrorMessages.messages_for(removed_only, automaton, file: "grammar.messages")

    document = Ibex::ErrorMessages.parse(<<~MESSAGES, file: "grammar.messages")
      # ibex-messages v1
      state 999
      | stale active message
      end
      removed 1000
      | archived message
      end
    MESSAGES

    error = assert_raises(Ibex::Error) do
      Ibex::ErrorMessages.messages_for(document, automaton, file: "grammar.messages")
    end
    assert_equal(
      "grammar.messages:2:1: unknown error state 999 for current automaton; run `ibex errors --update`",
      error.message
    )
  end

  private

  def build_automaton
    source = "class MessageParser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end
end
