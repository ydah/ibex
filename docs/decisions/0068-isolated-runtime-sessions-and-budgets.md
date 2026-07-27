# ADR 0068: Isolate runtime sessions and enforce resource budgets

- Status: Accepted
- Date: 2026-07-26

## Context

Generated parser tables are immutable program data, while LR stacks, lookahead, recovery state, observers, lexer state, and
semantic values change throughout a parse. Sharing one parser instance between drivers would require pervasive locking and
would still make application actions and token streams unsafe. Separate instances can safely share tables, but malformed or
adversarial input also needs explicit bounds before a stack or repeated recovery consumes unbounded resources.

## Decision

Generated parsers recursively freeze ordinary parser tables and make them Ractor-shareable when their token conversion keys are
shareable. Threads and Ractors share the generated class and table constants, but each parse uses a distinct parser instance.
One instance permits only one pull or push driver at a time; application semantic values, actions, lexers, and callbacks remain
the application's concurrency responsibility.

`Runtime::ResourceLimits` is an immutable per-instance configuration with finite defaults:

- `max_stack_depth: 10_000`
- `max_recovery_attempts: 100`

The constructor accepts `resource_limits:` and idle instances may replace it with `resource_limits=`. Active push sessions and
running drivers reject changes. Every ordinary shift, reduction goto, and synthetic error shift checks the stack budget.
Entering a new syntax or semantic recovery checks the recovery budget. Each new parse resets the attempt counter.

Exhaustion raises `Runtime::ResourceLimitError`, also exposed as `Ibex::ResourceLimitError`. It is a `ParseError` with structured
`resource`, `limit`, `observed`, `state`, and `location` readers plus a frozen `to_h` representation. A recovery limit of zero
deliberately disables recovery. The embedded `-E` runtime contains the same limit classes and enforcement.

## Consequences

- Immutable tables can be shared without copying while mutable sessions remain isolated.
- Concurrency safety has an explicit boundary instead of implying that application callbacks are magically thread-safe.
- Stack and recovery exhaustion fail deterministically with machine-readable data.
- Applications may choose smaller defensive limits or larger trusted-input limits without regenerating a parser.
