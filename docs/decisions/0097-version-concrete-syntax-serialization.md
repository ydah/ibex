# ADR 0097: Version concrete syntax serialization independently

- Status: Proposed
- Date: 2026-07-27

## Context

Concrete syntax trees need a cache and interchange format without changing
Grammar IR v2. Source bytes may not be valid UTF-8, while JSON strings must be.
Incremental parse memo entries also depend on parser state numbering in
addition to the grammar digest.

Derived widths and aggregate flags must not be trusted from an external
document. At the same time, intrinsic flags such as `INCOMPLETE_INPUT` and a
missing token's expected kind cannot be inferred solely from its children.

## Decision

Introduce the independent `ibex_cst` schema version 1 in `schema/cst-v1.json`.
Documents record the grammar digest, parser-table version, state and production
counts, kind metadata, one Green root, and a reserved memo field.
The document also records the trivia policy so a loaded `drop` tree cannot
silently enable source-coordinate APIs.

Text has exactly two forms:

- valid UTF-8 bytes use a JSON string;
- all other bytes use `{"b64": "<canonical Base64>"}`.

Nodes store kind `k`, intrinsic flags `f`, and children `c`. Tokens store kind,
flags, expected kind `e`, text, and leading/trailing trivia. The explicit `f`
and `e` fields are a necessary refinement of the design sketch: without them,
early-accept and repair state cannot round-trip. Annotations are session-local
and serialization rejects annotated trees rather than silently dropping them.

`Serialize.dump` uses fixed insertion order and pretty JSON.
`Serialize.load` delegates to `Validator`, which checks the closed shape,
compatibility metadata, kinds, canonical Base64, and flag bits. Green
constructors recompute widths, trim widths, aggregate flags, and descendant
counts. A grammar digest mismatch raises a structured `ValidationError`.

The memo field is `null` or a schema-v1 preorder `left_states` object.
Incremental Stage B emits it when supplied to `Serialize.dump`. Loading
validates its cardinality and state bounds. Expected state-count or
production-count mismatches silently discard the memo while retaining the
validated tree; a grammar-digest mismatch remains a structured compatibility
error for the tree itself.

## Consequences

- Dump/load/dump is byte-stable, including for invalid UTF-8 source bytes.
- CST serialization can evolve without changing Grammar or Automaton IR.
- State-count and production-count guards prevent stale parser memo reuse.
- Serialized trees intentionally do not preserve Red parents, offsets, files,
  memoized Red children, or syntax annotations.
