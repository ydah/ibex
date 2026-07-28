# ADR 0001: Separate pipeline stages with versioned IR

- Status: Accepted
- Date: 2026-07-28

## Context

Frontend parsing, normalization, automaton construction, and code generation
must be independently testable and resumable. Passing frontend objects between
all stages would couple later stages to source syntax and make serialized
artifacts ambiguous.

## Decision

Normalization produces immutable Grammar IR. Parser construction consumes
Grammar IR and produces immutable Automaton IR. Automaton IR embeds the Grammar
IR required to resume code generation; later stages do not reach back into
frontend AST objects.

Both IRs have deterministic JSON encodings, explicit schema versions, and
shipped closed schemas. Untrusted JSON crosses a validator that checks both
shape and cross-record references before constructing Ruby objects. A change
that alters the meaning or required shape of a document requires a new schema
version; optional metadata may be added only when older readers can ignore it
safely.

## Consequences

- Source, resumed Grammar IR, and resumed Automaton IR use the same downstream
  implementations.
- IR evolution carries a migration and support cost, but incompatibility is
  detected at the document boundary rather than deep in generation.
- Presentation views and operational reports are not additional IRs unless
  another tool must consume them as durable data.
