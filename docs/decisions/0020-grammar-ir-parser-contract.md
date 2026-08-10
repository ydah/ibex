# ADR 0020: Persist parser contracts in Grammar IR

- Status: Accepted
- Date: 2026-08-05

> The pre-release compatibility readers and in-process IR migration path were
> retired before v1.0. Racc-compatible grammar input remains supported.

## Context

Parser construction algorithm, multiple-entry construction, and CST trivia
ownership are durable grammar-owned contracts. They must survive normalization,
IR-only generation, Automaton IR embedding, and static inspection before a
source declaration can be released. The current Grammar IR stores these
contracts at the root so a resumed pipeline sees the same explicit and
unspecified states as the source pipeline.

Three persistence boundaries were credible:

1. add one root `parser_contract` to Grammar IR;
2. publish a separately versioned Parser Contract IR; or
3. wrap grammar and contract documents in a grammar-bundle envelope.

The choice crosses persisted schemas, grammar digests, resumed generation, and
the Automaton IR boundary. Reversing it requires coordinated changes to the
writer, reader, schemas, fixtures, and downstream consumers.

## Decision

The current Grammar IR owns one closed, root-level `parser_contract`. Its admitted
fields are parser algorithm, entry construction, and CST trivia ownership.
Each field records an explicit value and source location, or an explicit
unspecified state. Unspecified contract state contains no built-in default;
defaults and invocation requests remain inputs to the typed configuration
resolver.

Automaton IR embeds the exact current Grammar IR document. Its grammar digest
therefore binds the parser contract. It also records whether entry construction
was shared or isolated; the existing algorithm field remains the selected
automaton fact.

There is one reader and one writer for the current format. `Grammar.new` and
`Automaton.new` both construct the current format directly.

A separate Parser Contract IR is rejected because it would create two
authorities that must be joined atomically and included independently in every
digest. A bundle envelope is rejected because Grammar IR already contains the
normalized root and resolved fragment result; an additional container would
add identity rules without an independently lifecycled artifact.

The contract remains generator-side data. It does not change parser-table
format, generated runtime constants, or the `ibex-runtime` ABI. Static readers
validate it without evaluating grammar actions or application code.

## Consequences

- Source and IR-only pipelines share one normalized contract and one grammar
  digest.
- Unspecified source contract remains distinct from a newly selected built-in
  default.
- Fragments cannot acquire parser-wide authority; only the normalized root has
  a parser contract.
- Grammar and Automaton IR each have one closed current schema.
- Revisit the rejected sidecar only if parser contracts gain an independent
  lifecycle or a non-grammar authority with multiple real consumers.
