# ADR 0007: Share one downstream pipeline across parser algorithms

- Status: Accepted
- Date: 2026-07-28

## Context

SLR, LALR, IELR, and canonical LR(1) differ in state construction and
lookahead precision. Separate conflict resolution, table generation, or code
generation paths would make algorithm selection change more than the automaton.

## Decision

All algorithms consume Grammar IR and produce the same Automaton IR contract.
They share action candidate construction, conflict resolution, default-action
selection, reporting, table generation, and code generation.

LALR is the default and computes lookaheads directly over deterministic LR(0)
item occurrences. SLR uses the same LR(0) collection with FOLLOW sets.
Canonical LR(1) retains distinct contexts. IELR conservatively merges
compatible canonical states and prefers extra states whenever equivalence is
uncertain; it does not claim a minimum state count.

Reference strategies may remain for equivalence testing, but they are not
additional public algorithm identities when their output contract is the same.

## Consequences

- Algorithm choice changes automaton precision without changing downstream
  semantics or generated APIs.
- LALR avoids canonical state explosion in the default path.
- IELR can avoid LALR merge inadequacies but may pay canonical construction
  cost and retain more states than a lane-tracing implementation.
