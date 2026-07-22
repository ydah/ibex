# 0009: Ruby DSL frontend

- Status: Accepted
- Date: 2026-07-22

## Context

The Ruby DSL extension must not create a second normalization or parser-generation path. Source locations still need meaningful
values even though a DSL call does not correspond to a grammar-file token.

## Decision

The DSL builds the existing Grammar AST nodes directly and assigns monotonically increasing synthetic locations under `(dsl)`
or a caller-provided file name. Its builder exposes declarations, rule alternatives, actions, EBNF nodes, named references, and
user-code blocks. It then uses the unchanged Normalizer and downstream pipeline.

## Consequences

Text and DSL grammars produce semantically identical Grammar IR; only source-location metadata differs. New downstream features
automatically work for both frontends.
