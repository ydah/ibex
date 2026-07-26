# ADR 0072: Error-tolerant concrete trees

- Status: Accepted
- Date: 2026-07-26

## Context

Automatic trees are useful only if their shape, source locations, trivia, and
failure behavior are stable. Reusing application semantic values as a tree
would lose terminal identity and would make bounded repair invisible.
Conversely, wrapping every value in the compatible runtime would change action
contracts and penalize grammars that did not request trees.

## Decision

`pragma cst` is an explicit extended-root capability. It records `cst: true` in
Grammar IR v2 and adds CST metadata only to that parser's generated tables.
Productions without semantic actions reduce to immutable
`Ibex::Runtime::CST::Node` values. Their terminal occurrences are immutable
`Token` values; an explicit semantic action continues to own its result.

The runtime records parser and lexer failures as `Error` terminals and bounded
repair insertions as `Missing` terminals. If recovery cannot reach acceptance,
the parser returns a synthetic start node instead of `nil` or the default
syntax exception. A generated lexer similarly turns an unmatched input span
into a lexical error tree. This guarantee applies to the default CST runtime;
an application override that deliberately raises from a hook still owns that
exception.

Generated lexers implement two explicit trivia policies. `attach`, the
default, associates skipped matches with the next terminal and retains final
skips on the root. `drop` discards them. The generator option is
`--cst-trivia=attach|drop`; handwritten lexers can supply a compatible
`leading_trivia` location field but are not required to do so.

## Consequences

- Parsers without `pragma cst` keep their previous value stack and table shape.
- CST locations use the existing terminal location objects and synthesized
  `LocationSpan` values.
- Concrete nodes support `deconstruct` and `deconstruct_keys`, so callers can
  use Ruby pattern matching without a separate adapter.
- The immutable tree is a prerequisite for the GLR and incremental-parser
  research spikes, but does not itself promise either feature.
