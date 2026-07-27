# ADR 0080: Store compact parser actions as integer codes

- Status: Accepted
- Date: 2026-07-27

## Context

Compact action tables previously emitted one Ruby array for every occupied
cell, such as `[:shift, 12]` or `[:reduce, 34]`. Public grammars contain many
repeated actions, so those literals dominated the generated table text and
created objects that the direct compact driver immediately decomposed again.
The generic runtime and table inspection API still require the compatible
array-shaped actions.

## Decision

`Ibex::Tables::CompactActions` stores occupied cells with a versioned internal
integer encoding:

- `0` is accept;
- `1` is error;
- even codes from `2` encode shifts; and
- odd codes from `3` encode reductions.

The class retains the row-displacement offsets and checks from
`Tables::Compact`. Its `codes` reader exposes the frozen hot representation to
the direct compact driver. Its inherited `lookup` and `row` surfaces use a
deduplicated, frozen decoded action array so generic parsing and table
inspection retain their existing shape.

Compact generation emits integer action codes and a parallel integer encoding
of default actions. Plain generation continues to emit ordinary row hashes and
array actions. The parser-table marker introduced by ADR 0079 admits only an
exact `CompactActions` action table and an exact `Compact` goto table to the
direct driver.

## Consequences

- The hot driver branches on integers without allocating or unpacking action
  arrays.
- Generated public parsers contain substantially less repeated action text.
- Generic and observable runtime modes still receive `[:shift, state]`,
  `[:reduce, production]`, `[:accept]`, and `[:error]`.
- The standalone runtime gem must ship both compact table classes.
- The encoding is internal to parser-table format v4 and is covered by
  round-trip, generated-parser, embedded-runtime, and packaging tests.
