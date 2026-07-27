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
through v5 retain their existing execution and CST behavior. Grammar IR remains
v2.

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

The implementation uses table format v6 while retaining readers for formats
v1–v5 and Grammar IR v2. Green constructors verify binary source widths,
aggregate flags, descendant counts, equality, interning, frozen state, and
Ractor shareability. Red tests cover lazy parent/index/offset navigation and
multiple occurrences of one interned Green value. The P0 baseline remains
versioned under `benchmark/results/cst/`; incremental performance is recorded
by ADR 0098 rather than changing this core contract.

The final Ruby 4.0.0, arm64-darwin24 observation uses the same 25-terminal,
100-parse workload as P0. The Red/Green CST path measures 74.079 ms versus
40.294 ms without CST, a 1.838x ratio (+83.8%). It allocates 456,607 total
objects versus 327,201 without CST. Compared with the P0 legacy CST
observation, total allocations rise from 341,807 to 456,607 (+33.6%) rather
than falling by the provisional 30% target. Within the retained Red/Green tree,
52 Green occurrences use 6 distinct object identities, an 88.5% identity reuse
ratio.

The version-3 follow-up adds the P0-required recovery path. On the same Ruby
and platform, 100 recovery parses measure 7.402 ms/49,001 allocations without
CST, 8.156 ms/45,701 through the legacy CST, and 14.573 ms/64,401 through the
Red/Green CST. The normal path in that run is 65.324 ms with CST versus
39.746 ms without CST. This observation is stored as
`2026-07-28-red-green-recovery-ruby-4.0.0-arm64-darwin24.json`.

The provisional batch goals in design section 17 are therefore not met.
Identity interning is effective, but the new builder, fidelity metadata, and
Red/session surfaces outweigh it in the process-wide allocation probe. These
timings are local evidence rather than CI thresholds, and the feature remains
Preview. ADR 0098 separately records that conservative subtree reuse makes
Stage B 1.04–2.83x faster than Stage A and 1.66–4.48x faster than fresh syntax
sessions on the incremental workload. The versioned observations are
`2026-07-27-main-ruby-4.0.0-arm64-darwin24.json`,
`2026-07-27-red-green-ruby-4.0.0-arm64-darwin24.json`, and
`2026-07-27-blender-ruby-4.0.0-arm64-darwin24.json` under
`benchmark/results/cst/`.

## Gate 1 evidence

The legacy characterization suite records the normal root and final trivia,
terminal lexer values, action-bearing semantic overlay, pattern-matching keys,
lexical `Error`, repair `Missing`, and recovery `Error` shapes. The complete
method inventory and current replacements are published in
`docs/cst-migration.md`.

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
  compatibility behavior and migration guidance are recorded separately.
- Ruby versions without `Data` remain supported by equivalent frozen classes.
