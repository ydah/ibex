# ADR 0078: Accept user-code sections as compatible rule terminators

- Status: Accepted
- Date: 2026-07-26

## Context

The v1.0 migration KPI applies the public compatibility surface to maintained
third-party grammars rather than only repository fixtures. The Namae grammar
uses a form accepted by the public Racc command in which the first
`---- header`, `---- inner`, or `---- footer` marker terminates the `rule`
section without a preceding `end`.

Ibex previously required `end` unconditionally. It tokenized the user-code
section losslessly, but the generated frontend rejected that token while still
waiting for the terminator. Requiring a source-only rewrite would weaken the
replacement claim and create a difference unrelated to parser semantics.

## Decision

A root grammar may terminate its rule section in either of two ways:

1. `end`, followed by zero or more user-code sections; or
2. one or more user-code sections, where the first marker is the rule
   terminator.

End-of-file without either form remains an error, as does a rule section with
no rule definition. Fragments continue to require an explicit `end` and
continue to reject user-code sections.

The self-hosted grammar, its composition shadow grammar, and the bootstrap
parser implement the same choice. Lossless parsing and formatting retain the
source form; formatting does not insert an `end` that was absent.

## Consequences

- Maintained legacy grammars can be checked and generated without a
  compatibility-only edit.
- Explicit `end` remains the documented form for new grammars.
- The accepted alternative is structurally bounded by a user-code marker, so a
  truncated grammar ending at EOF is not silently accepted.
