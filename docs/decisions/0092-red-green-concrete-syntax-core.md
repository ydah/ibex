# ADR 0092: Introduce the Red/Green concrete syntax core

- Status: Accepted
- Date: 2026-07-27

## Context

The existing `pragma cst` implementation stores absolute source locations and
semantic values in one immutable tree. That representation cannot safely share
subtrees across edits, and action-bearing productions leave semantic values
inside otherwise syntactic child arrays.

The Red/Green design was drafted when parser-table format v3 and ADR 0081 were
current. Implementation begins after format v5 and ADR 0091, so its provisional
numbers cannot be used literally.

## Decision

CST-aware parsers will use a position-independent Green tree and expose a lazy
Red navigation facade. Green values contain only integer kinds, source bytes,
owned trivia, child structure, flags, and derived widths. The public root is a
synthetic `source_file` containing the selected start node and EOF token.

Full fidelity means that `to_source` reconstructs every byte consumed by the
parser, including bytes retained during error recovery. Early acceptance marks
the root as incomplete and applies fidelity to the consumed prefix.

Kind ids begin with the existing grammar symbol ids (`$eof` 0 and `error` 1),
then deterministic named-node, trivia, and synthetic intervals. The generator
records the complete mapping and named-kind-to-nonterminal mapping.

The new CST metadata will be introduced in parser-table format v6. Formats v1
through v5 retain their existing non-CST execution behavior. Their CST shape
is not part of the selected v1 contract and now requires regeneration under
ADR 0099. Grammar IR remains v2.

The P0 characterization gate found that action-bearing reductions are exposed
inside an actionless parent as synthetic `CST::Token` values whose `symbol` is
the reduced nonterminal and whose `value` is the semantic result. The new tree
does not preserve that semantic overlay: the corresponding child is a syntax
node. This is the sole observed mixed-grammar C1 shape and must be called out in
the migration guide.

The Ruby 4.0 baseline with 25 terminals and 100 parses measured a 1.19x elapsed
ratio and 17.1% more allocated objects for the existing CST path. These values
are observations rather than release thresholds; the versioned artifact is
stored under `benchmark/results/cst/`.

## Acceptance evidence

The implementation uses table format v6 while retaining non-CST readers for
formats v1–v5 and Grammar IR v2. Green constructors verify binary source widths,
aggregate flags, descendant counts, equality, interning, frozen state, and
Ractor shareability. Red tests cover lazy parent/index/offset navigation and
multiple occurrences of one interned Green value. The P0 baseline remains
versioned under `benchmark/results/cst/`; incremental performance is recorded
by ADR 0098 rather than changing this core contract.

The initial Ruby 4.0.0, arm64-darwin24 observation used the same 25-terminal,
100-parse workload as P0. Before the construction hot-path follow-up, the
Red/Green CST path measured 74.079 ms versus 40.294 ms without CST, a 1.838x
ratio (+83.8%), and allocated 456,607 total objects versus 327,201 without CST.
This result identified repeated trivia filtering, construct-then-intern token
allocation, recursive source reconstruction, per-instance kind metadata, and
unbounded descendant hashing as the dominant avoidable costs.

The version-3 follow-up adds the P0-required recovery path. On the same Ruby
and platform, 100 recovery parses measure 7.402 ms/49,001 allocations without
CST, 8.156 ms/45,701 through the legacy CST, and 14.573 ms/64,401 through the
Red/Green CST. The normal path in that run is 65.324 ms with CST versus
39.746 ms without CST. This observation is stored as
`2026-07-28-red-green-recovery-ruby-4.0.0-arm64-darwin24.json`.

The version-4 follow-up measures five alternating-order runs of 2,000 parses
each and uses the median per-run ratio. The Red/Green path measures 982.630 ms
versus 747.147 ms without CST; the median ratio is 1.315 (+31.5%), satisfying
the provisional +35% batch target. Process-wide allocations are 6,092,001
versus 5,958,001 (+2.25%). The dedicated construction probe records 50 legacy
CST node/token constructions and 6 Red/Green constructions for the same tree,
an 88.0% reduction that exceeds the provisional 30% target. The retained tree
still has 52 occurrences backed by 6 distinct Green identities (88.5% reuse).
The recovery observation improves to a 1.545x Red/Green/plain ratio and remains
recorded as a diagnostic rather than a release threshold.

The version-5 current-only follow-up removes the obsolete CST measurements
without rewriting history. On the same workload, the Red/Green path measures a
median 937.871 ms versus 719.998 ms without CST; the median per-run ratio is
1.302 (+30.2%). Process-wide allocations are 6,088,001 versus 5,952,001
(+2.28%), and the fixed recovery ratio is 1.587. The six Green constructions
and 88.5% identity reuse remain unchanged. The artifact is
`2026-07-28-current-only-ruby-4.0.0-arm64-darwin24.json`.

The design-section-17 provisional batch goals are therefore met. Timings remain
local evidence rather than CI thresholds. ADR 0099 selects the batch CST as
Stable for the initial v1 contract using the initial-major evidence rule; the
incremental layer remains Experimental. ADR 0098 separately records that conservative subtree
reuse makes Stage B 1.04–2.83x faster than Stage A and 1.66–4.48x faster than
fresh syntax sessions on the incremental workload. The versioned observations are
`2026-07-27-main-ruby-4.0.0-arm64-darwin24.json`,
`2026-07-27-red-green-ruby-4.0.0-arm64-darwin24.json`, and
`2026-07-27-blender-ruby-4.0.0-arm64-darwin24.json`, plus the final
`2026-07-28-red-green-optimized-ruby-4.0.0-arm64-darwin24.json` and
`2026-07-28-current-only-ruby-4.0.0-arm64-darwin24.json`, under
`benchmark/results/cst/`.

## Gate 1 evidence

The pre-migration characterization evidence recorded the normal root and final trivia,
terminal lexer values, action-bearing semantic overlay, pattern-matching keys,
lexical `Error`, repair `Missing`, and recovery `Error` shapes. The complete
method inventory and current replacements are published in
`docs/cst-migration.md`. Current tests retain the pure-syntax characterization
and verify that obsolete CST tables are rejected before token consumption.

Only one mixed-production shape was observed: an action-bearing child appeared
as a semantic token in an otherwise syntactic parent. Gate 1 accepts the
pure-syntax C1 change and the `source_file` C2 root change, with parser-table
regeneration as the opt-in boundary. No value-overlay view is brought forward;
semantic consumers use the ordinary parse result and syntax consumers use the
Red tree.

## Consequences

- Green subtrees can be interned, serialized, edited by path copying, and shared
  between parse sessions without carrying source or semantic state.
- Red objects provide parent and absolute-offset navigation without weakening
  Green shareability.
- Regenerating a CST parser opts into the new root and pure-syntax child model;
  obsolete CST tables are rejected and migration guidance is recorded
  separately.
- Ruby versions without `Data` remain supported by equivalent frozen classes.
