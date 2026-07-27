# ADR 0096: Edit syntax by path copying

- Status: Accepted
- Date: 2026-07-27

## Context

Red values contain occurrence coordinates and parents, while Green values are
immutable and may be physically shared at multiple source positions. Editing a
shared Green value in place would mutate unrelated occurrences. Rebuilding the
whole tree would discard the allocation and diff advantages of the Red/Green
model.

Annotations have the same aliasing problem: attaching an annotation directly
to an interned node would make it appear at every occurrence of that Green
object.

## Decision

Syntax edits replace one Green occurrence and path-copy only its ancestor
chain. `replace_with`, node child operations, token text operations, and trivia
operations all return a new Red root. Unchanged children retain Green object
identity.

`SyntaxRewriter` performs bottom-up kind-name dispatch and returns the original
root when every child remains identical. `SyntaxEditor` registers
occurrence-addressed replacements and applies them in one traversal. An outer
replacement suppresses nested replacements; conflicting replacements for the
same occurrence raise `EditConflictError`.

`SyntaxAnnotation` is an opaque frozen identity. Annotating a node creates an
annotated Green replacement and path-copies its ancestors. Annotated Green
values carry `HAS_ANNOTATION` and are excluded from `NodeCache`.

`Diff.text_edits` skips identical Green subtrees, descends through compatible
nodes, and emits byte-oriented `TextEdit` values for changed leaves. Applying
the edits to the old `SourceText` must reconstruct the new source exactly.

Green nodes retain intrinsic flags separately from flags propagated from
children. Path copying uses intrinsic flags so removing an erroneous child
does not leave stale aggregate flags.

## Acceptance evidence

Editing tests assert that one token replacement preserves untouched Green
identity and allocates only the occurrence path. Rewriter identity, batched
editor conflict rules, isolated annotations on shared Green occurrences, flag
recomputation, and `Diff.text_edits` source reconstruction all pass. Annotated
values are excluded from the cache and serialization boundary.

## Consequences

- A single leaf edit allocates at most one replacement plus the ancestor path.
- An annotation applies to one Red occurrence even when another occurrence
  shares the same original Green node.
- Edited trees remain immutable and Green-shareable across Ractors.
- Structural operations can create grammar-invalid trees by design; parsing
  validation remains a separate concern.
