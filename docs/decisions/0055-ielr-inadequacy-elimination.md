# 0055: Add an IELR inadequacy-elimination backend

- Status: Accepted
- Date: 2026-07-25
- Supersedes: the IELR entry boundary in ADR 0024

## Context

Canonical LR(1) preserves distinct contexts but can have many states. LALR merges every equal LR(0) core and can consequently
introduce conflicts that were absent from canonical LR(1). Direct LALR is now stable, and the standard LR(1)-but-not-LALR
fixture proves this gap. A fourth backend needs LR(1)-equivalent conflict behavior, a state-count bound between LALR and
canonical LR(1), deterministic output, and one Automaton IR identity that downstream tools can distinguish.

## Decision

`algorithm: :ielr` implements conservative inadequacy elimination over canonical LR(1) states. States are candidates for merging
only when they have the same complete LR(0) core. Within one core, a canonical member may gain an action only in a table cell
where it previously had no action; every nonempty member cell must equal the merged cell. This prevents a merge from introducing
or changing a shift/reduce, reduce/reduce, accept, or resolved action choice.

Candidate partitions are then refined until every member has the same symbol-to-target-partition transition signature. The
fixed point makes the quotient a deterministic DFA. Compatible members union their item lookaheads, and all actions, conflict
resolution, default reductions, tables, reports, counterexamples, simulation, and code generation continue through the shared
builder pipeline.

This is the deliberately conservative end of the IELR inadequacy-elimination family: it prefers an extra state over lane-tracing
complexity whenever compatibility is uncertain. It therefore guarantees
`LALR states <= IELR states <= canonical LR(1) states`, but does not promise a minimum IELR state count.

Automaton IR records the backend as `ielr1`; the CLI spelling is `--algorithm=ielr`. The v1/v2 Automaton schemas, explanation
schema, table-simulation schema, IR validator, error-message updater, and conflict explanation CLI all accept that identity.
Unexpected default-LALR conflicts now recommend IELR when it removes at least one unresolved conflict.

Fixtures cover:

- a grammar whose LALR core merge creates reduce/reduce conflicts that IELR and LR(1) avoid;
- a combined grammar where IELR is strictly larger than LALR and strictly smaller than canonical LR(1);
- exhaustive table-simulation equivalence with LR(1) for all terminal sequences through length four in that fixture;
- deterministic property pipelines for all four algorithms; and
- Automaton IR schema round trips.

## Consequences

- Applications can avoid LALR inadequacies without always paying the full canonical state count.
- IELR construction currently starts from canonical LR(1), so Direct LALR remains the default for large conflict-free grammars.
- Conservative compatibility makes correctness and rollback auditable, while future lane tracing can improve merging behind the
  same `ielr1` contract only with equivalent fixtures and benchmark evidence.
- Existing LALR, SLR, and LR(1) output is unchanged.
