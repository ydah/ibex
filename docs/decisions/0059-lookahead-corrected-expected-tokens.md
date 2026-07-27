# ADR 0059: Lookahead-corrected expected tokens

- Status: Accepted
- Date: 2026-07-26

## Context

A parser state can select one or more default reductions before it decides whether a candidate lookahead is viable. Treating a
default reduction as acceptance overstates the expected-token set; running the real reduction would execute application semantic
actions merely to answer a diagnostic query. The compatible runtime contract must also retain its historical current-state
behavior.

## Decision

`Parser#expected_tokens_exact` tests each declared terminal against a copy of the current state stack. It follows table actions,
applies production lengths and gotos, and succeeds only at a shift or accept action. It never copies semantic values or locations
and never invokes semantic actions. Repeated stack configurations, malformed reductions, and missing gotos fail closed.

Grammar IR v2 optionally records `mode: "extended"`; absence means compatible mode. Ruby generation marks extended parser
tables with `exact_expected_tokens: true`. `expected_tokens` delegates to the exact algorithm only for those tables, while the
explicit exact API is available in both modes. A source-level `pragma extended` is preserved as extended normalized IR even when
the caller used the default parser option.

## Consequences

- Extended diagnostics and spelling suggestions receive a reduction-corrected expected set.
- Compatible generated tables and their default `expected_tokens` behavior remain unchanged.
- Exact queries are proportional to declared terminals and simulated reductions, and allocate only temporary state stacks.
- Mode is additive optional IR metadata, so existing v2 documents continue to load as compatible grammars.
