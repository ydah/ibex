# 0014: Compatibility-safe default reductions

- Status: Accepted
- Date: 2026-07-22
- Supersedes: [ADR 0006](0006-automaton-ir-and-default-actions.md)

## Context

Automaton IR already reserves `default_action`, but ADR 0006 left it null because an ordinary yacc-style default reduction can
reduce a token whose original ACTION cell was absent. That delays syntax errors, runs semantic actions that previously would not
run, and can change error recovery. We want smaller generated tables without changing any ACTION lookup or the self-contained,
round-trippable Automaton IR contract established by ADR 0006.

## Decision

Automaton IR v1 continues to embed Grammar IR and stores resolved actions, gotos, conflicts, and an optional `default_action` in
each state. After conflict resolution, the builder may choose one existing reduce action as that state's default. Candidates are
ranked by the number of identical ACTION entries they replace, with the lower production id winning a tie.

For a selected default, the builder rewrites the complete known-terminal domain. Cells equal to the default are omitted, every
formerly absent cell becomes an explicit `error`, and all other actions remain explicit. The synthetic `error` terminal is part
of this domain. The default counts as one encoded entry and is selected only when:

```text
rewritten explicit entries + 1 < original explicit entries
```

Generated plain and compact tables carry the same per-state default array. Runtime lookup checks an explicit cell first, then
uses the default only for an internal id present in `token_names`; undeclared external tokens receive negative ids and therefore
remain immediate errors. Conflict search applies the same explicit-then-default lookup.

## Consequences

Every declared terminal has the same shift, reduce, accept, or error result before and after optimization, while unknown tokens
cannot fall through to a reduction. Error callbacks, semantic-action timing, and synthetic-token recovery remain unchanged.
Automaton JSON remains byte-stable across dump/load/dump and requires no schema-version change because `default_action` was
already part of v1. Some states remain unoptimized when error masks and the default would not reduce the total entry count.
