# Conflict-explanation usefulness study

H004 separates reproducible machine evidence from subjective usefulness
review. The committed version-1 corpus contains four grammar shapes and five
conflicts:

- an ambiguous expression and dangling `else` shift/reduce conflict;
- an ambiguous reduce/reduce choice;
- two nonunifying reduce/reduce conflicts introduced by LALR context merging.

Each case binds its grammar bytes, Automaton IR digest, conflicting state items,
competing actions, resolution, and bounded witness. It also runs the existing
`fix` candidate search with fixed limits. Only the expression case currently
has a machine-verified proposal: declaring right associativity for `PLUS`
removes the conflict and finds no language or mapped-tree difference within the
recorded bounds. The other cases truthfully record `no_safe_proposal`; advice
that merely acknowledges a conflict or changes recovery is labeled as not a
verified repair.

Every witness records its typed search outcome, explored configuration count,
exhaustion flag, and token/configuration bounds. A configuration-budget
exhaustion is `inconclusive`; it is never relabeled as a nonunifying witness or
accepted into the fixed study capture.

Regenerate or verify the machine capture with:

```sh
bundle exec ruby tool/conflict_explanation_study.rb --write
bundle exec rake quality:conflict_explanations
```

The normative machine artifact is
[`study-v1.json`](../test/fixtures/conflict_explanations/study-v1.json),
validated by the closed
[`schema`](../schema/conflict-explanation-study-v1.schema.json). The capture
uses repository-owned grammars and never executes grammar actions. Search,
candidate, build, equivalence, and verifier limits are explicit; exhaustion is
not success. The detailed pre-implementation contract and kill conditions are
recorded in the [investigation](investigations/H004-conflict-explanation-study.md).

## Independent human gate

The machine capture proves reproducibility, not usefulness. Independent
reviewers must use the state/items and witness to identify the cause, then
choose an edit and explain whether the explanation and proposed repair helped.
The [record instructions](conflict-explanation-reviews/v1/records/README.md)
and [review schema](../schema/conflict-explanation-review-v1.schema.json)
preserve per-case rationales and reviewer disagreement.

The current subjective gate is **HOLD** with zero external records, as recorded
in the [status registry](conflict-explanation-review-status-v1.json). PASS
requires at least two distinct reviewers covering every case. A future PASS
must retain disagreement; it cannot replace individual answers with a majority
percentage. Until then no usefulness rate, comparative superiority, or general
conflict-repair claim is publishable.
