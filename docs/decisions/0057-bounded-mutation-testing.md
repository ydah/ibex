# 0057: Bound mutation testing to compact table construction

- Status: Accepted
- Date: 2026-07-25
- Supersedes: the mutation-testing boundary in ADR 0024

## Context

Mutation testing is useful only when its subject and test ownership are explicit. Running it over the whole library would multiply
the normal matrix cost, mix subprocess and filesystem integration tests into mutation selection, and make routine CI duration
unpredictable. The maintained Mutant Minitest integration supports MRI 3.2 through 4.0 and permits free use for public
open-source repositories, while Ibex still supports Ruby 3.0 and 3.1.

## Decision

Mutation tooling lives in `gemfiles/mutation.Gemfile` rather than the default dependency set. CI runs it on MRI 4.0 with the
open-source usage declaration, a ten-minute job timeout, two workers, and the single matcher
`Ibex::Tables::Compact#initialize`.
`TablesTest` owns that matcher through Mutant's Minitest coverage declaration. Normal test runs neither load Mutant nor change
their selection; `.mutant.yml` sets `IBEX_MUTATION=1` only inside the mutation environment. The deterministic subject has a
one-second per-mutation timeout; a timeout counts as a kill because every selected baseline test completes well below that bound
and generated infinite loops are valid observable failures.

The initial subject is the compact row-displacement layout constructor because its immutability contract is deterministic,
side-effect free, central to shareable generated parser tables, and can be specified without semantically equivalent lookup
mutations. Expanding the matcher requires a reviewed test owner, zero surviving non-equivalent mutations, a measured CI duration
within the same ten-minute budget, and an update to this ADR.

Ruby 3.0 and 3.1 remain supported library runtimes. Mutation testing is a development analysis performed on one current MRI; its
isolated Gemfile prevents Mutant's newer interpreter floor from changing installation or CI compatibility for the gem.

## Consequences

- Every push checks that focused table tests kill the selected core mutations.
- The mutation dependency cannot constrain application dependencies or the supported Ruby matrix.
- The bounded matcher and timeout make a surviving mutation actionable instead of producing an unowned whole-library report.
