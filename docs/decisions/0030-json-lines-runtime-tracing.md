# 0030: Compose runtime tracing through existing observer hooks

- Status: Accepted
- Date: 2026-07-23

## Context

`yydebug` is intentionally human-readable, while test harnesses and external debuggers need a stream that can be parsed without
scraping text. The runtime already exposes post-commit shift, reduction, and recovery hooks. Adding another parser execution path
or serializing internal stacks would duplicate semantics and expose mutable implementation state.

## Decision

`Ibex::Runtime::JSONLTracer.attach(parser, io:)` prepends a small observer to one parser instance. It emits one JSON object per
line for committed shifts, reductions, and successful error recovery, then delegates to any application hook. Token and
production ids remain numeric; token display names are included. Semantic values use `inspect` strings so arbitrary application
objects cannot make JSON encoding fail. Invalid byte sequences are replaced. Inspection, encoding, and output failures are
contained because an optional observer must not change parsing or prevent an application hook from running.

The tracer deliberately records the stable public hook payloads, not the private state stack. Attaching it does not enable
`yydebug` or change parser results. Embedded parser generation includes the tracer and its standard-library JSON requirement so
the runtime API is the same in required and standalone outputs.

## Consequences

Tests, editor adapters, and debugging tools get a streaming stdlib-only format. Existing hook overrides continue to run. A future
interactive debugger can consume these records and the push API without becoming part of the parser core.
