# Investigation: conflict-repair baseline

## First measurement

The committed baseline contains twenty unresolved shift/reduce conflicts:
two are produced by removing precedence declarations from the repository's
clean-room `calc` and `sql-lite` gallery grammars, and eighteen are synthetic.
The synthetic cases vary direct recursion, grouping, and a separate primary
rule. They deliberately retain yacc's default shift behavior so that a safe
right-associative declaration can preserve the bounded action and reduction
trace.

With 10 bidirectional samples, a maximum witness length of 8 tokens, and
50,000 product configurations, `ibex fix` emitted at least one proposal for
20/20 cases (100.0%). Every emitted proposal also passed independent table
verification. The measurement is reproducible through `rake fix:test`; its
case-level result is fixed in `test/fixtures/fix/baseline.json`.

## Interpretation and next target

This is a capability and regression baseline, not a population estimate:
the corpus has three related expression-conflict shapes and only two
gallery-derived cases. It does not justify a general “100% repair rate” claim.
The next measurement must add reduce/reduce, LR(1)-but-not-LALR, dangling
optional clauses, and common-prefix conflicts without deleting these cases.
Until that broader corpus exists, the declared target is no regression below
20/20 on this fixed corpus; broader success is reported without a target.

## Safety evidence

- candidates that retain the target or increase another conflict are rejected;
- resulting Automaton IR must pass the independent verifier;
- bounded language and mapped reduction-tree comparison must both find no
  difference;
- semantic action text is never evaluated;
- a configured message catalog is evaluated against the original table, and
  newly moved, uncovered, or unreachable entries are included per proposal;
- any incomplete equivalence search is reported as budget exhaustion, not as a
  safe proposal.
