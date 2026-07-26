# ADR 0067: Example-keyed syntax error messages

- Status: Accepted
- Date: 2026-07-26

## Context

ADR 0031 attached custom syntax messages to numeric LR states. That made the
first implementation deterministic, but a harmless grammar refactor, algorithm
change, or table optimization could renumber states and attach retained prose to
the wrong parsing context. State numbers are useful review metadata, not durable
identities.

Applications also need an error identity that is stable enough for tests,
documentation links, telemetry, and programmatic handling. Generated prose
alone is not an API.

## Decision

`ibex-messages v2` keys each entry by a token sentence that reaches a syntax
error:

```text
# ibex-messages v2
sentence: NUM '+' ')'
## E0042
# entry: expression
# state: 7
# expected: '(', NUM
| An operand or opening parenthesis is required before ')'.
end
```

`ibex errors --list` performs a bounded breadth-first table simulation from
each parser entry point and prints one deterministic shortest witness for every
reachable error state. Semantic actions are never executed. Token and
configuration limits default to the counterexample-search limits and can be
overridden with `--max-tokens` and `--max-configurations`.

The sentence, optional entry-point name, and `E` identifier are durable review
keys. State and expected-token comments are regenerated metadata. Error
identifiers use at least four decimal digits, are persisted in the message file,
and are never reassigned by an update.

`ibex errors --update` simulates every saved sentence against the new table,
preserves its ID and message, and reports:

- `unreachable`: the sentence no longer reaches an error;
- `uncovered`: a reachable error state has no saved sentence;
- `moved`: the sentence still errors but now reaches another state.

New uncovered entries receive monotonically increasing IDs. Unreachable entries
remain in the file for review. The v1 parser and runtime embedding path remain
supported; updating a v1 file migrates its prose by the old state mapping and
emits v2. This preserves the stability promise made by ADR 0031 without keeping
numeric states as the current authoring model.

Ruby generation resolves active sentences back to states and embeds immutable
records containing both ID and message. `ParseError#error_id` exposes the ID and
the rendered diagnostic prefixes the custom message with it. All existing
structured error fields remain available.

## Consequences

- Message files survive state renumbering when their examples remain errors.
- Reviews show semantic changes explicitly instead of silently matching numbers.
- The updater is bounded and may require a larger explicit budget for unusually
  deep grammars.
- One shortest sentence is retained per reachable error state; applications can
  keep older, non-minimal sentences when those are clearer to humans.
- `ibex-messages v1` remains readable, but new templates and all updates use v2.
