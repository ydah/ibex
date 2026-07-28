# ADR 0009: Isolate mutable parser sessions from immutable parser data

- Status: Accepted
- Date: 2026-07-28

## Context

Generated tables are immutable program data, while LR stacks, lexer state,
lookahead, recovery state, observers, and incremental caches are per parse.
Supporting pull, yielding, and push input through separate engines would make
their recovery and callback behavior drift.

## Decision

Generated parser classes own recursively frozen tables. Each parser instance
owns one mutable session and permits only one active driver. Pull, yielding, and
push APIs feed the same LR transition and recovery machinery; nested or mixed
drivers fail before mutating state.

State, semantic value, optional location, and optional Green stacks remain
index-aligned. Capabilities allocate their parallel state only when the
generated grammar or runtime tooling requires it.

Per-instance resource limits bound stack growth, recovery attempts, and other
session-owned search or memo structures. Exceeding a bound produces a
structured failure rather than unbounded work. Sharing a parser instance or
its application callbacks across concurrent parses is outside the contract.

## Consequences

- Parser classes and eligible table graphs can be shared while sessions remain
  independently mutable.
- All input lifecycles preserve one action, recovery, and callback ordering.
- Applications choose stricter or larger limits without regenerating tables.
