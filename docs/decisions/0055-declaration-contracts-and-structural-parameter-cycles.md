# ADR 0055: Additive declaration contracts and structural parameter cycles

- Status: Accepted
- Date: 2026-07-26

## Context

The v1.0 design requires token aliases, independent shift/reduce and reduce/reduce expectations, precedence without
associativity, and explicit empty alternatives. It also rejects the existing parameter-expansion depth boundary: a grammar
should not change from valid to invalid merely because a configured depth is crossed.

Compatible grammar behavior and byte-stable metadata-free IR remain constraints. In particular, `token PLUS "+"` already
means two terminals in compatible mode, and old conflict summaries have a fixed shape.

## Decision

Extended mode adds four source forms:

- `token PLUS "+"` declares `PLUS` with `"+"` as its display name;
- `%expect-rr N` declares the expected reduce/reduce count independently from `expect N`;
- `%precedence TOKEN` assigns precedence without associativity, leaving an equal-level conflict as a counted default shift;
- `%empty` is the sole RHS item of an explicitly empty alternative.

The dedicated `display` declaration remains canonical and compatible mode retains its prior token-list interpretation.
`expect_rr` and its two conflict-summary fields are optional additive IR fields and are omitted when unused. Strict warning mode
promotes either expectation mismatch to an error. Extended implicit empty alternatives remain accepted but produce a structured
warning.

Parameterized expansion now memoizes same-instantiation recursion as before, but rejects a new specialization that re-enters an
active template with arguments structurally enclosing the active arguments. Shrinking calls remain finite and valid. The
total-specialization limit remains configurable defense in depth;
the arbitrary active-depth limit and its public option are removed.

## Consequences

- Metadata-free compatible Grammar and Automaton IR retain their previous bytes.
- Generated diagnostics can use compact yacc-style declarations without weakening stable symbol identity.
- Conflict expectations cover both conflict families and compose with strict CI.
- Argument-growing recursion fails at its structural cause instead of at an environment-tuned depth boundary.
- A deliberately polymorphic recursive template that re-enters itself with a different argument is rejected; such a grammar
  must be rewritten into a finite set of ordinary or separately named templates.
