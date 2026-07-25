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
  explicit name/parameter hygiene, cross-file location rules, and a Grammar IR schema-version plan. [ADR
  0039](0039-versioned-ir-v2-migration.md) satisfies the schema-version prerequisite and reserves explicit nullable provenance,
  documentation, expansion, and composed-action records. [ADR 0040](0040-lossless-frontend-source-document.md) satisfies the
  source-model prerequisite. [ADR 0042](0042-canonical-grammar-fragment-includes.md) satisfies and supersedes the grammar-include
  boundary with explicit fragment ownership, canonical containment, and cross-file composition. [ADR
  0043](0043-lossless-rule-documentation.md) satisfies and supersedes the rule-documentation boundary with segment-positioned
  attachment, repeated-rule semantics, and escaped standalone renderers. [ADR
  0044](0044-parameterized-user-rules.md) satisfies and supersedes the parameterized-rule boundary with byte-adjacent syntax,
  structural hygiene, memoized specialization, and deterministic work limits. [ADR
  0045](0045-bounded-inline-rule-expansion.md) satisfies and supersedes the inline-rule boundary with bounded structural
  expansion and resumable semantic-action plans.
- Full `@1`/`@$` semantic locations restart with a parallel location stack, reduction-span rules, generated-action syntax, and
  typed action contracts. [ADR 0036](0036-semantic-location-stack-and-spans.md) satisfies and supersedes this boundary; optional
  lookahead locations and structured errors remain its compatible first layer.
- Static checking inside opaque semantic-action bodies restarts with an opt-in extracted-source contract that preserves grammar
  backtraces and lets Steep associate each body with the generated reduction signature. The current generated RBS deliberately
  types the method boundary without claiming to check the body.
- CPCT+-class repair and batch frontend diagnostics restart with a repair-cost policy, ambiguity/deduplication rules, bounded
  search budgets, and fixtures proving recovery continues at useful synchronization points. [ADR
  0041](0041-bounded-frontend-diagnostics.md) satisfies and supersedes the batch frontend diagnostic boundary with conservative
  source-region recovery; CPCT+-class runtime repair remains deferred.
- `fmt` and LSP restart after a lossless concrete syntax tree preserves comments and whitespace. [ADR
  0040](0040-lossless-frontend-source-document.md) satisfies that prerequisite. Watch mode restarts with a portable
  event/polling policy and atomic regeneration contract.
- Production/state coverage and an interactive debugger restart with a stable event schema that extends, rather than exposes,
  private parser stacks. The push API and JSON Lines tracer are their current foundation. [ADR
  0037](0037-versioned-conflict-explanations.md) supersedes the boundary against a separate `explain` command with a thin,
  versioned view over existing Automaton IR and counterexamples; it does not supersede the runtime-event prerequisite.
- Automated `migrate-check` and racc differential-harness generation restart with an explicit application-code execution
  boundary and sandbox story.
- Chain-rule elimination and generated `case` dispatch restart only after the real-grammar benchmark demonstrates a repeatable
  runtime or size win and an ADR specifies source-map, table-version, and debugging consequences. [ADR
  0038](0038-versioned-benchmark-evidence.md) supplies the shared baseline and defines the candidate evidence gate; neither
  optimization becomes the default without its own qualifying comparison.

Direct LALR, IELR, ruby.wasm, mutation testing, and Pages/YARD publication retain the entry criteria in ADR 0024. GLR, PEG,
incremental parsing, and an integrated lexer remain outside the focused deterministic-LR product scope.

## Consequences

The shipped feature set remains compatible and testable instead of introducing partial syntax or unstable runtime state. Each
deferred item has a concrete prerequisite that can be turned into an implementation plan rather than an open-ended backlog label.
