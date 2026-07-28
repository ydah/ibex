# ADR 0012: Keep parser analysis bounded and free of semantic execution

- Status: Accepted
- Date: 2026-07-28

## Context

Conflict counterexamples, sample generation, table debugging, ambiguity
checks, migration inspection, and automatic repair explore potentially
unbounded parser or grammar configurations. Executing semantic actions on
speculative paths would duplicate application side effects and make read-only
tools unsafe.

## Decision

Static tools operate on validated Grammar IR, Automaton IR, or parser-table
state only. They never load generated application code or invoke semantic
actions. Every search has explicit token, configuration, stack, step, or
expansion limits and terminates when a limit is reached.

Results distinguish a proof from bounded evidence and from exhaustion. Failure
to find an ambiguity is never reported as proof of unambiguity. Table
simulation applies the same explicit-cell-before-default lookup rule as the
runtime.

Optional runtime repair also searches table configurations without actions.
Only the selected repair is replayed through the ordinary runtime, where
semantic actions and observers execute once on the committed path.

## Consequences

- Analysis is suitable for untrusted validated artifacts within caller-supplied
  input-size limits.
- Deep grammars may require explicitly larger budgets or produce an
  inconclusive result.
- Runtime and tooling share table semantics without sharing mutable parser
  internals.
