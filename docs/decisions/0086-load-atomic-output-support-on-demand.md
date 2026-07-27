# ADR 0086: Load atomic output support on demand

- Status: Accepted
- Date: 2026-07-27

## Context

Cold public-generator profiles showed `tempfile` and its `tmpdir` dependency in
the ordinary Ruby generation load path even after the main generation
transaction stopped using them. The shared CLI output module required
`tempfile` for IR, documentation, and migration subcommands, while ordinary
parser generation publishes artifacts through `GenerationTransaction`.

## Decision

The shared CLI output module loads `tempfile` inside `atomic_write_ir`, the
operation that needs it. Registering the module and ordinary parser generation
do not load the library. Optional output commands retain the same Tempfile
implementation and atomic rename behavior.

## Consequences

- Ordinary parser generation does not load `tempfile` or `tmpdir` through the
  shared output module.
- The first IR-style atomic output pays the standard-library load cost.
- CLI load-graph tests make the ordinary-generation boundary explicit.
