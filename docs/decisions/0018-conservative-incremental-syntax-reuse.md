# ADR 0018: Reuse incremental syntax only with conservative proofs

- Status: Accepted
- Date: 2026-07-28

## Context

Parser production actions may depend on arbitrary mutable state. Replaying or
skipping them during incremental parsing can duplicate side effects or return a
stale semantic value. Reusing a syntax subtree is also unsafe unless lexer and
LR state match at its boundaries.

## Decision

Incremental sessions are syntax-only: parser production actions are suppressed
and no semantic value is returned. Generated lexer actions still run because
they define token emission and lexical state. A fresh syntax parse remains the
reference result.

Relexing may reuse an old token suffix only after exact source-boundary, lexer
state, kind, text, flags, and trivia agreement. Green interning may preserve
equal token and node identity independently of parser reuse.

Subtree blending additionally requires the recorded left LR state to match the
live state, an unchanged following lookahead, a positive-width complete
nonterminal, and no error, missing, or skipped flags. Parse memo identity is by
occurrence position, not Green object identity. Every cache, decomposition, and
memo has a resource bound; uncertainty or exhaustion falls back to the already
available fresh path.

Incremental sessions and their caches are single-owner mutable objects.

## Consequences

- Incremental parsing cannot silently reuse semantic side effects or values.
- Valid reuse is intentionally missed whenever proof metadata is insufficient.
- Correctness is defined by equality with a fresh syntax parse; performance is
  evidence for optimization, not part of this decision.
