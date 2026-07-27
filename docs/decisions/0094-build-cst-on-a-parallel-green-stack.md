# ADR 0094: Build CSTs on a parallel Green stack

- Status: Accepted
- Date: 2026-07-27

## Context

ADR 0065 made the original CST action-sensitive: actionless reductions created
nodes, while action-bearing reductions supplied semantic values to their
parents. A Green tree cannot be both purely syntactic and preserve those mixed
children. Error recovery also pops parser states, so an unsynchronized syntax
stack would lose already consumed bytes.

## Decision

Every format-v6 `pragma cst` parser maintains one Green entry per semantic stack
entry. A terminal shift pushes a Green token and every reduction replaces its
physical RHS entries with a Green node. Semantic actions continue to operate
only on the existing value and location stacks.

Recovery follows the same stack mutations:

- yacc recovery wraps popped Green entries in `error_node`;
- repair insertion pushes a zero-width `missing_token`;
- repair replacement and lexical failure carry error flags;
- panic-discarded tokens become `skipped_tokens` trivia;
- an unrecoverable parse returns a `synthetic_root`;
- early acceptance marks `INCOMPLETE_INPUT`.

A successful result is a synthetic `source_file` whose children are the chosen
start node and an explicit EOF token. `parse_with_syntax` returns
`ParseResult(value:, syntax_root:, diagnostics:)`; ordinary `parse`, `do_parse`,
and `yyparse` retain their semantic return contracts.

The opt-in boundary is parser-table regeneration. Format v6 embeds structured
`cst` metadata and selects the Green path. Formats v1 through v5 retain the
legacy CST implementation for one compatibility series.

## Compatibility

Two observable changes apply only to regenerated CST parsers:

1. action-bearing children are syntax nodes instead of semantic values;
2. the syntax-aware root is `source_file`, not the start node.

The semantic value remains `ParseResult#value`. The start node is
`ParseResult#syntax_root.children[0]`. The complete migration is documented in
`docs/cst-migration.md`.

## Acceptance evidence

The parallel Green stack is exercised across ordinary shifts/reductions,
multiple start entries, lexical failure, yacc pop and panic discard, bounded
repair insertion/replacement, unrecoverable synthetic roots, and early
acceptance. A format-v5 regression test continues through the legacy path.
Action-bearing grammar tests confirm semantic values stay on the value stack
while syntax children remain nodes.

## Consequences

- Syntax shape no longer depends on whether a production has a Ruby action.
- Green values never contain semantic values or absolute locations and remain
  Ractor-shareable.
- Parser recovery, repair, lexer failure, and early acceptance all preserve the
  consumed-input fidelity invariant.
