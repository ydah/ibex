# ADR 0066: Generated Data AST and traversal contracts

- Status: Accepted
- Date: 2026-07-26

## Context

Semantic actions can construct any application object, but that freedom makes
routine AST declarations repetitive and leaves traversal APIs and signatures
to drift independently. Inferring node names or fields from Ruby action text
would be unsound and would not survive Grammar IR serialization.

## Decision

Extended alternatives may end with `@node Name(field, ...)`. The field list is
positional and must match the normalized RHS value count. A node annotation
cannot share an alternative with a semantic or middle action. Node names and
fields must be Ruby identifiers; repeated use of one node name must have the
same field list.

Grammar IR v2 stores the node name, ordered fields, and source location on the
production. Code generation emits one class per distinct shape through
`Ibex::Runtime::ASTData.define`. It uses Ruby `Data.define` when available and
an immutable keyword Struct on Ruby 3.0 and 3.1. The production's generated
action constructs that class.

The same shape set generates `AST::Visitor` and `AST::Listener`. Every node has
a statically named visit, enter, and exit hook, and generated RBS lists the
complete set. Field types come from symbol semantic types; a nonterminal whose
alternatives are all annotated is inferred as the union of their generated
node types. A temporary standalone Steep consumer project is an integration
test for the published signature.

## Consequences

- AST structure is explicit grammar metadata rather than parsed Ruby text.
- Generated runtime, action-shadow source, and RBS use the same node set.
- Explicit actions remain the escape hatch for transformations that are not a
  positional node construction.
- Version-1 IR migration records AST node metadata as unavailable.
