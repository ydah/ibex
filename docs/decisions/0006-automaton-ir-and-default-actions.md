# 0006: Automaton IR and default actions

- Status: Superseded by [ADR 0014](0014-compatibility-safe-default-reductions.md)
- Date: 2026-07-22

## Context

Automaton JSON must support resuming code generation without the original grammar file. Choosing a default reduction can delay
syntax errors by reducing cells that would otherwise be errors.

## Decision

Automaton IR v1 embeds its immutable Grammar IR in addition to its digest. States store merged LR items, transitions, resolved
actions, gotos, and every resolved conflict. The initial builder leaves `default_action` unset so an absent ACTION cell always
remains an immediate error. Compact table generation may compress explicit cells but must preserve this behavior.

## Consequences

Automaton JSON is self-contained at the cost of duplicating grammar data. Error positions remain predictable. A future default
reduction policy requires a new decision and compatibility measurements before changing generated behavior.
