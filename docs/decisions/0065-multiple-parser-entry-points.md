# ADR 0065: Multiple parser entry points

- Status: Accepted
- Date: 2026-07-26

## Context

A grammar library often needs to parse both a complete document and smaller syntactic units. Duplicating the grammar creates
drift, while changing the historical `start` and `do_parse` contracts would break compatible users. Sharing LALR states can
also introduce conflicts that neither entry has when constructed alone, so those effects must remain observable and avoidable.

## Decision

Extended `start` declarations accept an ordered, unique list of nonterminals. The first remains the primary `start`. Grammar IR
v2 adds optional `starts`; Automaton IR v2 adds optional `entry_states`. They are omitted for the historical one-entry shape.
Generated Ruby and RBS expose `parse_<name>` for every entry, and `do_parse` starts at the primary entry.

Shared construction seeds one augmented canonical item per entry, merges compatible cores, and attributes each retained conflict
to the entries that can reach its state. A conflict absent from every corresponding isolated automaton is marked `composite`.
The CLI's `--entry-isolation` option constructs each entry independently, applies normal conflict resolution and default
reductions, and concatenates the immutable state sets with deterministic offsets. It is rejected when loading Automaton IR
because that document already fixes its state topology.

## Consequences

- One generated parser can expose several explicit entry methods without changing `do_parse`.
- Reports and IR consumers can distinguish entry-local conflicts from conflicts caused by sharing.
- Isolation provides a deterministic escape hatch, but duplicates states and can enlarge generated tables.
- Multi-entry direct LALR construction uses the canonical-merge path until a separately verified multi-root propagation
  algorithm is adopted.
