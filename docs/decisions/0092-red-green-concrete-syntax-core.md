# ADR 0092: Introduce the Red/Green concrete syntax core

- Status: Proposed
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

## Consequences

- Green subtrees can be interned, serialized, edited by path copying, and shared
  between parse sessions without carrying source or semantic state.
- Red objects provide parent and absolute-offset navigation without weakening
  Green shareability.
- Regenerating a CST parser opts into the new root and pure-syntax child model;
  compatibility behavior and migration guidance are recorded separately.
- Ruby versions without `Data` remain supported by equivalent frozen classes.
