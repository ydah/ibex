# ADR 0046: Expose stable immutable runtime events

- Status: Accepted
- Date: 2026-07-25

## Context

`on_shift`, `on_reduce`, and `on_error_recover` are application override points. Their arguments deliberately include live
semantic values and snapshots needed by parser subclasses, so widening them into a tooling protocol would expose private runtime
state and make coverage or debugging consumers depend on application objects. The original `Runtime::JSONLTracer` is implemented
as a singleton-class hook wrapper and already has a byte-level output contract that applications may consume.

Coverage and external tooling need a separate, versioned stream that also describes parser start, syntax errors, recovery
discards, acceptance, and rejection. That stream must be safe for untrusted semantic values and locations, must not retain parser
stacks or application objects, and must not construct events, summaries, or dispatch snapshots when it is unused.

## Decision

`Runtime::Parser#observe { |event| ... }` registers an observer and returns an opaque immutable subscription.
`unobserve(subscription)` removes it and returns whether it was active. Multiple observers run in registration order over a
snapshot. Registration or removal during a callback takes effect on the next event, including removal of an observer that has
not yet run in the current snapshot. Observer registration and parsing are single-thread-owned while a driver is active;
cross-thread mutation raises `ThreadError`. Driver transitions and observer mutations are linearized by one mutex, while
callbacks run outside that mutex so same-thread registration remains supported. The parser remains non-reentrant under its
existing driver guard.

Syntax-error handling fixes the observer set immediately after dispatching `error`, before calling the legacy `on_error` hook.
Registration or removal inside `on_error` therefore takes effect after that error/recover-or-reject transaction. This preserves
the original pre-hook token, value, and location without doing speculative sanitization when no observer was registered.

Events are `Runtime::Event` version 1 values with a type, per-session sequence number, and string-keyed data. Types are
`start`, `shift`, `reduce`, `error`, `recover`, `discard`, `accept`, and `reject`. The name `repair` is reserved by the design but
is deliberately absent from the v1 constructor and schema; a future repair payload requires a new schema version. Every event
and nested value is frozen. Events never contain live semantic objects, parser instances, callbacks, state/value/location stacks,
or mutable table records.

Event data contains only JSON primitives, arrays, and hashes. Semantic values are summarized with a maximum depth of 3,
16 entries per collection, 256 UTF-8 bytes per string, and 64 bits for integers retained as JSON numbers. Larger integers become
bounded bit-length and sign summaries. Invalid encoding is replaced. Cycles and truncation are explicit. Unknown objects are
represented only by a safely obtained class name; the sanitizer never calls application `inspect`, `to_s`, collection iteration
overrides, or location conversion hooks beyond the bounded documented location fields. A failing location field is omitted.
Location summaries are limited to file, line, column, end line, and end column.

The public event coverage metadata is:

- `start`: driver, initial state, table format version, full grammar digest, state count, and production count;
- `shift`: source/destination state, token id/display, bounded value summary, and location;
- `reduce`: production id, LHS id, RHS length, pre-pop state, post-pop state, goto state, bounded result summary, and reduction
  location;
- `error`, `recover`, and `discard`: state transition where applicable, token id/display, bounded value and location summaries,
  and a stable reason;
- `accept` and `reject`: final state, stable reason, and bounded result or token summaries.

Existing hooks retain their exact call counts, arguments, order, exception propagation, and semantic timing. `shift`, `reduce`,
and `recover` events are dispatched only after the corresponding existing observer hook returns successfully. The original
`Runtime::JSONLTracer` remains hook-based, returns the parser from `attach`, switches output on reattachment, catches its own
inspection/output failures, and preserves its existing JSON bytes. It does not use the new event schema.

New observers are synchronous application callbacks like the existing `on_*` hooks. Their exceptions propagate without
detachment, and later observers do not receive that event. This makes missing coverage or trace output visible and permits an
observer to stop a parse deliberately. The parser's existing ensure paths still return a pull driver to idle and finish a failed
push session. An observer exception never synthesizes a `reject` event.

Event dispatch sites perform a single `@runtime_observers` nil check. With no observer, a parse transition does not instantiate an
event, sanitize payload values, summarize locations, or allocate a dispatch snapshot. Parser initialization still creates the
mutex required to linearize driver and observer ownership. Tests instrument every event/payload builder boundary, and a dedicated
benchmark reports construction counts without using a timing threshold.

`Runtime::EventJSONLTracer.attach(parser, io:)` is the new schema-v1 JSON Lines adapter and returns a detachable tracer handle.
Each line is one `Event#to_h` document validated by `schema/runtime-event-v1.schema.json`. Serialization and output failures
propagate so the stream cannot silently claim completeness. Only the original hook-based `JSONLTracer` retains failure
containment for byte compatibility.

Generated parser tables add `grammar_digest`, `state_count`, and `production_count`. These keys are immutable metadata; ACTION,
GOTO, production semantics, and action method ABI do not change, so parser-table format version 3 remains current. Handwritten
version 1–3 tables may omit the new keys and produce nullable start metadata. Standalone and embedded generators expose identical
events and metadata.

## Consequences

- Coverage, tracing, and debugger tooling can consume a versioned public protocol without reading private stacks.
- Existing hook subclasses and the original JSONL byte stream remain compatible.
- Observer failures are visible to callers and cannot silently produce an incomplete new trace.
- Event summaries intentionally lose application-object detail and do not provide a repair event yet.
- Generated Ruby changes because it embeds full grammar/count metadata; deterministic fixtures and benchmark output digests must
  be regenerated even though parser behavior and the table ABI are unchanged.
