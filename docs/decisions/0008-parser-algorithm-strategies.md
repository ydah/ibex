# 0008: Parser construction strategies

- Status: Accepted
- Date: 2026-07-22

## Context

Some grammars are LR(1) but not LALR(1), while SLR can introduce conflicts that LALR lookaheads avoid. These variants should
not change Grammar IR or code generation.

## Decision

Build canonical LR(1) states once. `lr1` retains them, `lalr` merges states with equal LR(0) cores, and `slr` uses those LR(0)
states with FOLLOW sets on completed items. All strategies produce the same Automaton IR schema and use the same conflict
resolver. The CLI selects them with `--algorithm=slr|lalr|lr1`; `lalr` remains the default.

## Consequences

Algorithm changes stay inside the builder boundary. Canonical LR(1) can consume substantially more memory, while SLR is useful
for diagnostics and teaching but may report avoidable conflicts.
