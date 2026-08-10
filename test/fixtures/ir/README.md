# Current IR fixtures

`grammar.json` and `automaton.json` are the sole Grammar and Automaton IR
fixtures. They pin the current schema and the root parser contract used by the
pipeline.

After reviewing an intentional current-format change, refresh the generated
fixtures with:

```sh
UPDATE_IBEX_IR_FIXTURES=1 bundle exec ruby -Itest test/ir/golden_fixture_test.rb
```

Do not refresh fixtures merely to silence a failure. A later schema-breaking
change requires an explicit compatibility decision before introducing another
reader.
