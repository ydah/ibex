# ADR 0024: Keep the parser family and ecosystem scope focused

- Status: Accepted
- Date: 2026-07-23

## Context

Ibex is a deterministic LR parser generator with a racc-compatible surface,
staged IR, diagnostics, and a dependency-free Pure Ruby runtime. Several
adjacent parsing models and ecosystem projects are valuable, but starting
them without explicit boundaries would weaken compatibility work and make
completion criteria unclear.

## Decision

The following parsing models are intentionally outside the current product
scope:

- GLR, because it requires multiple actions per table cell, parse forests, and
  ambiguity policy across Automaton IR, runtime, and semantic values;
- PEG or packrat parsing, because ordered choice and memoization do not use the
  LR automaton contracts;
- tree-sitter-style incremental reparsing, because it requires persistent
  concrete trees, edit mapping, and reusable parse state;
- an integrated lexer generator, because Ibex keeps the public `next_token`
  boundary and zero runtime dependencies.

Lexer interoperability is in scope through documented adapters and examples,
especially the standard-library `StringScanner`; an external lexer may remain
an optional application dependency.

The following work is compatible with the product direction but belongs to a
separate phase. Each item may restart only when its listed entry criteria are
met:

- **Direct LALR lookaheads:** a representative real-grammar benchmark shows
  canonical LR(1) construction is a material time or memory bottleneck, and
  fixed-seed tests can compare the new relation-based builder with the current
  canonical-and-merge result.
- **IELR:** direct LALR is stable, a published algorithm is selected, and the
  phase has fixtures proving LALR inadequacy, LR(1) correctness, and the
  intended state-count bound.
- **Caller-driven push API:** a lifecycle ADR specifies start, push, finish,
  acceptance, repeated-use, and error-recovery results without redefining the
  existing compatible `yyparse(receiver, method)` API. This entry criterion has
  since been met and the API is implemented; see
  [ADR 0025](0025-caller-driven-push-parser.md).
- **ruby.wasm playground:** the browser packaging, worker boundary, asset
  update policy, accessibility baseline, hosting owner, and deployment target
  are agreed before site implementation.
- **Mutation testing:** an actively maintained Minitest integration supports
  the project's Ruby versions and license policy, and a bounded core namespace
  plus CI time budget is selected.
- **Benchmark history and Pages/YARD publication:** representative benchmarks
  and a public-API documentation boundary exist first; repository Pages
  settings, write permissions, retention, and deployment ownership are then
  approved explicitly.

## Consequences

- Current implementation work stays centered on deterministic LR correctness,
  compatibility, diagnostics, and measured Pure Ruby improvements.
- JSON/INI and other example lexers demonstrate integration without adding a
  runtime dependency or a second language implementation to Ibex.
- Deferred items have observable restart criteria rather than an indefinite
  promise.
- Pursuing one of these projects requires a new ADR that supersedes the
  corresponding boundary here.
