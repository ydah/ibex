# ADR 0024: Keep direct IELR as an opt-in construction strategy

- Status: Accepted for experimental implementation; default adoption remains held
- Date: 2026-08-11

## Context

The existing IELR partition strategy constructs canonical LR(1) first and then
merges compatible states. That path is conservative and is retained as the
default. A direct implementation is useful when canonical state construction
is the dominant cost, but it carries a larger proof and maintenance surface.

## Decision

Implement direct IELR as `Builder`'s explicit `ielr_strategy: :direct` and as
the CLI option `--ielr-strategy=direct`. The direct pipeline is built from
LR(0), goto-follow closures, lane annotations, split-stability checks, state
splitting, and a second item-level lookahead propagation pass. It emits the
same Automaton IR consumed by all other algorithms.

Keep `:partition` as the default IELR strategy. Do not claim that direct IELR
is globally state-minimal, do not change public state-number baselines, and do
not enable unreachable-state compaction by default. The direct decision dossier
remains a release and evidence gate; an opt-in implementation is not evidence
that the gate has been satisfied.

## Consequences

- Direct construction can be exercised and profiled without changing existing
  parser output or release defaults.
- The implementation records phase metrics and offers bounded diagnostic
  reports, which makes future independent review possible.
- The direct path must retain adversarial fixtures, gallery regression tests,
  RBS, and static-quality checks as part of its maintenance budget.
- A future default change requires new real-workload measurements, an
  independent adequacy review, and a separately updated decision record.

## Provenance constraint

The implementation is derived from the published IELR paper and local parser
specifications only. GPL implementation sources are not inspected, translated,
or used as design input.
