# 0005: Grammar IR version 1

- Status: Accepted
- Date: 2026-07-22

## Context

The normalized grammar is the only contract between the frontend and analysis stages. Inline actions reduce an empty helper
production but must still see values already shifted for the surrounding production.

## Decision

Grammar IR schema version 1 uses immutable Ruby value objects and deterministic JSON. Reserved `$eof` and `error` symbols have
ids 0 and 1. Action records contain opaque code, location, named references, and `context_length`; generated inline actions use
the latter to view the required suffix of the surrounding value stack. Synthetic EBNF productions use ordinary action records
and machine-readable origins.

## Consequences

JSON round trips are stable and later stages do not depend on frontend nodes. Any incompatible field change requires a schema
version change. Inline action support does not leak frontend state into the runtime table contract.
