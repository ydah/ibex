# ADR 0087: Make IELR advice explicit

- Status: Accepted
- Date: 2026-07-27
- Supersedes: the automatic-advice trigger in ADR 0020

## Context

An unexpected LALR conflict was reported immediately and then caused the CLI
to build a complete IELR automaton solely to determine whether it could print
an advisory note. On the public Nokogiri CSS grammar that second construction
dominated generator time. It did not change the conflict, generated parser,
exit status, or strict-warning result.

Paying an algorithm-sized cost for optional advice on every affected
generation makes an ordinary build unpredictable. Omitting the conflict itself
or guessing whether IELR helps would weaken diagnostics.

## Decision

Unexpected conflicts continue to be reported during ordinary generation.
The exact second build and the resulting advice run only when the caller passes
`--suggest-ielr`. Explicit IELR generation remains available through
`--algorithm=ielr`.

The canonical closure worklist also advances by index instead of shifting its
Array, avoiding repeated prefix movement during requested IELR and LR(1)
construction.

## Consequences

- Ordinary generation performs one selected automaton construction.
- `--suggest-ielr` retains exact avoided-conflict counts and may take roughly
  as long as an additional IELR build.
- CI that wants the advice can request it explicitly without changing output
  or exit semantics.
- ADR 0020 remains in force for deterministic output and advisory-only
  behavior; only its automatic trigger is replaced.
