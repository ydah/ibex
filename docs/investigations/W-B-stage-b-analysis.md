# Investigation: Stage B analysis tools

## Existing facilities

- Automaton IR embeds normalized Grammar IR, item sets, transitions, actions,
  gotos, default actions, conflicts, entry states, and conflict summaries.
- `IR::Validator::AutomatonDocument` rejects malformed JSON, unknown fields,
  bad references, inconsistent conflict counts, and invalid schema versions.
  It intentionally does not prove that item sets, lookaheads, or actions are
  derivable from the embedded grammar.
- direct LALR is tested against a retained canonical-merge strategy, but both
  are builder implementations and neither validates a supplied Automaton IR.
- `Analysis::Sets` independently computes nullable/FIRST/FOLLOW.
- `TableSimulation::Simulator` executes Automaton IR without loading or
  evaluating semantic actions.
- `Samples` provides deterministic bounded terminal derivation.
- conflict reports, source spans, transactional writes, and IR comparison
  already exist and should be reused by user-facing tools.

Stage B generalizes these assets. It does not replace the builder, the JSON
validator, or the existing property oracles.

## Boundary and affected code

| Area | Responsibility | Stage B rule |
|---|---|---|
| `lib/ibex/lalr/` | construct Automaton IR | verifier must not require or call it |
| `lib/ibex/verify/` | independently derive LR item expectations | deliberate bounded duplication |
| `lib/ibex/equiv/` | compare two read-only grammar/automaton inputs | no semantic execution |
| `lib/ibex/fix/` | enumerate finite source edits and evaluate them | every emitted edit passes bounded equivalence |
| `lib/ibex/diff.rb` | structural report | no core IR changes |
| `lib/ibex/metrics.rb` | deterministic counts | no timing claims |
| `schema/` | report contracts | separate reports; core IR remains frozen |

## Contracts

- analysis consumes existing Grammar/Automaton IR and never mutates its schema;
- semantic actions and user-code sections remain opaque and unexecuted;
- reference collection construction uses explicit queues and state/item
  budgets;
- absence of a counterexample within a bound is never called a proof;
- exit 0 means success within declared bounds, 1 means a concrete violation or
  difference, and 2 means a budget prevented completion;
- the verifier's reference item construction does not call
  `Ibex::LALR::Builder`;
- default reductions are checked after expansion across every terminal,
  including explicit error masks;
- output ordering and JSON bytes are deterministic.

## Choices

| Choice | Benefit | Cost | Decision |
|---|---|---|---|
| rebuild with `LALR::Builder` and compare | short | correlated defects; not independent | reject |
| validate only JSON shape | already implemented | cannot detect semantic table corruption | reject |
| independently construct canonical LR(1)/LR(0) collections | strong V1/V2/V3 oracle | intentional algorithm duplication | use |
| claim unbounded grammar equivalence | attractive wording | undecidable/incorrect | reject |
| bounded samples plus shortest product search | concrete witnesses and honest bounds | may return inconclusive | use |
| evaluate `%expect` and recovery settings as repairs | appears to cover more candidate kinds | neither removes a conflict, so both always fail the repair gate | report separately as explicitly unverified advice |
| rewrite recursion direction or factor source around opaque actions | broader automatic edits | relocating action text can change timing, values, and locations | exclude; keep the action-preserving `%inline` rewrite |
| write one ADR per command | procedural trace | violates the curated ADR scope gate | reject |

The independent-verifier boundary follows existing durable decisions for
versioned IR, a shared downstream pipeline, and bounded nonexecuting analysis.
It does not introduce a new persistence, packaging, execution, or security
boundary, so the command specifications and evidence belong here and in
public reference documentation rather than in a new ADR.
