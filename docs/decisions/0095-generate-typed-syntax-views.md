# ADR 0095: Generate typed syntax views from `@node`

- Status: Proposed
- Date: 2026-07-27

## Context

ADR 0066 uses `@node` declarations to generate immutable Data AST values. Those
values belong to semantic actions and intentionally omit punctuation and
trivia. Red syntax nodes preserve the physical grammar but otherwise require
callers to index untyped child arrays.

The same declaration must not acquire a second, incompatible shape rule. Inline
and EBNF lowering also means syntax slots must describe the normalized physical
RHS rather than the source spelling.

## Decision

For a `pragma cst` grammar, the generator emits `Parser::Syntax::<NodeName>`
classes deriving from `Ibex::Runtime::CST::TypedNode`. They are immutable views
over Red nodes, not transformed copies and not semantic values.

Each generated class has:

- a deterministic `KIND` and a nullable `.cast(SyntaxNode)`;
- one accessor per `@node` field, reading its physical child slot;
- repetition enumerators for lowered `*` and `+` helpers;
- element and separator enumerators for lowered `separated_list` helpers.

Parser-table format v6 records a slot entry per normalized production.
Ordinary fields map to an integer child index. Repetition fields map to a
frozen extraction record containing the index and extraction kind.
`SyntaxNode#deconstruct_keys` uses the same slot map.

Multiple alternatives bearing the same `@node` name remain valid under the
ADR 0066 rule: their field names and order must match. Generated RBS unions the
terminal and nonterminal accessor types across those alternatives. Repetition
convenience methods are generated only when every alternative agrees on the
same extraction rule.

## Consequences

- Data AST and typed syntax views coexist in distinct `AST` and `Syntax`
  namespaces and retain separate semantic and syntactic roles.
- Slot indices stay aligned with action positions because trivia is token-owned
  and never appears as an LR child.
- Generated Ruby, RBS, and table metadata remain byte-stable.
