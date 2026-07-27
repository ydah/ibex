# ADR 0091: Materialize bounded dense rows for the direct parser

- Status: Accepted
- Date: 2026-07-27

## Context

The compact direct driver still performed displacement addition, ownership
checks, and legacy/signed selection for every LR action and goto. The three
fixed public grammars have small state-by-symbol products, so a flat decoded
row can remove those branches without enlarging generated source literals.

Unconditionally expanding a sparse grammar is unsafe. A grammar with many
states or a high numeric symbol id can make the dense product much larger than
its compact representation.

## Decision

New compact action and goto objects optionally materialize frozen flat rows
while decoding their packed generated literals. Generated source records the
row width, not the expanded values. The runtime enters a signed dense loop only
when both layouts are available; otherwise it falls back before committing an
action.

Dense action and goto layouts are independently limited to 1,000,000 cells.
Construction and packed loading both enforce the limit. The row-displacement
arrays and compatible `lookup`/`row` surface remain authoritative regardless
of whether the optional dense layout is present.

## Consequences

- Five-worker diagnostics reduced public reuse time by approximately one to
  two-and-a-half percent after legacy and sparse branches left the hot loop.
- Generated source grows only by the two width keywords and remains smaller
  than Racc for all three public profiles.
- Eligible small and medium grammars trade bounded load-time memory for fewer
  runtime branches.
- Large or unusually sparse grammars retain compact memory use and compatible
  behavior through the generic driver.
