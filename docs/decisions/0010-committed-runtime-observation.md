# ADR 0010: Observe only committed runtime transitions

- Status: Accepted
- Date: 2026-07-28

## Context

Hooks, tracing, coverage, and debugging need parser activity without depending
on private mutable stacks. Emitting speculative events makes failed semantic
actions and recovery attempts indistinguishable from committed parser state.
Optional observation must also remain removable from the normal hot path.

## Decision

Runtime hooks and versioned events are emitted at documented committed
boundaries for shifts, reductions, errors, recovery, discard, acceptance, and
rejection. Payloads are immutable snapshots or bounded JSON-safe summaries;
they never expose live parser stacks or retain arbitrary application objects.
Observer failures are visible to the parser caller.

Tracing and coverage consume this public boundary rather than adding parser
drivers. When no observer or hook is active, the runtime does not construct
event payloads.

The generic runtime is the semantic reference. A fast path may run only after
proving that every omitted observable capability is inactive, and must fall
back before a newly enabled capability could miss its documented next event.

## Consequences

- Runtime tools compose without reading implementation state.
- Coverage and traces describe completed transitions rather than intentions.
- Performance work must preserve invalidation rules whenever a new observation
  capability is added.
