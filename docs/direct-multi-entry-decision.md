# Direct multi-entry construction decision

M001 is **MORE DATA**. Direct shared multi-entry construction is not
authorized, and the specification, spike, oracle, implementation, and public
experiment tasks analogous to I002-I006 remain unauthorized. This is not a
NO-GO claim: the current evidence is insufficient to make the feature a GO.

The machine authority remains H005's closed
[`construction-profile-v1.json`](../tool/profile/evidence/construction-profile-v1.json),
validated by
[`construction-profile-v1.schema.json`](../schema/construction-profile-v1.schema.json).
Its `direct-multi-entry` decision is `MORE DATA`. M001 adds no second decision
record or competing schema.

## GO conditions

All four M001 conditions require real-workload evidence. None is currently
satisfied.

| GO condition | Status | Current evidence |
| --- | --- | --- |
| Actual verified grammars with multiple entries exist. | Not satisfied | H005 records zero real multi-entry workloads. Its decision threshold requires at least two representative real multi-entry grammars. |
| Canonical or fallback construction cost is material. | Not satisfied | No real multi-entry run records state/item exhaustion or at least twofold structural overhead. Host timing is an observation, not a decision gate. |
| Shared construction has a clear benefit over isolation. | Not satisfied | The synthetic matrix completes shared and isolated LALR/IELR with the same 9 states, 14 final core items, and 20 final lookahead memberships. This does not establish a real benefit. |
| Shared-entry conflict attribution can be preserved. | Not satisfied | The synthetic matrix has no conflicts, and no direct constructor exists from which to obtain attribution evidence. |

One synthetic threshold is satisfied only as diagnostic coverage. The
`matrix-multi-entry` fixture has two entries and exercises shared and isolated
construction, but it is a `repository_synthetic` workload. It cannot satisfy a
real-workload GO condition, establish material cost, demonstrate a shared
benefit, or prove conflict attribution. Its elapsed measurements have
`release_gate: false`.

## Exact evidence required for reconsideration

Reconsideration requires a new H005 capture, under its existing revision,
source-digest, environment, and measurement-policy provenance, that records:

1. At least two verified real grammars with exact identity, revision, grammar
   digest, entry count, and entry names, plus completed comparable shared and
   isolated runs.
2. Material canonical or fallback cost on those grammars: observed bounded
   exhaustion or the existing threshold of at least twofold structural
   overhead on real inputs.
3. A clear shared-over-isolated benefit from comparable structural evidence;
   host timing alone is insufficient.
4. Per-entry conflict attribution and semantic review showing that direct
   construction preserves the existing shared-entry conflict contract.
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

Until a recorded GO, no I002-I006-equivalent adequacy specification, bounded
spike, independent oracle and fixture program, internal direct constructor, or
public experiment is authorized. Existing shared multi-entry construction and
the default generation path remain unchanged.

Run the focused policy test with:

```sh
bundle exec ruby -Itest test/quality/direct_multi_entry_decision_test.rb
```
