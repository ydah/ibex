# ADR 0093: Own trivia on Green tokens

- Status: Accepted
- Date: 2026-07-27

## Context

Lossless Red/Green trees need a deterministic owner for lexer text that the
grammar skips. Making trivia ordinary LR symbols would change production
arity, semantic action positions, lowered inline plans, and `@node` field
slots. Keeping absolute locations on trivia would also make Green values
position-dependent.

The design document proposed `leading`, `balanced`, and `drop` policies. Its
provisional table-format and ADR numbers predate parser-table format v5 and ADR
0091.

## Decision

Green tokens own immutable `GreenTrivia` values. Trivia stores an integer kind,
binary text, and derived width only.

- `leading` attaches skipped text to the next token. The historical `attach`
  spelling is accepted as an alias.
- `balanced` assigns text through the first newline to the preceding token and
  the remainder to the next token. Text before the first token remains leading.
- `drop` omits skipped text and disables coordinate and incremental APIs.

Generated lexers classify whitespace, newline-bearing text, line comments,
block comments, and otherwise use `custom_skip`. Recovery-only discarded input
uses `skipped_tokens`.

The EOF token owns final leading trivia, so every complete tree has one place
for trailing file text. Early `yyaccept` excludes the unshifted lookahead and
its trivia from the consumed prefix.

This metadata is emitted in parser-table format v6. Formats v1 through v5 keep
their previous trivia behavior.

## Acceptance evidence

Generated-lexer integration tests cover `leading`, `balanced`, the `attach`
alias, final EOF trivia, and early acceptance. Recovery tests retain popped and
discarded source. `to_source` property cases are byte exact for non-drop trees,
including invalid UTF-8 serialization fixtures. `drop` deterministically
raises for coordinates and incremental session creation.

## Consequences

- Physical production children remain aligned with lowered RHS positions and
  semantic action indices.
- Balanced ownership requires right-edge path copying when trivia is learned
  after a token has already been reduced.
- `to_source` is byte exact for `leading` and `balanced`; `drop` is the explicit
  fidelity exception.
