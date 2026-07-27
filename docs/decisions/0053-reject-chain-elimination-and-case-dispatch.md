# 0053: Retain production identities and compact table dispatch

- Status: Accepted
- Date: 2026-07-26

## Context

The optimization experiment uses five isolated runs on one named environment,
reproduction on a second supported MRI, equal parser behavior digests, and
requires either a five-percent runtime improvement or ten-percent size
reduction without a five-percent regression in the other dimension. The
current generator already compiles semantic actions as methods, and the runtime
dispatches shift, reduce, accept, and error through one `case`. The remaining
generated-case candidate is therefore per-state parser-table lookup, not
replacement of Proc-based semantic actions.

Unit-production elimination has a different constraint. A reduction's production id is observable through `on_reduce`, JSON
tracing, coverage, the debugger, conflict explanations, source locations, and Automaton IR. Removing a unit production while
claiming compatible behavior would erase that event or require replaying a synthetic reduction with the same semantic and
location work.

## Evidence

`benchmark/optimization_candidates.rb` retains the compact action table for public table inspection, expected-token queries,
repair search, and debugging, then injects a nested state/token `case` only for the runtime lookup path. Every timing is collected
in a fresh Ruby process after 100 warmup parses. Source, Automaton IR, and runtime-result SHA-256 digests must match before a report
is emitted.

The committed revision `05dc61bdb5d0` produced:

| MRI | table median | case median | runtime improvement | generated size change | qualifies |
| --- | ---: | ---: | ---: | ---: | --- |
| 4.0.0 arm64-darwin24 | 1.884327 ms | 1.573629 ms | 16.489% | +198.170% | no |
| 3.4.9 arm64-darwin25 | 1.885949 ms | 1.593746 ms | 15.494% | +198.170% | no |

Both reports contain five observations per variant and equal source, Automaton, and result digests. They are stored under
`benchmark/results/optimization/`.

The representative grammar has 139 productions, including 45 unit productions: 39 actionless and six with actions. Even the
actionless reductions retain observable production identity and reduction hooks. Eliminating only those 39 would therefore
change the existing runtime-event, coverage, debug, and source-map contracts; replaying them preserves the work the optimization
is meant to remove. Rewriting production ids would additionally require a new Grammar/Automaton IR schema and migration.

## Decision

Do not add chain-rule elimination or generated per-state `case` dispatch.

The case candidate clears the runtime threshold on both MRIs but fails the other-dimension guard by nearly tripling generated
source. Keeping a second action representation would also create two dispatch sources that must remain equivalent.

Chain elimination is rejected at the compatibility boundary. Production reductions and their ids remain real parser operations.
A future proposal may restart only with a new observable-event and IR contract, not as a table-format optimization.

## Consequences

- Compact row-displacement tables remain the single default and inspection representation.
- Generated source stays small while semantic actions and action kinds retain their existing method/`case` dispatch.
- Production ids, hooks, source locations, tracing, coverage, and debugger steps remain aligned.
- The experiment is reproducible, but timing remains observational and is not added as a CI threshold.
