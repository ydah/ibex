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
- Preserve per-block user-code source maps through IR and implement compatible default, all-code, and disabled line conversion.
- Complete the compatible CLI surface and add optional racc black-box result comparisons.
- Add extended EBNF/named-reference integration, source-facing EBNF labels in text/DOT/HTML reports, and resumable IR pipelines.
- Add selectable SLR, LALR(1), and canonical LR(1) construction strategies.
- Add a Ruby DSL frontend that converges on the existing Grammar AST and IR pipeline.
- Add unifying conflict counterexamples with complete competing derivation trees and bounded nonunifying fallback.
- Add generated parser RBS output, shipped runtime signatures, and strict structured grammar diagnostics.
- Expand generated signatures and Steep checking to every library source, including concrete frontend/IR/LALR/codegen/CLI domain
  types and the self-hosted parser.
- Support quoted, interpolated, and multiple Ruby heredocs plus recursively nested grouped EBNF.
- Define unknown external tokens to invoke `on_error` before yacc-style recovery.
- Add post-commit shift, reduction, and successful-recovery observation hooks to the runtime.
- Add complete quickstart, grammar, migration, architecture, and extension documentation with an executable README test.
- Self-host the grammar frontend from a committed Ibex grammar with deterministic regeneration and bootstrap parity checks.
- Version generated parser tables and reject missing or unsupported formats before consuming input.
- Add grammar-local `pragma extended` selection and document the action and named-reference boundary inside EBNF groups.
- Add fixed-seed pipeline properties, versioned Grammar/Automaton IR fixtures, and a reproducible whole-builder benchmark.
- Keep the whole-library Steep statistics in the README synchronized and enforce them in CI.
- Add typed symbol/display declarations, state-specific `.messages`, structured located errors, caller-driven push parsing, and
  dependency-free JSON Lines tracing.
- Add FIRST/FOLLOW output, Mermaid and interactive HTML reports, railroad SVGs, generated-output checks, Rake integration,
  bounded samples, IR validation/comparison, and published JSON Schemas.
- Compile mapped actions once at class load, optimize compact-table placement, make safe generated tables Ractor-shareable, and
  exercise real example grammars plus frozen-string and experimental TruffleRuby CI.
