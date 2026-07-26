# 0037: Expose versioned, selectable conflict explanations

- Status: Accepted
- Date: 2026-07-24

## Context

The automaton report contains every state as well as conflict witnesses, which is useful for archival inspection but cumbersome
when a developer is investigating one state or lookahead. Automaton IR and the bounded counterexample search already contain the
necessary facts. A dedicated command therefore does not need another parser algorithm, mutable debugger state, or an IR change.

ADR 0035 deferred a separate `explain` command because the report already carried the information. The need for deterministic
selection, machine-readable output, and a focused step-by-step view now justifies a thin command over those existing contracts.

## Decision

Add `ibex explain` as a read-only view over a freshly built Automaton IR and
`Ibex::LALR::Counterexample`. It supports all deterministic construction algorithms, racc and extended frontend modes, optional
state and token selectors, text or JSON output, and the existing positive counterexample search budgets. State and token
selectors may be combined and select their intersection. The view filters conflicts before calling the selected-conflict
counterexample API, so excluded conflicts consume no search budget; the existing all-conflict API remains compatible.

A token selector first matches the unique canonical Grammar IR symbol name. Only when no canonical name matches does it match an
exact `display_name`. Duplicate display names are rejected with the sorted canonical candidates rather than selecting one.
Unknown states and tokens are usage errors. A valid selector whose intersection contains no conflict, and an automaton with no
conflicts, are successful empty results.

Text output numbers the selected conflicts and presents witness reachability, competing actions, the recorded resolution, and
both derivations. When bounded search does not find one sentence accepted through both actions, the existing deterministic
nonunifying reachability witness is shown and identified as such.

JSON output is the public `explain` version-1 analysis shape described by `schema/explain-v1.schema.json`. The document records
the algorithm, resolved selectors, budgets, counts, conflicts, canonical and display symbol names, resolutions, witnesses, and
derivation trees. It is not Grammar or Automaton IR and does not change either IR schema version. JSON is the only stdout content;
option, file, grammar, and selector diagnostics go to stderr. Successful empty and nonempty views exit zero, while diagnostics
exit one.

The common CLI boundary converts all `SystemCallError` file failures, including missing, unreadable, and directory input paths,
to one stderr diagnostic and exit one. Such failures do not write partial analysis output to stdout.

This decision supersedes only ADR 0035's boundary against adding a separate `explain` command. The stable runtime-event
prerequisite for the interactive debugger and production/state coverage remains in force.

## Consequences

- Developers can isolate one conflict without reading an entire automaton report.
- Automation can validate and consume a stable JSON document without treating an analysis view as pipeline IR.
- Canonical names remain unambiguous while display names remain convenient and explicit in output.
- A nonunifying witness means bounded search did not find a shared sentence; the existing search does not claim whether a larger
  budget would find one.
