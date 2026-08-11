# Direct IELR decision dossier

I001 is **NO-GO** for release promotion. An experimental direct IELR
implementation may exist behind an explicit opt-in, but it is not authorized as
the default or as a release-readiness claim; I002 remains
blocked. This decision is a feature gate, not a claim that direct IELR has no
future value.

The final decision date is 2026-08-11. Revision
`f917abde4c300358939ab2dca05644119b7a3953` is the repository evidence snapshot
reviewed immediately before this dossier was published; it is not a claim that
the dossier itself existed in that revision. The machine record marks the
decision `final_no_go`, its basis `repository_evidence`, and its review state
`validated`. It asserts no signer, consent, or personal decision attribution.

The closed machine record is
[`direct-ielr-decision-v1.json`](../tool/quality/evidence/direct-ielr-decision-v1.json),
validated by
[`direct-ielr-decision-v1.schema.json`](../schema/direct-ielr-decision-v1.schema.json).
Run its evidence and policy gate with:

```sh
bundle exec ruby -Ilib -r./tool/quality/direct_ielr_decision \
  -e 'Ibex::Quality::DirectIELRDecision.new.verify!'
```

## Decision rules

A GO requires every GO condition. The current record satisfies none of them.

| GO condition | Status | Current evidence |
| --- | --- | --- |
| At least two representative real grammars show practical canonical-state or item cost. | Not satisfied | H005 has one measured real grammar. |
| IELR is required by those representative grammars. | Not satisfied | There are zero real IELR-required workloads and zero semantically reviewed conflict removals. |
| An algorithm and specification owner exists. | Not satisfied | No accepted owner is recorded. |
| A noncanonical verification plan exists. | Not satisfied | No accepted scale-independent plan exists; the current verified workflow requires full canonical LR(1). |
| The maintenance budget is accepted. | Not satisfied | No accepted ongoing implementation, verification, review, and maintenance budget is recorded. |

A single NO-GO condition is sufficient. All five conditions remain explicit so
that later reviews cannot silently narrow the policy.

| NO-GO condition | Status | Current evidence |
| --- | --- | --- |
| No real workload requires IELR. | Satisfied | No measured real workload currently requires IELR. |
| Canonical LR(1) completes within the current project budget. | Satisfied for the measured scope | The one measured real grammar completes without observed exhaustion. This is not a general scale bound. |
| LR(1) or a grammar rewrite is simpler. | Not assessable | There is no concrete real conflict case on which to compare alternatives. |
| The verifier would still enumerate the full canonical collection. | Satisfied | Default and strict `ielr1` verification both enumerate full canonical LR(1). |
| The benefit is only state-count vanity. | Satisfied | No semantic conflict-removal benefit is established. Structural counts alone do not justify a second construction algorithm. |

The decision is therefore NO-GO on more than one independent ground. In
particular, promoting a direct builder now would leave the dominant
canonical-collection cost in the verified workflow.

## Bound observations and verification gaps

H005 records one measured real workload, `ibex-frontend`: 227 LR(0) states and
633 LR(0) items, 456 canonical states and 10,482 canonical items, and 227 final
IELR states. It has no unresolved conflict requiring IELR. The three registered
public-real workloads were not run, so there are zero verified public
checkouts in this capture.

The canonical scale problem is unresolved. Completion of the one measured real
grammar does not establish an upper bound for other grammars. Conversely, the
current default and strict verifier both build full canonical LR(1), so direct
construction alone cannot remove that cost from a verified build.

V001's supported IELR check establishes membership in a canonical-core union
and, in strict mode, union coverage. It does not verify IELR adequacy, conflict
preservation, why a state was split, or split witnesses. The dossier records
all three relevant assurances as `not_verified`.

## Reconsideration gate

Reconsideration requires all of the following new evidence:

1. At least two verified representative real grammars.
2. Material canonical state/item cost or observed bounded exhaustion on those grammars.
3. Semantically reviewed, meaningful conflicts that IELR removes on those grammars.
4. A bounded verification plan that does not make full canonical LR(1) enumeration mandatory.
5. An identified owner who accepts the algorithm and specification.
6. An accepted implementation, verification, review, and maintenance budget.

State-count reduction without a real semantic or operational need does not
reopen the gate.

## Legal and implementation provenance

Any future direct IELR design must be independently derived from papers and
specifications. GPL implementation source, including GNU Bison implementation
source, must not be inspected as a design input or translated. No GPL
implementation source was used or translated for this decision. This rule does
not replace project license review if the gate is reconsidered.

## Evidence identity

The machine dossier binds the H005 human report, H005 machine evidence and
schema, the V001 trust-boundary report, and the current reference-collection
and verifier implementations by path and SHA-256 at the reviewed revision. It
also binds:

- H005 capture base revision
  `b5933ae49297422546113577072efce59878009f`;
- H005 bound-path digest
  `27b5abf3e1ec20b9b904e46c9f7283ebb6b9a710bb3f0d05a6cad067d9627ac3`;
- H005 implementation digest
  `6c62c6c1ca7f9ad078405019502d1e7bed8364d1786a4f45755480d372122aac`;
- V001 revision `c7e5cad89ccd00591f3127fdb76a789bbeb202ab`.

The quality gate verifies the schema, exact GO/NO-GO inventory, follow-on
block, H005 thresholds and measurements, V001 boundary statements, legal
lineage, revision ancestry, every current and reviewed-revision source digest,
and the aggregate source-list digest. A changed source requires an explicit new
decision record rather than silently inheriting this decision. In particular,
the final H005 recapture must be followed by a dossier refresh, even if its
high-level NO-GO result is unchanged.

Exact reviewed history is part of the evidence contract. A shallow checkout
that omits the decision or V001 revision fails closed with an unavailable
revision error. Jobs running this gate must fetch complete history; they must
not silently weaken source verification to accommodate a depth-one checkout.
