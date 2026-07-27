# ADR 0067: Name fragment composition with import

- Status: Accepted
- Date: 2026-07-26
- Refines: ADR 0038

## Context

ADR 0038 implemented the complete secure fragment-composition boundary under an `include` spelling. The v1.0 feature contract
calls the operation `import`: a namespace-free merge of declarations and rules, token-set union, duplicate graph elimination,
and cycle detection. Maintaining two resolvers or changing the established AST and provenance model would create needless
semantic differences.

## Decision

`import "relative/path.y"` is the canonical extended-mode spelling. It lowers to the existing `AST::Include` node and therefore
uses exactly the same canonical realpath traversal, root containment, deterministic depth-first merge, diamond deduplication,
cycle diagnostics, immutable resolution, source provenance, CLI behavior, and build dependencies defined by ADR 0038.

Imported token declarations form the same merged token set as declarations in the root. Duplicate canonical files in a diamond
are merged once; conflicting declaration metadata and rule definitions continue through the normal positioned validation and
diagnostic paths. Namespaces and re-export controls remain outside the v1.0 contract.

The existing `include` spelling stays accepted as a compatibility alias. Formatting preserves the spelling written by the user,
while documentation uses `import` for new examples. Both the generated and bootstrap frontends parse the two spellings.

## Consequences

- The Phase 17 vocabulary matches the public design without duplicating composition machinery.
- Existing grammars and editor integrations remain source-compatible.
- Every graph safety and provenance guarantee is identical for `import` and `include`.
- Namespace and re-export design can be added later without pretending the current flat merge provides those semantics.
