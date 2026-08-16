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

The compatibility `RepairSearch#search` projection still returns the legacy
`RepairPlan | NEED_INPUT | nil` shape. The additive `search_result` method
retains a frozen typed outcome (`:selected`, `:need_input`, `:exhausted`, or
`:not_found`) for syntax tooling, so bounded exhaustion is not confused with a
complete search that found no plan.

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

## Syntax-only editor proposals

`SyntaxSession#repair` is a separate Experimental boundary for callers that
need byte edits rather than semantic replay. It runs the same bounded search
on a fresh private parser, captures absolute source ranges, resolves source
spelling only from caller-provided text or conservative punctuation literals,
and validates the applied bytes with a fresh syntax session. Production actions
and the application's `on_repair` callback do not run, and the result has no
semantic `value`. The originating session remains unchanged.

`SyntaxRepairResult` distinguishes `:accepted`, `:progress`, and `:rejected`
from bounded `:exhausted` and `:not_found` outcomes and selected-but-unavailable
cases such as missing token spelling or multiple repair segments. Accepted
results require a diagnostic-free fresh parse consuming all edited bytes. For
error results, `updated_source` keeps the exact bytes while the CST may expose
only the consumed prefix under the existing error CST contract. See [E002
syntax-only repair](investigations/E002-syntax-only-repair-result.md) and
[ADR 0023](../decisions/0023-syntax-only-repair-results.md).

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
| typed-search-outcomes | `test/runtime/repair_characterization_test.rb` |
| values-locations-and-replay | `test/runtime/repair_test.rb` |
| hooks-actions-and-observers | `test/runtime/repair_test.rb` |
| pull-and-push-bounds | `test/runtime/repair_test.rb` |
| cst-representation | `test/codegen/cst_test.rb` |
| cst-source-fidelity | `test/runtime/cst_fidelity_property_test.rb` |
| syntax-only-repair-projection | `test/runtime/syntax_repair_test.rb` |
<!-- repair-semantics:coverage:end -->

The H003 [round-two evidence](error-ux/round2.md) records exact selected plans
and fresh reparses but keeps external usefulness judgments on HOLD. Neither
that evidence nor this characterization promotes bounded repair to Stable.
