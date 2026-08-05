# IELR and multi-entry construction profiling

This document closes H005's profiling work without selecting or implementing a
new construction algorithm. The machine-readable authority is
[`construction-profile-v1.json`](../tool/profile/evidence/construction-profile-v1.json),
validated by
[`construction-profile-v1.schema.json`](../schema/construction-profile-v1.schema.json).
It is an `internal_local_observation`, not release or adoption evidence.

## Public profiler

Run the repository-owned and synthetic profiles with:

```sh
bundle exec ruby tool/construction_profile.rb \
  --wall-seconds=60 \
  --output=tool/profile/evidence/construction-profile-v1.json
bundle exec rake quality:construction_profile
```

Third-party observations require a full checkout that the existing public
workload manifest can verify. Each checkout must have the exact revision,
origin, clean status, grammar digest, and structural baseline:

```sh
bundle exec ruby tool/construction_profile.rb \
  --checkout=namae=/path/to/namae \
  --checkout=bcdice_command=/path/to/BCDice \
  --checkout=nokogiri_css=/path/to/nokogiri
```

Omitting a checkout records its exact registry metadata as `not_run`; it does
not silently profile a cached file or substitute a synthetic grammar.

The artifact separates reconstructible source provenance from host-bound
observations. `provenance.base_revision` is only the Git base: when capture is
dirty, every H005 contract path records its observed digest, base-object
digest, and `base` / `modified` / `untracked` state. The clean flag is derived
from the exact porcelain status; the status, bound-path set, implementation
subset, host observation, and measurement policy each have an integrity
digest. The evidence file is excluded from the source and implementation
digests, so no digest refers to the bytes that contain itself.

The quality gate reconstructs the base objects, requires the base to be an
ancestor of the checked revision, verifies current contract bytes against the
bound paths, and checks all derived digests and workload/run entry identities.
Ruby version and options, kernel, CPU, and other host fields remain explicitly
host-bound rather than cross-platform goldens, but their recorded values are
validated against `environment_observation_sha256` before that observation is
excluded from the deterministic structural comparison.

Every construction has an explicit wall-time limit. Exceeding it records the
resource and limit. `NoMemoryError` and `SystemStackError` are recorded as
resource exhaustion. Those results establish only that a bound was observed;
they are not negative proofs about the language or algorithm.

## Counting contract

The profiler records these structural quantities from the construction that
already exists:

| Field | Meaning |
| --- | --- |
| `lr0_states` | Distinct LR(0) cores materialized directly or represented by the canonical collection. |
| `lr0_items` | Core-item occurrences across those distinct cores. |
| `canonical_states` / `canonical_items` | Canonical LR(1) states and item triples, only when that collection completes. |
| `final_states` / `final_items` | States and core-item occurrences after merge or IELR partitioning. |
| `final_lookahead_items` | Lookahead memberships across final core items. |
| `propagation_edges` | Deduplicated direct-LALR lookahead propagation edges; canonical paths report `not_applicable`. |
| `ielr_initial_partitions` / `ielr_final_partitions` | Compatible partitions before and after transition refinement. |

`not_applicable` is reserved for metrics that the selected construction path
does not perform, such as canonical-state counts in direct LALR. A metric that
would apply but could not be collected because construction timed out or
failed is `not_measured`; failure never masquerades as algorithmic absence.

Elapsed seconds are retained only as host-bound observations. The schema fixes
`release_gate` to `false`, and the quality gate deliberately removes elapsed
values before comparing evidence. Ruby's live-slot counters are neither a
peak measurement nor reproducible retained-object accounting, so peak retained
objects are truthfully `not_measured`. The current builders also expose no
state budget or portable per-build heap limit; both omissions are explicit in
the evidence.

Profiling is opt-in through `Builder(profile: true)`. Ordinary generation does
not calculate the additional item/core summaries. Parser tables, conflicts,
generated source, runtime ABI, Grammar IR, and Automaton IR are unchanged.

## Current observations

Synthetic and real workloads are separate cohorts. All repository grammar
revisions and SHA-256 digests come from the public workload registry. The
multi-entry diagnostic is the existing representative matrix grammar at the
recorded exact revision, not a new language fixture.

| Workload | Class | LR(0) states/items | Direct propagation edges | Canonical LR(1) states/items | IELR partitions initial/final | Final states |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `gallery-calc` | repository synthetic | 15 / 76 | 99 | 27 / 674 | 15 / 15 | 15 |
| `gallery-json` | repository synthetic | 27 / 82 | 111 | 57 / 272 | 27 / 27 | 27 |
| `gallery-sql-lite` | repository synthetic | 26 / 53 | 55 | 26 / 115 | 26 / 26 | 26 |
| `matrix-multi-entry` | repository synthetic | 9 / 14 | n/a | 9 / 20 | 9 / 9 | 9 |
| `ibex-frontend` | repository real | 220 / 618 | 734 | 449 / 10,103 | 220 / 220 | 220 |

The table pairs direct-LALR edge counts with the canonical collection used by
current IELR. The multi-entry row reports the shared result; its committed run
records also contain isolated LALR and IELR. On this diagnostic all four
shared/isolated combinations retain 9 states, 14 final core items, and 20 final
lookahead memberships. That bounded synthetic equality is not evidence that a
direct multi-entry implementation lacks value on real grammars.

The three `public_real` identities—Namae, BCDice command, and Nokogiri CSS—are
recorded as `not_run` because no checkout satisfying the public manifest was
supplied for this evidence capture. They contribute no state, item, edge,
partition, failure, or timing observation. The only measured real workload is
the repository's production frontend; it has no unresolved conflict requiring
IELR, and current IELR partitions its 449 canonical states back to the same 220
final states as direct LALR.

## Decisions

Direct IELR is **NO-GO** under the current verifier and workload evidence.
Direct multi-entry is **MORE DATA**.

### Direct IELR — NO-GO

The threshold is at least two verified representative real grammars that both
show a practical canonical-collection cost and require IELR for semantically
meaningful conflicts. The current artifact has one measured real grammar, zero
real IELR-required conflict cases, and no verified public checkout.

[V001](verifier-trust-boundary.md) is complete, so the trust-boundary threshold
is satisfied. It also establishes a current NO-GO condition: default and
strict `ielr1` verification both enumerate the full canonical LR(1)
collection. A direct builder would therefore not remove canonical scale cost
from the current verified workflow, and the verifier does not establish IELR
adequacy or split witnesses. Together with no real IELR-required workload,
that makes direct IELR unjustified now rather than merely unmeasured.

Evidence that can change the decision must include verified real grammars,
material canonical state/item cost or observed exhaustion, meaningful
conflicts removed by IELR, a bounded verification plan that does not make full
canonical enumeration mandatory, and an owner accepting the specification and
maintenance budget. State-count vanity alone is insufficient.

### Direct multi-entry — MORE DATA

The threshold is at least two verified real multi-entry grammars plus either an
observed construction bound or at least twofold structural overhead in the
current shared path relative to an admitted direct plan. The registry contains
zero real multi-entry workloads. The existing synthetic matrix exercises both
shared and isolated modes, but neither its elapsed time nor its equal state
counts justify a production algorithm.

Evidence that can change the decision must add verified real multi-entry
grammars, preserve entry dispatch and shared conflict attribution, demonstrate
material structural cost, and identify an owner for the semantic and
maintenance plan.
