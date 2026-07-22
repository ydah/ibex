# 0002: Runtime table contract

- Status: Accepted
- Date: 2026-07-22

## Context

The runtime must be testable before code generation exists, and its table representation is intentionally not compatible with
racc internals. Error recovery behavior also needs a stable boundary for generated parsers.

## Decision

Parser subclasses expose `.parser_tables`, a hash containing external-token mappings, display names, per-state ACTION and
GOTO hashes, production metadata, and optional default actions. Runtime actions use tagged arrays. Semantic action methods
receive the reduced RHS values and a copy of the remaining value stack.

Errors use token id 1. A returning `on_error` begins yacc-style recovery by popping until the error token can shift; subsequent
bad lookahead is discarded, and error reporting resumes after three successful shifts. Unrecoverable input returns `nil` after
a user error handler returns. The default handler raises `Ibex::Runtime::ParseError`.

## Consequences

Handwritten and generated parsers share a small public contract. Plain tables remain easy to inspect, while Phase 7 can add a
compact lookup adapter without changing semantic actions or public parser APIs.
