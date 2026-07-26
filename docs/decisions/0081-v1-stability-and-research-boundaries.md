# ADR 0081: Freeze the stable core and hold the v1 release

- Status: Accepted
- Date: 2026-07-26

## Context

Phase 18 is a stabilization and promotion audit, not another feature phase.
The outcome KPIs now have concrete evidence: three public-gem migrations, a
501-production scale build, ten error snapshots, external performance
comparisons, whole-library types, and the compatibility suite.

Behavioral migration and scale pass. External generator and generated-parser
performance are slower than racc in every measured project. The ten error
cases also lack independent third-party review. Treating implementation
completeness as release readiness would override the outcome-based design.

The maturity checklist additionally requires two released versions without a
specification change. The extended grammar family, IELR, and repair work have
not accumulated that field period.

## Decision

The v1.0 decision is **hold**. No new feature work enters the release branch
until the performance and independent-review gates pass.

The compatible grammar/runtime, direct LALR, and published core IR/report
contracts are stable. Extended grammar and tooling surfaces remain preview.
IELR passes its correctness/state-bound spike but remains preview. Bounded
repair passes SP-4 but remains experimental.

GLR and incremental parsing are no-go for this release line because their
required delayed-action and edit-reuse spikes did not meet an exit criterion;
they are not partially implemented. Counterexample/ambiguity analysis and
watch-mode full reparsing are the supported alternatives.

Core Grammar and Automaton IR required fields and meanings are frozen. Future
experimental `x-` data is outside that freeze, but the current closed schemas
continue to reject unknown fields. Any experimental envelope starts in a new
additive schema version rather than weakening existing validation.

Deprecation requires a warning for two minor releases and an autocorrect
migration before removal.

## Consequences

- The repository has a complete stabilization decision without claiming an
  unearned v1.0 release.
- Preview and experimental code may ship in prereleases under explicit support
  boundaries.
- Performance work is evaluated against the same three public workloads, not
  only an internal microbenchmark.
- Independent review remains an external release action and is never replaced
  by a second maintainer-authored judgment.
- GLR and incremental work require a new ADR with new measured spike evidence
  before implementation restarts.

