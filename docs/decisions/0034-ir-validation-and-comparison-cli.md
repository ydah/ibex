# 0034: Keep IR tooling structural and schema-version aware

- Status: Accepted
- Date: 2026-07-23

## Context

Published schemas help tools validate individual documents, while CI and grammar refactoring also need a dependency-free command
that checks semantic references and summarizes changes between pipeline artifacts.

## Decision

`ibex validate-ir FILE` uses the in-process v1 validator and reports the document kind. `ibex compare BEFORE AFTER` requires two
documents of the same kind and emits deterministic JSON. Grammar comparison lists symbol and production-shape additions/removals.
Automaton comparison adds algorithms, state and transition counts, and unresolved/resolved conflict deltas.

The comparison is structural. State ids are construction artifacts, so the command does not claim a semantic language
equivalence proof.

## Consequences

External tools can combine the published JSON Schemas with Ibex's deeper reference checks. Reviewers get a stable change summary
without coupling to builder internals or adding a JSON Schema runtime dependency.
