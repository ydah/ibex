# ADR 0085: Specialize the direct pull boundary

- Status: Accepted
- Date: 2026-07-27

## Context

Public runtime profiles still showed avoidable framework work around the
compact loop. `do_parse` allocated and invoked a Proc solely to call
`next_token`, successful compact acceptance allocated a two-element outcome,
and every lexer or semantic callback dispatched a helper method to check the
same six fast-path invalidators.

These costs occur once or more per parse and do not represent grammar work.
The general `yyparse` source and generic parser outcome protocol still need
their existing callable and tuple forms.

## Decision

`do_parse` uses a nil internal source to select a direct `next_token` call.
Callable sources remain supported for `yyparse`. Successful ordinary compact
acceptance returns a frozen internal sentinel, and the caller reads the final
value from the parser stack. Exceptional semantic acceptance continues to use
the general outcome protocol.

The compact loop inlines the post-callback invalidation predicate. Mutation
trackers and public setters still disable the path immediately; the inline
predicate preserves direct instance-variable changes made by application
callbacks.

## Consequences

- Ordinary pull parsing removes the per-parse lexer Proc and accepted-outcome
  Array.
- The generic driver and public push/`yyparse` contracts do not change.
- Direct calls to the private driver with nil now mean the parser's
  `next_token`, matching `do_parse`.
- The invalidation condition is duplicated at the two compact callback
  boundaries and must stay synchronized with fast-path eligibility.
