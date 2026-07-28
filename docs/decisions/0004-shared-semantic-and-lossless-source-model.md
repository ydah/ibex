# ADR 0004: Derive semantic and lossless source views from one lexing pass

- Status: Accepted
- Date: 2026-07-28

## Context

Generation needs a semantic AST, while formatting, diagnostics, documentation,
and editor features need comments, trivia, opaque bodies, and exact byte
ranges. Re-lexing independently for each tool can disagree with the token
stream that defined grammar meaning.

## Decision

One frontend lexing pass produces semantic tokens and immutable lossless
segments over the same UTF-8 source. A source document correlates those views
with half-open byte spans and reproduces the accepted input exactly. The
self-hosted parser remains the authority for the semantic AST.

Recovering diagnostics are bounded and may expose a clearly marked partial AST,
but never attach that projection to the unchanged source as if it were a
complete parse. Formatting changes trivia only, then reparses and rejects any
semantic difference. Filesystem and unsaved-buffer access are supplied through
an injected source loader; the parser itself performs no I/O.

## Consequences

- Formatter, documentation, resolver, and LSP features share one interpretation
  of tokens, opaque Ruby, locations, and source bytes.
- Exact byte coordinates remain distinct from editor-specific coordinate
  encodings such as UTF-16.
- Error recovery and overlays are tool boundaries around the strict parser,
  not alternative grammar semantics.
