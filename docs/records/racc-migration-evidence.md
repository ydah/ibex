# Racc migration evidence

This page is the H002 evidence index for the compatibility claims in
[`racc-migration.md`](../guides/racc-migration.md). It records observable behavior only;
it does not claim that a third party has adopted Ibex, and it is not a
performance result.

## Evidence boundary

The three public migration suites are pinned in
[`release-readiness.md`](../policy/release-readiness.md): Namae, BCDice, and Nokogiri.
Their revisions, adapters, and observed test counts are release evidence.
The rows below are repository-owned black-box probes that target compatibility
risks which are easy to miss in a single arithmetic grammar. They run against
the installed `racc` executable when it is available and skip otherwise; a
skip is not reported as a pass.

| Risk | Probe and observable contract | Reproduction |
|---|---|---|
| precedence and conflict accounting | arithmetic results match; resolved conflicts remain visible in Automaton IR but do not inflate the CLI conflict count or `expect` | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| empty productions and string tokens | empty reductions and literal-token paths produce the same public result values | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| `convert` and `no_result_var` | token conversion and result-variable suppression preserve the generated parser's public action behavior | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| inline actions | action placement and returned semantic values are equivalent at the public parser boundary | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| `expect` and dangling-else behavior | the expected conflict count and parse result remain stable for the ambiguous grammar | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| error recovery and `on_error` | callback arguments and recovered result values are compared; the documented undeclared-token difference remains explicit | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| source locations and line conversion | semantic action line mapping follows the documented default and `--line-convert-all` modes | `bundle exec ruby -Itest test/racc_migration_test.rb` |
| runtime initialization and value-stack reads | an initializer that omits `super` retains application state while historical value-stack reads remain compatible | `bundle exec ruby -Itest test/racc_migration_test.rb` |
| unqualified `ParseError` | parser methods and actions can retain the explicit rejection path through `Runtime::Parser` lookup | `bundle exec ruby -Itest test/racc_migration_test.rb` |
| large grammar construction | a 500-production grammar completes with the recorded production/state bound and no conflicts | `bundle exec ruby -Itest test/compat/black_box_test.rb` |
| push-parser runtime contract | push-session lifecycle, token feeding, acceptance, and cleanup remain stable within Ibex's public runtime API | `bundle exec ruby -Itest test/runtime/push_parser_test.rb` |

The compatibility test files are the executable source of truth. The commands
above were last run at the evidence refresh and produced zero failures and zero
errors (black-box: 6 runs/33 assertions; migration: 5 runs/20 assertions;
push-parser: 46 runs/183 assertions). The black-box suite reported no skip in
that environment.

## Interpretation

These probes establish coverage of distinct compatibility risks, not a claim
that every racc grammar is interchangeable. Generated source layout, internal
table arrays, `require "racc/parser"` replacement, and previously generated
racc table loading remain explicitly out of scope. Formal cross-project
performance comparison is tracked separately in the release-readiness report
and remains incomplete until a clean, exact-revision artifact is published.
