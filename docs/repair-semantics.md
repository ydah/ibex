# Existing bounded repair semantics

Ibex bounded repair is an opt-in Experimental runtime facility. Assign an
immutable `Ibex::Runtime::RepairPolicy` before starting a parser session. With
no policy, parsing does not search or prefetch for repairs and existing error
recovery is unchanged.

## Search state and bounds

`RepairSearch` runs Dijkstra search over configurations containing:

- a copied LR state stack;
- the buffered-input index;
- consecutive successful shifts;
- accumulated edit cost and ordered edits;
- whether that configuration has reached the proof goal.

Insertion, deletion, and replacement are the only edits. The default costs are
1, 1, and 2, with maximum cost 3. Search also has independent defaults of 5,000
simulated configurations, 8 lookahead tokens, 3 proof shifts, and stack depth
256. Every policy number is positive and proof shifts cannot exceed lookahead.

The queue orders configurations lexicographically by:

1. total cost;
2. semantic-value risk;
3. ordered edit keys `(input position, delete|insert|replace rank, token id)`;
4. goal before non-goal;
5. more successful shifts;
6. earlier buffered-input index;
7. LR state stack.

Word-like token names add semantic-value risk; punctuation does not. This is a
deterministic tie-break, not a claim that punctuation edits are correct.
Candidate inserted/replacement token IDs are ordered and exclude EOF and the
reserved `error` token. A plan succeeds after the configured consecutive
shifts or accept.

Search simulates table actions and reductions on integer state stacks only. It
does not call semantic actions, `on_error`, `on_repair`, lexer actions, or
runtime observers. Reduction-stack cycles, excess stack depth, excess cost,
and excess configuration count stop a path. Pull parsing may read ahead to the
lookahead bound. An incomplete push prefix yields the internal `NEED_INPUT`
sentinel and waits for more input.

The current private search result has a known limitation: both budget
exhaustion and a complete search that found no plan return `nil`. The normal
error/recovery path then runs. Callers cannot currently distinguish those two
reasons; E002 must preserve that fact or explicitly extend the result model.

## Selection, hooks, and replay

On a reported syntax error, the runtime captures the error context and CST
error, publishes the runtime `error` event, and calls `on_error`. If search
selected a plan, `on_repair(plan)` is called next. If either hook raises, its
exception propagates before edited tokens are applied.

After both hooks return, the runtime rebuilds the buffered token prefix:

| Edit | Replay token value | Replay location | CST effect |
| --- | --- | --- | --- |
| insert | `nil` | location at the insertion point | missing token |
| delete | absent from replay | original source retained separately | skipped/error trivia |
| replace | original token value | original token location | error-marked replacement |

The rebuilt prefix then passes through ordinary shift/reduce/accept handling.
Committed semantic actions and observers therefore run normally; speculative
search never runs them. Replay emits normal parser events and does not invent a
`recover` event for the selected repair. The original syntax error remains a
diagnostic even if replay accepts.

Inserted `nil` and a replacement's retained value are compatibility mechanics,
not evidence of user intent. A syntactically accepted repair can still be
semantically unsafe.

## CST and source ownership

CST parsing retains the original source bytes. Insertions are represented by
missing nodes, replacements carry an error flag, and deleted token bytes are
preserved as skipped-token trivia rather than silently disappearing. These
representations are part of the existing CST error-path contract, not a text
edit API. `RepairPlan#position` is a buffered token index, not a source-byte
offset.

## Executable coverage

<!-- repair-semantics:coverage:start -->
| Concept | Executable evidence |
| --- | --- |
| policy-and-default-off | `test/runtime/repair_test.rb` |
| dijkstra-priority-and-outcomes | `test/runtime/repair_characterization_test.rb` |
| values-locations-and-replay | `test/runtime/repair_test.rb` |
| hooks-actions-and-observers | `test/runtime/repair_test.rb` |
| pull-and-push-bounds | `test/runtime/repair_test.rb` |
| cst-representation | `test/codegen/cst_test.rb` |
| cst-source-fidelity | `test/runtime/cst_fidelity_property_test.rb` |
<!-- repair-semantics:coverage:end -->

The H003 [round-two evidence](error-ux-round2.md) records exact selected plans
and fresh reparses but keeps external usefulness judgments on HOLD. Neither
that evidence nor this characterization promotes bounded repair to Stable.
