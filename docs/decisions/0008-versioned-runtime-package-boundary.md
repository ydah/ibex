# ADR 0008: Separate the runtime behind a versioned parser-table ABI

- Status: Accepted
- Date: 2026-07-28

## Context

Applications executing a generated parser do not need the grammar frontend or
generator. Independently installed generated code and runtime code still need a
precise compatibility boundary; otherwise a table-shape change can fail or be
misinterpreted during a parse.

## Decision

The dependency-free parser runtime ships as `ibex-runtime`; the generator
depends on it but runtime deployments do not depend on generator code. Normal
generated parsers require the runtime package, while embedded output carries
the same runtime implementation.

Every generated table declares a parser-table format version. The runtime
validates the version and marker combinations before consuming input. Changes
to required shape, action calling convention, or table meaning increment that
version.

Plain and compact tables are two encodings of the same lookup contract.
Compression may change representation only when every declared and unknown
token retains the same shift, reduce, accept, or error result. In particular,
explicit error cells must mask default reductions.

## Consequences

- Generator and runtime packaging can evolve independently within the declared
  dependency and table-format contracts.
- Unsupported generated parsers fail before lexer or semantic side effects.
- Compact representation remains replaceable and optimizable without becoming
  a second parser semantics.
