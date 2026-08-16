# E001 existing repair semantics characterization

## Problem evidence

Ibex already has one opt-in bounded repair engine, but its contract was spread
between the runtime search, replay path, CST construction, and tests. Adding an
editor-facing result or recovery declaration without first closing these
semantics could create a second engine with different cost, value, or observer
behavior.

## Contract

E001 documents the current engine without changing it. The search is bounded
Dijkstra over copied LR state stacks and buffered token identities. Search does
not execute actions. A selected plan is reported after the syntax-error event
and `on_error`, then replayed through the ordinary parser path after
`on_repair`. Inserted values are `nil`, replacements retain the replaced value,
and deletions remove a value from the replay stream.

The current internal return contract deliberately remains characterized, not
improved here: `nil` represents both an exhausted search and a complete search
with no plan, while the private `NEED_INPUT` sentinel suspends an incomplete
push-parser search. E002 must not expose that ambiguity as a richer public
status without extending the engine deliberately.

## Trust label

Parser tables, token normalization, the priority queue, the repair search, and
normal replay are trusted implementation. Grammar semantic actions and parser
hooks are application code. They are not run during search, but they do run on
the committed replay path and may raise or have effects.

## Compatibility

This task adds documentation and characterization tests only. `RepairPolicy`,
`RepairEdit`, `RepairPlan`, `on_error`, and `on_repair` retain their existing
Experimental API and behavior. No fallback yacc recovery, push/pull parser
contract, or default parser behavior changes.

## Configuration admission

No grammar or CLI configuration is admitted. Repair remains an explicit
per-parser `RepairPolicy` assignment. All eight positive integer policy fields
and the `success_shifts <= max_lookahead` relation retain their current
validation.

## ABI assessment

No runtime method, RBS signature, generated table, grammar syntax, IR field,
manifest field, or persisted schema is added or changed. The new documentation
does not promote bounded repair from Experimental.

## Bounds

Search is bounded by maximum edit cost, visited/simulated configurations,
lookahead tokens, required successful shifts, and copied stack depth. Repeated
reduction stacks are cycle-checked. Pull parsing may prefetch up to the
lookahead bound; push parsing returns `NEED_INPUT` until the available prefix is
complete enough. Parser-level recovery-attempt and runtime stack limits remain
separate outer bounds.

## Oracle

The oracle is the existing runtime itself plus focused tests of the exact
priority tuple and its three distinct internal outcomes. Replay/value,
hook/observer, and CST claims are tied to executable tests listed in the public
characterization rather than inferred from documentation prose.

## Tests

- exact default costs, immutable policy, and invalid bounds;
- lexicographic priority including semantic-value risk and edit ordering;
- plan, `NEED_INPUT`, and the currently conflated `nil` result;
- inserted/replaced/deleted value and location behavior;
- hook order, normal action replay, and observer events;
- pull prefetch and push buffering;
- CST missing/error/skipped-token representation and source fidelity.

## Claims

The allowed claim is that E001 describes the current repository engine and its
known ambiguity. It does not claim edit usefulness, preservation of author
intent, action purity, minimal text distance, external validation, or a
syntax-only editor result.

## Kill conditions encountered

No second search or recovery engine is introduced. If a focused test disagrees
with the prose, the characterization fails instead of selecting the preferred
description. E002 must extend this engine and must not infer a semantic value
for inserted syntax.
