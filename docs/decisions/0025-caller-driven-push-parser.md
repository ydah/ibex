# 0025: Add a caller-driven push parser lifecycle

- Status: Accepted
- Date: 2026-07-23

## Context

`yyparse(receiver, method)` is compatible with the established yielding API, but the parser still owns that producer call. Event
loops and streaming applications need the inverse contract: the caller supplies one token at a time and explicitly marks EOF.
Reusing the pull driver through an Enumerator would either block for input or hide parser-session lifecycle errors.

## Decision

`Ibex::Runtime::Parser#push(token, value = nil, location = nil)` starts a session lazily, supplies exactly one lookahead, and runs
reductions and recovery until that lookahead is consumed or the parse accepts. It returns `:need_more` after consumption and
`[:accepted, result]` when `yyaccept` accepts before EOF. If an overridden `on_error` returns and no recovery action exists,
`push` returns `[:rejected, result]`; it never labels that termination as acceptance.

`finish` supplies EOF and runs to completion, returning the semantic result. A finished session rejects additional input with a
positioned `ParseError`; `reset_push` explicitly returns it to the idle state. Invalid nil/false input is rejected before a
session starts. Pull `do_parse` and yielding `yyparse` remain unchanged and cannot replace an active push session. A shared driver
guard rejects nested pull, push, finish, or reset calls from callbacks before they can mutate parser state.

The optional location matches the pull token-source contract from ADR 0026; `finish(location:)` can locate EOF errors. Semantic
location stacks and pausable debugger
snapshots remain separate contracts rather than additional shapes hidden inside this lifecycle.

## Consequences

The push path shares the same ACTION/GOTO, semantic action, error recovery, callbacks, and table-version checks as the pull path.
It does not add threads, queues, or runtime dependencies. Applications get deterministic misuse errors for double finish,
input-after-finish, and attempts to start another parser driver while a push session is active.
