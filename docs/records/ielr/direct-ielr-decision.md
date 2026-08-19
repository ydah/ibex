---
title: Direct IELR decision dossier
description: Evidence and release boundary for the experimental direct IELR construction strategy.
---

# Direct IELR decision dossier

I001 is **NO-GO** for release promotion. An experimental direct IELR
implementation may exist behind an explicit opt-in, but it is not authorized as
the default or as a release-readiness claim; I002 remains
blocked. This decision is a feature gate, not a claim that direct IELR has no
future value.

The machine record marks the decision `final_no_go`, its basis
`repository_evidence`, and its review state `validated`.
The reviewed evidence date is `2026-08-19` at revision
`f64997e2e2e0e01ae6506b867f05801c86456ce8`. It asserts no signer, consent, or personal
decision attribution.

The closed machine record is
[`direct-ielr-decision-v1.json`](../../../tool/quality/evidence/direct-ielr-decision-v1.json),
validated by
[`direct-ielr-decision-v1.schema.json`](../../../schema/direct-ielr-decision-v1.schema.json).
Run its evidence and policy gate with:

```sh
bundle exec ruby -Ilib -r./tool/quality/direct_ielr_decision \
  -e 'Ibex::Quality::DirectIELRDecision.new.verify!'
```

## Decision rules

A GO requires every GO condition. A single NO-GO condition is sufficient.
The machine dossier is the canonical source for the conditions, statuses, and
observed evidence rendered below.

| GO condition | Status | Current evidence |
| --- | --- | --- |
| Representative practical canonical cost | Not satisfied | one measured real grammar; at least two representative real grammars are required |
| Ielr required by representative grammars | Not satisfied | zero real IELR-required workloads and zero semantically reviewed conflict removals |
| Algorithm and specification owner | Not satisfied | no accepted owner is recorded |
| Noncanonical verification plan | Not satisfied | no accepted scale-independent verification plan; current verification requires full canonical LR(1) |
| Maintenance budget accepted | Not satisfied | no accepted maintenance budget is recorded |

| NO-GO condition | Status | Current evidence |
| --- | --- | --- |
| No real ielr required workload | Satisfied | zero real workloads currently require IELR |
| Canonical lr1 completes within current measured budget | Satisfied | the one measured real grammar completes canonical LR(1) without observed exhaustion; no broader budget claim is made |
| Lr1 or grammar rewrite is simpler | Not assessable | there is no concrete real conflict case on which to compare alternatives |
| Verifier still enumerates full canonical collection | Satisfied | default and strict ielr1 verification both enumerate full canonical LR(1) |
| Only state count benefit | Satisfied | no semantic conflict-removal benefit is established; structural state and item counts alone do not justify direct IELR |
## Bound observations and verification gaps

Measured real grammars: **1**.
Verified public checkouts: **0**.
Real IELR-required workloads: **0**.
Semantically reviewed conflict removals: **0**.

Current real workload `ibex-frontend` records:

| Measurement | Value |
| --- | ---: |
| LR(0) states | 227 |
| LR(0) items | 633 |
| Canonical states | 456 |
| Canonical items | 10482 |
| Final states | 227 |
| Unresolved IELR conflicts | 0 |

Canonical scale status: `unresolved`.
Current verified workflow: `default_and_strict_ielr1_verification_enumerate_full_canonical_lr1`.
Scope: completion is established only for the one measured real grammar; no general scale bound is claimed

V001 verification gaps remain explicit:

- `ielr_adequacy`: `not_verified`
- `split_witnesses`: `not_verified`
- `conflict_preservation`: `not_verified`

## Reconsideration gate

Reconsideration requires all of the following new evidence:

1. **Representative real grammars:** at least two verified representative real grammars.
2. **Material canonical cost:** material canonical state or item cost, or observed bounded exhaustion, on those grammars.
3. **Meaningful ielr need:** IELR removes semantically reviewed meaningful conflicts on those grammars.
4. **Scale independent verification:** a bounded verification plan does not make full canonical LR(1) enumeration mandatory.
5. **Algorithm and specification owner:** an identified owner accepts the algorithm and specification.
6. **Maintenance budget:** the ongoing implementation, verification, review, and maintenance budget is accepted.

State-count reduction without a real semantic or operational need does not
reopen the gate.

## Legal and implementation provenance

Design lineage: `independent_design_from_papers_and_specifications`.
Permitted design inputs: `papers`, `specifications`.
GPL implementation source used: `false`.
GPL implementation source translated: `false`.

future direct IELR design must remain independent; GPL implementation source must not be inspected or translated

## Evidence identity

The machine dossier binds the evidence sources by path and SHA-256. It also binds:

- H005 capture base revision `98caaf795dbd64a6b58bcb942d6353313044bde1`;
- H005 bound-path digest `8c01454f02a3aceacbb5cc93542f46cb91dec54fc9c7b5c63abf00bb940d0a81`;
- H005 implementation digest `91160673bb0d540a738a698781b283d332729c5afafee6a601b14928b1ed3239`;
- V001 revision `f9d2c54eb4b27fc5ffe798bb0b29d038d97ee35c`.

| Source ID | Path | Role | SHA-256 |
| --- | --- | --- | --- |
| `h005-human-report` | `docs/records/profiles/construction-profiling.md` | H005 thresholds, observations, NO-GO rationale, and reconsideration evidence | `e69e88b9a474fb07b30d1e29a353e0d80edcced7d538b9ca3cf47413d087034c` |
| `h005-machine-evidence` | `tool/profile/evidence/construction-profile-v1.json` | machine-readable workload measurements, thresholds, decision, and capture provenance | `5406289ea16d4084d100b17d463f7220fb8054f0015b1f8d41e19df38fd89fd7` |
| `h005-evidence-schema` | `schema/construction-profile-v1.schema.json` | closed H005 evidence contract | `0cdac1514e965800701286084c18411a190ac424527ebf9de2163cbc204b4462` |
| `v001-trust-boundary` | `docs/policy/verifier-trust-boundary.md` | verifier reference cost, assurance boundary, and explicit IELR non-goals | `7615c078e856bad5b3b8b6606b39dc1b35fedc385da5ab7bbecd1c71b1376b93` |
| `v001-reference-collection` | `lib/ibex/verify/reference_collection.rb` | independent reference collection implementation reviewed by V001 | `d07e900652c61ddd942380d49edce0a3c811605cd82490c1e0e6db54010746fb` |
| `v001-verifier` | `lib/ibex/verify/verifier.rb` | current verifier checks reviewed by V001 | `934ae84111581d2edd4230b06733f259bbf72839042a67c62d20558973af2e2e` |

Aggregate source-list digest: `affcc0c555634cb1e4f25863d62199d3cff6deb143178dd93555843268b74981`.

Exact reviewed history is part of the evidence contract. A shallow checkout
that omits the decision or V001 revision fails closed with an unavailable
revision error. Jobs running this gate must fetch complete history; they must
not silently weaken source verification to accommodate a depth-one checkout.
