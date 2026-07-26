# ADR 0066: Composition shadow grammar

- Status: Accepted
- Date: 2026-07-26

## Context

Parameterized and inline rules need continuous use on a grammar large enough to expose ordering, semantic-action, and lowering
defects. Rewriting the production self-hosted grammar immediately would make bootstrap recovery harder and couple a stable
frontend artifact to preview composition features.

## Decision

Keep `lib/ibex/frontend/grammar.y` as the production source and add `shadow_grammar.y` as a second complete description of the
same language. The shadow grammar uses one parameterized sequence rule for repeated frontend structures and an inline wrapper
that crosses a semantic-action boundary. `Frontend::Regenerator.generate_shadow` builds it through the handwritten bootstrap
parser but never publishes its generated Ruby.

CI generates the shadow parser in memory and compares its location-preserving AST with the production generated parser for the
canonical grammar, the shadow grammar itself, and every extended frontend fixture. A structural test also proves that normalized
IR contains both parameter-specialization provenance and inline action composition.

## Consequences

- Composition features are exercised against the full frontend language without changing the production regeneration chain.
- Any AST drift fails the ordinary test suite before a preview feature can silently change frontend behavior.
- The shadow grammar deliberately duplicates production syntax and must be updated whenever the canonical language changes.
