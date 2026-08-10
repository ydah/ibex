# Direct IELR(1) implementation design

This document is the maintained implementation summary for the paper-derived
IELR(1) pipeline. The complete design definition and fixture tables are maintained alongside this public summary; this public copy records the
decisions that are part of the shipped implementation.

## Contract

Direct IELR starts from an LR(0) collection, computes DeRemer–Pennello
successor/internal/includes and goto-follow closures, annotates grammar-relative
inadequacies, splits incompatible isocores, and reruns item lookahead
propagation. Conflict resolution, error reductions, default reductions, and
Automaton IR serialization are shared with the existing builder. Canonical LR(1)
is not constructed on the normal direct path.

The implementation is divided into `LR0Collection`, `GotoFollows`,
`IELR::Annotator`, `IELR::StateSplitter`, and `LookaheadPropagation`.
Integer bitsets are used for terminal and kernel-item sets. `--remove-unreachable`
is an explicit, default-off post-resolution compaction because state numbers are
part of diagnostics and generated artifacts.

## Verification and limits

`GotoFollows#reduction_lookaheads` is cross-checked against the existing direct
item propagator. Paper fixtures cover the split and no-split cases, and the
acceptance matrix checks direct IELR against LALR for the four conflict examples.
The independent verifier still uses its canonical reference collection for V1/V2;
`Verify::ActionCorrespondence` and `LALR::InadequacyReport` are bounded diagnostic
tools, not a scale-independent proof. Global minimum state merging and remergeable
state optimization are intentionally out of scope.

## Operational decision

`ielr_strategy: :partition` remains the default. `:direct` is an experimental,
explicit strategy exposed by `--ielr-strategy=direct`; no state-count or release
readiness claim is made. The decision and provenance boundary are recorded in
[ADR 0024](decisions/0024-direct-ielr-construction.md) and the direct-IELR dossier.

The implementation is independently derived from the published IELR and
DeRemer–Pennello papers and repository parser specifications. GPL implementation
source is not a design input.
