# 0035: Stage extensions that require new source or runtime contracts

- Status: Accepted
- Date: 2026-07-23

## Context

The current work completes the low- and medium-risk additions from the extension inventory. Several remaining ideas are useful,
but each crosses a contract that is intentionally stable today. Treating them as incidental additions would weaken racc
compatibility, source mapping, or runtime determinism.

## Decision

The following work requires a separately reviewed phase and ADR:

- Parameterized user rules, `%inline`, grammar includes, and rule doc comments restart with a comment-preserving source model,
  explicit name/parameter hygiene, cross-file location rules, and a Grammar IR schema-version plan.
- Full `@1`/`@$` semantic locations restart with a parallel location stack, reduction-span rules, generated-action syntax, and
  typed action contracts. Optional lookahead locations and structured errors remain the compatible first layer.
- Static checking inside opaque semantic-action bodies restarts with an opt-in extracted-source contract that preserves grammar
  backtraces and lets Steep associate each body with the generated reduction signature. The current generated RBS deliberately
  types the method boundary without claiming to check the body.
- CPCT+-class repair and batch frontend diagnostics restart with a repair-cost policy, ambiguity/deduplication rules, bounded
  search budgets, and fixtures proving recovery continues at useful synchronization points.
- `fmt` and LSP restart after a lossless concrete syntax tree preserves comments and whitespace. Watch mode restarts with a
  portable event/polling policy and atomic regeneration contract.
- Production/state coverage and an interactive debugger restart with a stable event schema that extends, rather than exposes,
  private parser stacks. The push API and JSON Lines tracer are their current foundation. A separate `explain` command is not
  added while verbose reports already render every conflict witness and competing derivation.
- Automated `migrate-check` and racc differential-harness generation restart with an explicit application-code execution
  boundary and sandbox story.
- Chain-rule elimination and generated `case` dispatch restart only after the real-grammar benchmark demonstrates a repeatable
  runtime or size win and an ADR specifies source-map, table-version, and debugging consequences.

Direct LALR, IELR, ruby.wasm, mutation testing, and Pages/YARD publication retain the entry criteria in ADR 0024. GLR, PEG,
incremental parsing, and an integrated lexer remain outside the focused deterministic-LR product scope.

## Consequences

The shipped feature set remains compatible and testable instead of introducing partial syntax or unstable runtime state. Each
deferred item has a concrete prerequisite that can be turned into an implementation plan rather than an open-ended backlog label.
