# ADR 0017: Persist and edit syntax through Green structure

- Status: Accepted
- Date: 2026-07-28

## Context

Mutable syntax nodes make snapshots and sharing difficult. Serializing Red
parents and offsets would duplicate derived occurrence state and tie the file
format to one navigation implementation.

## Decision

Syntax edits replace one Green occurrence and path-copy only its ancestor
chain. Batch rewriting resolves replacements by Red occurrence; unchanged
subtrees retain Green identity. Annotations are occurrence-scoped identities,
exclude annotated Green values from interning, and are not serialized.

Concrete syntax uses an independently versioned closed schema. It records
grammar and parser compatibility metadata, kind metadata, trivia policy, and
one Green root. Source bytes use a canonical UTF-8-or-Base64 representation.
Loading validates the closed shape and compatibility, then recomputes widths,
descendant counts, and aggregate flags through Green constructors. Red parents,
offsets, cached wrappers, and annotations are deliberately absent.

Text diffs descend past identical Green values and emit byte-oriented edits
whose application must reconstruct the new source exactly.

## Consequences

- Small edits allocate in proportion to the changed occurrence path.
- Serialized trees are independent of Red navigation caches and preserve
  arbitrary source bytes.
- Structural editing may produce grammar-invalid trees; parsing validation is
  a separate operation.
