# ADR 0089: Use signed compact action codes

- Status: Accepted
- Date: 2026-07-27

## Context

The compact parser decoded every shift and reduction from interleaved even and
odd integers. Each hot action therefore required an evenness test, subtraction,
and division by two. Profiles attributed a material part of small-parser time
to this dispatch, while the action kind and target can be represented directly
by the integer sign.

Generated parsers already in applications must continue to load against a
newer runtime. Their explicit action rows and default-reduction codes use the
previous parity encoding.

## Decision

New compact action tables encode zero as accept, positive integers as
`shift_state + 1`, minus one as error, and values at or below minus two as
`-(production_id + 2)`. Generated table metadata marks signed default actions.

The existing `CompactActions` constructor treats an omitted encoding as the
legacy parity form and normalizes its explicit codes at load time. The parser
converts a legacy default code only when an old table falls through to that
default. Public lookup still returns the established action tuples.

## Consequences

- New hot dispatch uses sign checks and addition/subtraction without division.
- Five-worker diagnostics across the three public runtime profiles reduced
  median reuse time by approximately three to five percent.
- Current generated parsers keep the same compatible inspection surface.
- Previously generated compact parsers remain loadable and correct, with a
  small compatibility cost on legacy default reductions.
- Zigzag encoding keeps signed generated table literals compact.
