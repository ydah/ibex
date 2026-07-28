# ADR 0005: Resolve grammar composition in a contained filesystem boundary

- Status: Accepted
- Date: 2026-07-28

## Context

Composing grammar fragments introduces file identity, traversal order, cycles,
diamonds, source provenance, and symlink escape. Textual concatenation loses
those properties and makes programmatic source parsing perform implicit I/O.

## Decision

Root and fragment files have distinct syntax and ownership. Parsing records
`import` nodes without reading their targets. A resolver is the sole filesystem
boundary and returns one immutable resolution containing the merged AST,
canonical dependency closure, and include provenance.

Canonical real paths define identity. Imports are resolved in deterministic
depth-first order, a completed canonical file is merged once, and cycles are
reported by canonical path. Targets must remain below the canonical root
directory after symlink resolution; absolute paths, parent traversal, and
ambiguous path forms are rejected.

Every CLI and build integration that accepts a grammar path uses this resolver.
Programmatic source-string parsing must opt into it explicitly.

## Consequences

- All consumers observe the same merge order and dependency closure.
- Diamonds are deterministic and symlink aliases cannot hide a cycle or escape
  the root.
- Composition is intentionally a flat merge; namespaces and re-export policy
  require a separate design.
