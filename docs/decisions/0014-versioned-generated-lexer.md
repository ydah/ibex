# ADR 0014: Model generated lexers as an independently versioned stage

- Status: Accepted
- Date: 2026-07-28

## Context

Handwritten token sources keep the parser runtime general, but a generated
lexer needs durable matching, state, streaming, and location semantics.
Embedding those details directly in Grammar or Automaton IR would tie lexer
evolution to parser construction.

## Decision

Generated lexer declarations normalize into immutable Lexer IR with its own
schema version. Grammar IR may embed that document, while Lexer IR can also be
validated and consumed independently.

Rules are ordered and state-scoped. At one input position the lexer chooses the
longest match, then the lowest rule id; empty matches are invalid. Lexical state
is explicit per parser instance. Streaming input retries a match when the
current chunk may be a strict prefix, so tokenization does not depend on chunk
boundaries.

Lexer actions execute only in the generated runtime boundary. Static tools may
inspect their opaque source but do not run it.

## Consequences

- Lexer format can evolve without changing Automaton IR or handwritten token
  sources.
- Matching is deterministic but intentionally uses a simple ordered rule model
  rather than a hidden engine-specific DFA contract.
- Regular-expression safety remains an application responsibility; static
  warnings are not a proof against pathological expressions.
