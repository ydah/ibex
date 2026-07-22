# 0011: Unifying conflict counterexamples

- Status: Accepted
- Date: 2026-07-22

## Context

A shortest route to a conflict state explains reachability but does not prove ambiguity. A useful ambiguity diagnostic needs one
terminal sentence accepted through both competing actions, together with the two complete derivation trees. Such a search cannot
be guaranteed to terminate for every context-free grammar.

## Decision

Search parser-stack configurations using only Automaton IR. At the selected conflict, force each pair of competing actions and
breadth-first search for a common suffix that makes both branches accept. Preserve parse nodes on each simulated stack so a
successful search produces two complete derivation trees. Bound the search by terminal count and configuration count.

If the bounded search finds no common accepted sentence, retain the deterministic shortest state-path witness from ADR 0010 and
mark it explicitly as nonunifying.

## Consequences

Unifying results prove that the grammar is ambiguous and reports show the precise lookahead position plus both parses. Conflicts
caused by an LALR state merge can still receive useful nonunifying witnesses, and expensive or nonterminating searches cannot
block report generation.
