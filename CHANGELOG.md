# Changelog

## Unreleased

- Establish the Pure Ruby gem, Minitest, lint, CI, and CLI foundations.
- Add a table-driven Pure Ruby LR runtime with pull/push APIs, recovery, and tracing.
- Tokenize grammar files with positions, opaque Ruby actions, comments, and user-code blocks.
- Parse compatible and extended grammar syntax into a serializable, location-preserving AST.
- Normalize grammars into immutable, versioned JSON IR with EBNF expansion and diagnostics.
- Compute nullable, FIRST, and FOLLOW sets with deterministic integer bitsets.
- Build deterministic LALR(1) automata, resolve and retain conflicts, and render state reports.
- Generate plain or compact Ruby parsers with embedded runtime and source-line mapping support.
- Complete the compatible CLI surface and add optional racc black-box result comparisons.
- Add extended EBNF/named-reference integration, DOT/HTML reports, and resumable IR pipelines.
- Add selectable SLR, LALR(1), and canonical LR(1) construction strategies.
- Add a Ruby DSL frontend that converges on the existing Grammar AST and IR pipeline.
- Add deterministic shortest-path conflict witnesses with competing derivation summaries.
