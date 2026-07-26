# ADR 0076: Ship the parser runtime as an independent gem

- Status: Accepted
- Date: 2026-07-26

## Context

Applications executing generated parsers do not need the grammar frontend, normalization passes, LR construction, reports, CLI,
watcher, or documentation tooling. Shipping the complete generator in production enlarges the dependency and update surface.
At the same time, compact generated tables need their immutable lookup class, and fully embedded `-E` output must remain
dependency-free.

## Decision

The repository publishes a second package, `ibex-runtime`, with its own `Ibex::Runtime::VERSION` and semver lifecycle. It contains
the runtime entry point and implementation, the compact-table value class, and their RBS signatures. It has no third-party
runtime dependencies and no executable.

The `ibex` generator gem depends on a compatible runtime minor series and excludes runtime-owned sources and signatures from its
own package. Generator-only table construction stays in `ibex/tables.rb`; the immutable `Ibex::Tables::Compact` class moves to
`ibex/tables/compact.rb`, which both packages can load without IR or generator constants.

Normal generated parsers require only `ibex/runtime`. Compact output no longer requires the generator's `ibex/tables` entry
point. Embedded output includes the same runtime and compact-table sources directly and continues to run under
`ruby --disable-gems`. The parser-table format version remains the actual compatibility gate between independently versioned
generator and runtime releases.

## Consequences

- Deployments can install `ibex-runtime` without installing the generator or executable.
- Generator and runtime releases can advance independently within the declared dependency and table-format contracts.
- Compact generated parsers no longer accidentally load generator table-building code.
- Package tests build the runtime gem and execute both runtime-only and embedded generated parsers in isolated processes.
