# 0052: Safe Automaton IR table simulation

- Status: Accepted
- Date: 2026-07-25

## Context

A parser debugger should explain state transitions and reductions without loading generated Ruby or running application semantic
actions. It must agree with optimized runtime table selection, particularly where an explicit `error` masks a default reduction.
Malformed automata, epsilon/default-reduction cycles, and unbounded state-stack growth must not hang an interactive tool.

## Decision

`TableSimulation::Simulator` interprets a validated Automaton IR state stack only. A caller supplies terminal names or unique
display names one at a time through a session. `$eof` is supplied by `finish`; the reserved `$eof` and `error` spellings cannot be
submitted as ordinary input.

For each lookahead, lookup first uses an explicit state action, including explicit `error`; only an absent cell uses
`default_action`, and a missing default becomes an implicit error. Shift pushes its target. Reduce pops the production RHS
length, follows the LHS goto, and does not inspect or execute the production action. Accept and error terminate. Stack underflow,
a missing goto, or a missing referenced symbol fails as invalid simulation state.

Each immutable step records sequence, pre-action state, token id/display, action, explicit/default/implicit source, nullable
production/LHS/RHS/target details, and stack depth before and after. The versioned JSON result also records grammar digest,
algorithm, canonical supplied token names, and accepted/error status. It contains no semantic values, Ruby code, locations,
private runtime stack, host, or clock and is described by `schema/table-simulation-v1.schema.json`.

The default budgets are 100,000 actions and 10,000 stack entries. Positive `--max-steps` and `--max-stack` values can override
them. They bound default/epsilon loops and pathological growth deterministically.

`ibex debug AUTOMATON.json [TOKEN...]` accepts only validated Automaton IR. With no token arguments it consumes one terminal per
stdin line, emits text steps as each token is processed, and treats a blank line or input EOF as parser EOF. `--format=json`
emits one schema-v1 result. An accepted simulation exits zero; a table error or command/validation failure exits nonzero.

## Consequences

- The debugger has no generated-code or application-code execution boundary and is suitable for untrusted validated IR.
- Optimized default reductions and explicit error masks are visible and match runtime selection order.
- Semantic `yyaccept`, `yyerror`, values, locations, and application recovery overrides are intentionally not simulated; use
  runtime events when those behaviors are the subject of debugging.
- Token-at-a-time sessions support interactive frontends without exposing mutable parser internals.
