# 0004: Rule boundaries without semicolons

- Status: Accepted
- Date: 2026-07-22

## Context

The grammar permits omitted semicolons, while extended named references also use `identifier:identifier`. Whitespace is not
otherwise semantically meaningful, but source locations are available on every token.

## Decision

Within a rule, an `identifier:` begins the next rule only when its identifier starts at the same or a shallower column than the
current rule's LHS. A colon following a RHS symbol is a named reference in extended mode. Explicit semicolons remain
unambiguous and are recommended for unusually formatted grammars.

## Consequences

Conventional racc formatting parses without semicolons and extended named references remain available. A deliberately
outdented named reference must be reformatted or its containing rule terminated explicitly.
