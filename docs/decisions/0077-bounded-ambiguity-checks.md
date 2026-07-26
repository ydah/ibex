# ADR 0077: Check ambiguity through bounded conflict searches

- Status: Accepted
- Date: 2026-07-26

## Context

Conflict counts alone do not tell users whether two parser actions accept the same complete sentence. LALR merging can introduce
a conflict that is absent from canonical LR(1), while precedence may intentionally resolve a genuinely ambiguous grammar.
Unbounded context-free ambiguity is undecidable, so a command that claims proof from a finite search would be misleading.

## Decision

`ibex check --ambiguity GRAMMAR` runs the existing paired conflict-configuration search for every recorded parser conflict. Each
search has explicit sentence and configuration budgets, configurable with `--max-tokens` and `--max-configurations`. The default
algorithm is LALR; `--algorithm=lr1` is available when users want to exclude LALR merge artifacts.

The command has three outcomes:

- `ambiguous` (exit 1): at least one complete sentence was accepted through two conflict interpretations;
- `inconclusive` (exit 2): no ambiguity was found before at least one configuration budget was exhausted;
- `no_ambiguity_found_within_bounds` (exit 0): no unifying sentence was found within the declared bounds.

The last outcome is deliberately not called “unambiguous.” Text output states the budgets and explored configurations. JSON
output is versioned with `ibex_check: "ambiguity"` and retains every conflict result, sentence, lookahead position,
interpretations, explored count, and exhaustion flag. The existing report and `explain` counterexamples keep their compatible
fallback witnesses.

## Consequences

- CI can fail on a concrete ambiguity and distinguish search exhaustion from a clean bounded run.
- Users can reproduce and raise either budget without changing parser generation.
- Canonical LR(1) remains the answer for suspected LALR-only conflicts.
- The command makes a useful bounded claim without pretending to decide arbitrary grammar ambiguity.
