# 0013: Runtime observation hooks run after committed parser events

- Status: Accepted
- Date: 2026-07-22

## Context

Generated parsers need lightweight extension points for tracing, metrics, and application diagnostics without replacing the LR
driver. A callback must have an unambiguous relationship to parser state, and error recovery must not report its synthetic
`error` token as ordinary lexer input. Recovery also pops parser stacks, so reporting only the resulting recovery state would
lose the token, value, and semantic context that caused the error.

## Decision

`Ibex::Runtime::Parser` defines three public, no-op methods that subclasses may override:

- `on_shift(token_id, value, state)` runs once after an ordinary lookahead is pushed and `state` becomes the current destination
  state. Shifting the runtime's synthetic token id 1 does not call this hook.
- `on_reduce(production_id, values, result)` runs once after the semantic action returns, the goto is known to exist, and the
  destination state and `result` are pushed. `values` is a shallow Array snapshot of the RHS semantic values taken before the
  semantic action runs.
- `on_error_recover(token_id, value, value_stack)` runs once after token id 1 is successfully shifted and recovery mode is
  entered. Its payload is a shallow snapshot captured when the original syntax error was detected, before `on_error` can mutate
  its own Array argument and before recovery pops states. It also runs for successful recovery requested by `yyerror`, for which
  `on_error` remains suppressed.

The hooks are available to every generated parser; overriding one is the opt-in extension. Their return values are ignored, so
the default methods and observer return values cannot change the semantic result. Callback exceptions are not rescued and
propagate to the parser caller. A failed semantic action, missing goto, unsuccessful error-token shift, or token discarded while
already recovering does not emit a successful-event callback.

## Consequences

Observers see committed parser state and receive stable payloads without gaining access to mutable internal stack Arrays. The
ordinary shift and recovery-entry streams remain distinct. Applications that raise from a callback should discard that parser
instance because its state may already contain the event that the callback was observing.
