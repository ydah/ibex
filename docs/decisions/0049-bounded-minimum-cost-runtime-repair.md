# 0049: Bounded minimum-cost runtime repair

- Status: Accepted
- Date: 2026-07-25

## Context

Yacc-style `error` productions remain useful, but an application may want a bounded automatic insertion, deletion, or replacement
before falling back to that recovery. Searching by executing semantic actions would duplicate side effects and make speculative
paths unsafe. Pull parsing can inspect future input, while push parsing must wait for the caller to provide enough evidence.
Ambiguous repairs, default reductions, explicit error masks, epsilon cycles, and large terminal vocabularies require deterministic
selection and hard resource limits.

## Decision

Automatic repair is disabled by default. Assigning an immutable `Runtime::RepairPolicy` to `parser.repair_policy` opts in for the
next pull or push session; the policy cannot change during an active driver or push session. With no policy the runtime does not
allocate repair input records, prefetch input, or alter existing error/recovery behavior.

The search is Dijkstra over immutable `(state stack, input index, successful shifts, edits)` configurations. It interprets only
ACTION, default ACTION, GOTO, and production LHS/length records. Explicit cells, including explicit `error`, take precedence over
defaults. Semantic actions, values, locations, hooks, `yyaccept`, and `yyerror` never run speculatively. Candidate insertions and
replacements exclude `$eof` and `error`; EOF cannot be deleted or replaced.

Defaults are insertion cost 1, deletion cost 1, replacement cost 2, maximum total cost 3, 5,000 configurations/table actions,
eight input records, three successful original/replaced shifts (or table acceptance), and 256 simulated stack entries. Every
policy value is a positive integer and successful shifts cannot exceed lookahead. The configuration counter also bounds
reduction/default loops.

Selection first minimizes total cost. Equal-cost candidates prefer edits on punctuation over inventing or discarding a word-like
token that likely carries an application value, then compare edit position, deletion/insertion/replacement rank, token id,
successful progress, input index, and state stack. Equivalent configurations retain only their best deterministic priority.

Pull parsing prefetches at most the policy lookahead and replays every unedited record. Push parsing retains the unexpected token
and returns `:need_more` until the buffered prefix proves a repair, reaches its lookahead limit, or receives EOF. This is explicit
opt-in latency. A selected plan is immutable and contains total cost, explored configuration count, and ordered edits.

The original syntax-error event and `on_error` run exactly once. The default `on_error` suppresses its exception only while a
plan has already been selected; a custom override keeps its normal behavior. `on_repair(plan)` then runs exactly once before
application. Hook exceptions propagate before edited tokens are replayed. Insertions use a nil semantic value and the current
input location; replacements preserve the original value and location; deletions remove the record. The edited prefix is then
processed by normal shift/reduce actions and ordinary hooks, so semantic actions execute once on the committed path.

If no plan exists or a budget is exhausted, the same error incident continues into existing yacc recovery without a second
`on_error` or error event. The default handler still raises when no plan is available. Semantic `yyerror` never invokes automatic
repair. Runtime-event schema v1 gains no repair event; consumers observe the original error followed by committed ordinary
actions, while applications that need the plan use `on_repair`.

## Consequences

- Applications can opt into deterministic, bounded single-plan repair without speculative semantic side effects.
- Existing parsers, default exceptions, error productions, generated tables, and no-policy allocation/read behavior remain
  compatible.
- Push callers may need to supply additional tokens or EOF before the call that encountered an error is reported.
- Inserted semantic values are necessarily nil; applications should use token-specific costs or inspect `on_repair` when a token
  requires a nontrivial value.
- The search is deliberately a bounded minimum-cost repair, not an exhaustive CPCT+ repair-set enumerator.
