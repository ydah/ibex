# ADR 0081: Pack compact production metadata and borrow proven-safe values

- Status: Accepted
- Date: 2026-07-27

## Context

The fixed public-grammar profiles showed two related costs after direct compact
dispatch was enabled. Generated parsers repeated `lhs`, `length`, action ABI
markers, and long action method names in one Hash literal per production.
Every values-only semantic reduction also copied its reduction-values Array so
that a hook installed by the action could still observe the pre-action
container. That copy is required when action code can mutate or retain `val`,
but most public actions only read indexed elements or destructure the Array.

Removing the copy for every action would break the documented dynamic-hook
boundary. Emitting only primitive production arrays without a compatible
Array-of-Hash surface would break generic parsing, table validation, and
inspection.

## Decision

Compact generation emits `Ibex::Tables::CompactProductions`. It stores `lhs`,
length, action Symbol, and ABI flags in parallel frozen arrays, then exposes
frozen decoded Hash entries through its Array-compatible surface. Sparse CST,
context, and named-location metadata remains attached to the corresponding
decoded entry. The direct compact driver reads the parallel arrays rather than
the compatibility Hashes and expands the common zero-to-four-symbol stack
reductions without a per-symbol loop. Plain-table generation keeps the
existing literals.

The generated-action ABI scanner first recognizes the common single-result
form containing only numeric `val[n]` reads without loading a Ruby parser. For
other forms it parses rewritten semantic action code with Ripper. It marks a
values-only action `borrowed_values_action` only when every reference to `val`
is either an indexed read or the right-hand side of parallel assignment.
Assignment through `val`, method calls on it, passing it as an argument,
returning it, and syntax that cannot be parsed all remain unmarked.

The direct compact driver admits only an exact `CompactProductions` instance
whose action entries are all values-only. A marked action and a hook installed
by that action share the one unchanged reduction-values Array. An unmarked
action retains the independent pre-action hook snapshot.

## Consequences

- Public generated-parser sizes fell from 18,389 to 16,822 bytes for Namae,
  19,014 to 17,716 for BCDice, and 31,372 to 28,452 for Nokogiri CSS.
- Proven-safe public actions avoid one Array allocation per semantic
  reduction; unsafe and dynamically opaque actions retain the prior behavior.
- Five-worker diagnostics across the three public profiles reduced median
  reuse time by approximately four to five percent after direct column reads
  replaced compatibility-Hash reads.
- Generic runtime modes and table consumers still see the established
  production Hash keys and action markers.
- The standalone runtime gem and embedded output include the compact
  production class.
- New ways of exposing `val` must remain conservative until the scanner has a
  syntax-specific proof that the container cannot be changed or retained.
