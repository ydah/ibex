---
title: Direct multi-entry decision dossier
description: Evidence and release boundary for experimental shared multi-entry construction.
---

# Direct multi-entry construction decision

M001 is **MORE DATA**. Production direct shared multi-entry construction,
public experiments, and default-path changes are not authorized. This is not a
NO-GO claim: the current evidence is insufficient to make the feature a GO.

Evidence acquisition before GO may include a bounded design proof or
reachability analysis, an independent semantic oracle, and an adversarial
synthetic conflicting fixture or prototype. These activities must remain
bounded evidence work; they do not authorize a production implementation or a
public experiment.

The machine authority remains H005's closed
[`construction-profile-v1.json`](../../../tool/profile/evidence/construction-profile-v1.json),
validated by
[`construction-profile-v1.schema.json`](../../../schema/construction-profile-v1.schema.json).
Its `direct-multi-entry` decision is `MORE DATA`. M001 adds no second decision
record or competing schema.

## GO conditions

The first three M001 conditions require verified real-workload evidence. The
conflict-attribution condition may instead be established with adversarial
synthetic conflicting fixtures checked by an independent semantic oracle. None
is currently satisfied.

| GO condition | Status | Current evidence |
| --- | --- | --- |
| Actual verified grammars with multiple entries exist. | Not satisfied | H005 records zero real multi-entry workloads. Its decision threshold requires at least two representative real multi-entry grammars. |
| Canonical fallback cost is material. | Not satisfied | No verified real multi-entry run records canonical fallback exhaustion or at least twofold structural overhead. Host timing is an observation, not a decision gate. |
| Shared construction has a clear benefit over isolation. | Not satisfied | The synthetic matrix shows no structural advantage for shared LALR construction over isolation. This does not establish a benefit on a verified real workload. |
| Shared-entry conflict attribution can be preserved. | Not satisfied | The synthetic matrix has zero conflicts and exercises no direct construction mechanism, so it supplies no attribution evidence. |

The `matrix-multi-entry` fixture remains diagnostic coverage, not a GO
threshold. It has two entries and exercises shared and isolated construction,
but it is a `repository_synthetic` workload. It cannot satisfy any of the first
three real-workload GO conditions or prove conflict attribution. Its elapsed
measurements have `release_gate: false`.

## Exact evidence required for reconsideration

Reconsideration requires a fresh H005 capture at a fresh exact revision under
the existing source-digest, environment, and measurement-policy provenance
contract, recording:

1. At least two verified real grammars with exact identity, revision, grammar
   digest, entry count, and entry names, plus completed comparable shared and
   isolated runs.
2. Material canonical fallback cost on those grammars: observed canonical
   fallback exhaustion or at least twofold structural overhead on verified real
   inputs.
3. A clear shared-over-isolated benefit from comparable structural evidence;
   host timing alone is insufficient.
4. Adversarial synthetic conflicting fixtures and an independent semantic
   oracle showing that a direct mechanism preserves per-entry attribution.
5. An identified owner who accepts the semantic specification and ongoing
   implementation, verification, review, and maintenance budget.

The closed H005 decision must then change to `GO`. Adding a real workload or a
faster synthetic observation without satisfying the other conditions does not
authorize follow-on work.

## Independence and follow-on boundary

M001 is independent of the direct IELR decision. Direct IELR remains NO-GO,
and neither decision supplies evidence for the other. A future multi-entry GO
may share code with direct IELR only where independently specified invariants
genuinely coincide; it must not inherit an algorithm or verification plan by
coupling the two tracks.

Until a recorded GO, no production adequacy specification, production direct
constructor, public experiment, or default-path change analogous to I002-I006
is authorized. The bounded proof, reachability analysis, oracle, and adversarial
synthetic prototype described above are permitted only to acquire the four GO
conditions. Existing shared multi-entry construction and the default generation
path remain unchanged.

Run the focused policy test with:

```sh
bundle exec ruby -Itest test/quality/direct_multi_entry_decision_test.rb
```
