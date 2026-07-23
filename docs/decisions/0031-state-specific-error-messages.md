# ADR 0031: State-specific syntax error messages

- Status: Accepted
- Date: 2026-07-23

## Context

The structured runtime error contract can report the current LR state, token,
expected tokens, location, source line, caret, and spelling suggestions.
Applications still need a stable place to write domain-specific explanations
without overriding `on_error` or editing generated Ruby.

LR state numbers are useful identifiers for a fixed automaton, but they are not
semantic names. Grammar edits, algorithm changes, and generator upgrades can
renumber or remove them. The update workflow must make that instability visible
instead of silently discarding human-written messages.

## Decision

Ibex defines the UTF-8, line-oriented `ibex-messages v1` format:

```text
# ibex-messages v1

state 4
# expected: "(", INT
| An expression must start here.
| Use an integer or an opening parenthesis.
end

removed 9
| This text is retained for review after state 9 disappeared.
end
```

Blank lines and lines whose first non-whitespace character is `#` are comments
outside message text. Message lines start with `|`; one optional space after it
is structural and is not part of the message. Multiple lines are joined with
newlines. Within message lines, `\\`, `\n`, `\t`, and `\r` are the only
escapes. A `#`, `state`, `removed`, `end`, or `|` intended as message text is
written normally after the `|` prefix. Malformed directives, escapes,
unterminated entries, duplicate numeric states, and invalid UTF-8 receive
file/line/column diagnostics.

`ibex errors --update[=FILE] grammar.y` builds the selected automaton and writes
the file, defaulting to `grammar.messages`. Active syntax-error states are
ordered numerically. Existing message bodies are retained by numeric state;
states outside the new error-state set move to a deterministic `removed`
section instead of being deleted. A removed state that reappears becomes active
again with its retained text. The updater rewrites structural comments and
layout canonically; only decoded message bodies are preservation boundaries.

For this MVP, a syntax error state is one whose resolved explicit action or
default action is absent or `error` for at least one known grammar terminal
other than the synthetic recovery token. Unknown external token ids do not make
every LR state appear in the file. Generated `# expected:` comments are
informational and use display names where declared.

The update command accepts grammar source, Grammar IR v1, or Automaton IR v1.
Grammar source and Grammar IR build the requested algorithm; Automaton IR uses
its stored algorithm and states, and therefore rejects an explicit algorithm override. Updates use a same-directory temporary
file and atomic rename so an interrupted write does not truncate reviewed messages. Existing permissions are preserved; a new
file uses the process umask. Updating through a symlink keeps the link and atomically replaces its target. The `errors` subcommand is recognized only
when `errors` is the first argument, keeping ordinary option parsing separate
from subcommand options.

Normal Ruby generation accepts `--messages=FILE`. Active entries that are not
in the current syntax-error state set are rejected with a positioned diagnostic
and an instruction to run the updater; `removed` entries are ignored. The
decoded non-empty messages are embedded as an integer-to-string map in
`PARSER_TABLES[:error_messages]`. Plain, compact, runtime-requiring, and
embedded output use the same map.
Input, message, parser, signature, report, and visualization paths are checked for collisions before generation writes anything.
The check resolves symlinks and existing inode identity, so alternate spellings and hard links cannot overwrite an input or
another output.

The runtime treats `:error_messages` as an optional parser-table field. At a
matching state, the default `ParseError` diagnostic uses the custom text in
place of its generic unexpected-token sentence while retaining token, value,
expected-token, state, suggestion, and location attributes and appending the
existing source line and caret. Message text is not interpolated. Old parser
tables continue to use the generic diagnostic, and old runtimes ignore the
additive table key, so parser-table format version 1 does not change.

## Stability boundary

- The text syntax identified by `ibex-messages v1` is stable.
- Numeric state assignments are stable only for the same grammar, algorithm,
  relevant generator options, and Ibex implementation version.
- `--update` is a mechanical preservation aid, not proof that a retained
  message still describes the same language context. Generated expected-token
  comments and the `removed` section make review explicit after changes.
- State fingerprints, example error sentences, message interpolation, and
  locale selection are outside this MVP.

## Consequences

- Applications can maintain useful syntax diagnostics outside generated code
  without losing structured runtime data.
- Source and resumable IR pipelines produce the same message inventory and
  generated Ruby for the same automaton.
- A grammar or algorithm change requires running the updater and reviewing
  retained and removed entries before regeneration.
