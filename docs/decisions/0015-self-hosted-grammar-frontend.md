# 0015: Self-hosted grammar frontend

- Status: Accepted
- Date: 2026-07-22

## Context

The original grammar parser was a handwritten recursive-descent implementation. Keeping grammar syntax in Ruby control flow made
the frontend harder to audit than user grammars and left Ibex unable to validate its own parser-generation pipeline. Replacing it
creates a bootstrap cycle: Ibex needs a grammar parser in order to generate the grammar parser.

The lexer remains specialized because Ruby action and user-code blocks are deliberately opaque to the grammar parser. Its tokens
also carry the source locations required by every AST node and diagnostic.

## Decision

`lib/ibex/frontend/grammar.y` is the canonical syntax definition. The committed
`lib/ibex/frontend/generated_parser.rb` is generated from it by Ibex and is the normal implementation wrapped by
`Ibex::Frontend::Parser`. `TokenAdapter` maps lexer tokens to generated terminals while retaining each original `Token` as the
semantic value. It performs the two lexical classifications that depend on frontend context: declaration keywords and
indentation-sensitive rule LHS boundaries.

The former recursive-descent implementation is retained as the explicitly named `BootstrapParser`. Normal library loading does
not require it. `Frontend::Regenerator` directly requires only the lexer/AST/bootstrap and downstream generation stages; it does
not require the public frontend or committed `GeneratedParser`. It parses `grammar.y`, then passes the AST through the ordinary
Normalizer, LALR builder, compact-table builder, and Ruby generator. This breaks the cycle even when the generated file is absent,
without introducing a pregenerated external tool or a runtime dependency.

Run `bundle exec rake frontend:generate` after changing the frontend grammar, semantic support, or generator output. The generated
file is deterministic and committed. A subprocess test removes the generated file from a temporary source copy, verifies that the
regenerator does not define `GeneratedParser`, and requires byte-for-byte output equality. Parity tests compare generated and
bootstrap ASTs and errors across compatible, extended, edge, and malformed grammars.

## Consequences

Ibex now exercises its own generated runtime for every CLI grammar parse and documentation example. Releases contain both the
canonical grammar and generated parser, so installed gems never need development tooling or bootstrap generation. The bootstrap
parser remains maintenance-sensitive until it can be reduced further; every syntax change must update it sufficiently to parse the
canonical grammar and must preserve the regeneration/parity tests.

The clean-room boundary remains unchanged: no racc implementation or racc-generated source participates in bootstrap or normal
execution.
