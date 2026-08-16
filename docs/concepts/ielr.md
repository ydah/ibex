---
title: IELR(1) construction
description: The opt-in IELR construction strategies and their verification boundary.
---

# IELR(1) construction

Ibex exposes IELR(1) as an opt-in parser-construction algorithm. It keeps the
same Grammar IR, Automaton IR, conflict resolver, table generator, and runtime
as SLR, LALR, and canonical LR(1). The default remains the compatible LALR
path; selecting IELR does not change generated parser APIs.

## Strategies

`--algorithm=ielr` accepts two construction strategies:

- `partition` (the default) constructs canonical LR(1) states and partitions
  compatible isocores. It is the conservative reference strategy and remains
  the release baseline.
- `direct` starts with LR(0), computes LALR lookaheads and goto-follow
  relations, traces grammar-relative inadequacies, splits only affected
  isocores, and recalculates lookaheads on the split graph. It does not build a
  canonical collection in the normal construction path.

The direct strategy is deliberately not a claim of globally minimal state
count. Its benefit is bounded construction work and phase-level evidence, not
an unconditional reduction in the final table. `--remove-unreachable` is
available as an explicit post-resolution compaction; it is off by default so
state numbers used by diagnostics and generated artifacts remain stable.

```sh
ibex --algorithm=ielr --ielr-strategy=direct grammar.y
ibex --algorithm=ielr --ielr-report grammar.y
ibex --algorithm=ielr --ielr-strategy=direct --remove-unreachable grammar.y
```

`--ielr-report` is diagnostic-only. It constructs a canonical reference and
reports action differences; it must not be confused with the direct build
path. The report is useful for review and regression tests, but it is not a
proof that every viable prefix has a unique state correspondence.

## Construction phases

The direct path is organized as the following explicit boundaries:

1. `LR0Collection`, `LookaheadPropagation`, and `GotoFollows` build the LR(0)
   collection, direct reads, successor/internal/includes relations, and LALR
   lookaheads. `DirectLookaheads` remains the existing compatibility-path
   cross-check.
2. `IELR::Annotator` and `ItemLookaheads` classify conflicts and propagate
   annotations over predecessor lanes. `SplitStability` discards annotations
   whose resolved action cannot change under a split.
3. `IELR::StateSplitter` copies transition tables for incompatible isocores and
   preserves deterministic construction order.
4. `LookaheadPropagation` reruns item-level propagation over the split graph.
5. The existing `Builder` phase resolves conflicts and applies error/default
   reductions, preserving the common Automaton IR contract.

All lookahead sets are integer bitsets. `Analysis::Digraph` computes the
successor, always, and includes closures with an iterative worklist so deep
grammars do not depend on Ruby recursion depth.

## Metrics and reports

Profiled builds expose `ielr_annotations`, `ielr_annotated_states`,
`ielr_inadequacies`, `ielr_split_stable_discarded`, `ielr_lalr_states`,
`ielr_split_states`, `ielr_unreachable_removed`,
`ielr_remergeable_candidates`, and the existing partition counts. Use
`tool/construction_profile.rb --ielr-strategy=direct` to capture the direct
measurements. Wall-clock values remain observations, not release gates.

The phase implementation is covered by the paper-derived fixtures in
`test/fixtures/ielr` and the structural tests in
`test/lalr/ielr_direct_test.rb`. The direct strategy remains experimental
until representative real-workload evidence and an independent adequacy
review satisfy the direct-IELR decision dossier.

## Verification and limits

`GotoFollows#reduction_lookaheads` is cross-checked against the existing direct
item propagator. Paper fixtures cover split and no-split cases, and the
acceptance matrix checks direct IELR against LALR for the conflict examples.
The independent verifier still uses its canonical reference collection for
V1/V2; strict IELR verification additionally runs the bounded V9 acceptance
witness.

`Verify::ActionCorrespondence` and `LALR::InadequacyReport` are explicit
diagnostic tools. They compare resolved actions and preserve a bounded search
budget, but canonical-vs-target state pairing is not assumed to be a function.
`Verify::LanguageWitness` supplies the strict IELR V9 bounded acceptance
comparison; it reports token-level acceptance witnesses and fails closed when
its finite case budget is exhausted. It does not prove unbounded equivalence,
conflict preservation, or split correctness. Global minimum state merging and
remergeable state optimization are intentionally out of scope. Normal parser
construction never invokes these diagnostics. Existing canonical-core
verification remains the trusted boundary for release decisions.

The operational decision and provenance boundary are recorded in
[ADR 0024](../decisions/0024-direct-ielr-construction.md) and the
[direct-IELR dossier](../records/ielr/direct-ielr-decision.md).

The implementation is independently derived from the published IELR paper and
the repository's parser specifications. GNU Bison or another GPL
implementation is not a design input.
