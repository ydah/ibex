# 0010: Shortest conflict witnesses

- Status: Accepted
- Date: 2026-07-22

## Context

Conflict reports need a concrete route to the conflicting state without coupling diagnostics back to the builder. Fully unifying
counterexamples can be expensive and are a later refinement.

## Decision

Use Automaton IR transitions for breadth-first search from state 0. Expand each nonterminal edge with its shortest terminal yield
computed by fixed point, append the conflict lookahead, and report both competing actions. Reduce interpretations include a
one-step derivation tree; shift interpretations include the shifted token and target state.

## Consequences

Every recorded conflict gets a deterministic, inexpensive witness from Automaton IR alone. A witness demonstrates reachability
of the conflict state but is not guaranteed to be a fully unifying sentence for both complete parses.
