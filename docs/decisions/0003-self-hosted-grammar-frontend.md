# ADR 0003: Self-host the grammar parser behind an explicit bootstrap

- Status: Accepted
- Date: 2026-07-28

## Context

Keeping grammar syntax in a handwritten parser makes the generator unable to
exercise its own parser pipeline. Direct self-hosting creates a cycle because
the generated grammar parser is needed to regenerate itself.

## Decision

`lib/ibex/frontend/grammar.y` is the canonical grammar syntax. Its generated
parser is committed and is the normal frontend implementation. A specialized
lexer remains outside that grammar because opaque Ruby scanning and source
locations are lexical responsibilities.

An explicitly named bootstrap parser exists only to regenerate the committed
parser when that parser is absent. The regeneration path loads the minimum
frontend and generation components directly and does not load the normal
generated frontend. Normal library loading does not use the bootstrap.

No racc implementation or racc-generated source participates in bootstrap or
normal execution.

## Consequences

- Ordinary grammar parsing continuously exercises Ibex-generated code.
- Grammar syntax changes must keep the canonical grammar, bootstrap capability,
  and generated parser deterministic and mutually consistent.
- The bootstrap is recovery infrastructure, not a second supported frontend.
