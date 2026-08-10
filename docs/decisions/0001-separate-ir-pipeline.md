# ADR 0001: Separate pipeline stages with current IR

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

Both IRs have deterministic JSON encodings and shipped closed schemas. Their
current schema contract is explicit and validated. Untrusted JSON crosses a
validator that checks both shape and cross-record references before constructing
Ruby objects. A pre-v1 change that alters the meaning or required shape is
coordinated across writers, readers, schemas, fixtures, and downstream
consumers; no legacy reader is retained solely to preserve an obsolete format.

## Consequences

- Source, resumed Grammar IR, and resumed Automaton IR use the same downstream
  implementations.
- Incompatibility is detected at the document boundary rather than deep in
  generation.
- Presentation views and operational reports are not additional IRs unless
  another tool must consume them as durable data.
