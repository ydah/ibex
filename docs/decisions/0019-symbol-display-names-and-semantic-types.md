# ADR 0019: Symbol display names and semantic value types

- Status: Accepted
- Date: 2026-07-23

## Context

Grammar symbol names serve two different roles today: they are stable parser identities and they are also shown verbatim in
runtime errors and generated reports. Grammars also have no way to describe semantic value types, so generated parser signatures
cannot give reduction methods useful parameter and return types.

Reinterpreting `token NUM "number"` in compatible mode would not be safe because the existing grammar treats `NUM`
and `"number"` as two token declarations. RBS syntax is also broad enough that parsing it inside the dependency-free grammar
frontend would introduce an unrelated language implementation and a runtime dependency.

## Decision

Extended mode adds two dedicated declarations:

```text
display NUM "number"
type NUM "Integer"
type expression "AST::Expression"
```

Extended mode additionally accepts `token NUM "number"` as display-name shorthand. Compatible mode retains the original
two-terminal interpretation. This additive shorthand is specified by [ADR 0055](0055-declaration-contracts-and-structural-parameter-cycles.md).

Both declarations consist of a symbol and one quoted, single-line, non-empty string without control characters. The frontend
decodes the quoted value but otherwise treats a type spelling as opaque. RBS tooling remains responsible for validating the
emitted type expression. Compatible mode rejects either declaration at its keyword with a positioned error. `pragma extended`
enables them in the same way as the other extended grammar syntax.

Grammar AST records display and type declarations separately. Grammar IR v1 adds optional `display_name` and `semantic_type`
fields to symbol records. They are omitted when absent, and the loader accepts older v1 records without them. Display names do
not change symbol identity, token conversion, conflicts, digests of metadata-free grammars, or parser-table layout.

Runtime `TOKEN_NAMES`, `token_to_str`, `expected_tokens`, and human-facing reports prefer `display_name`. Internal lookups and
conflict records continue to use canonical symbol names.

Generated RBS declares each generated private reduction method. Its first argument is an RBS tuple whose entries come from the
declared RHS symbol types, falling back independently to `untyped`; its return type comes from the declared LHS type, also
falling back to `untyped`. The surrounding value stack remains `Array[untyped]`. These signatures describe method boundaries
only: default source mapping compiles each opaque action method with `class_eval` when the generated class loads, so this feature
does not claim that Steep checks action bodies.

## Consequences

- Existing compatible grammars and metadata-free schema-v1 JSON remain byte-stable.
- Diagnostics and reports can use domain language without changing lexer token objects.
- Generated parser RBS becomes materially more useful while remaining sound at undeclared boundaries.
- Applications should run normal RBS validation on generated signatures; Ibex deliberately does not parse RBS type syntax.
