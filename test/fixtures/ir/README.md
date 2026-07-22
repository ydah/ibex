# Versioned IR fixtures

`grammar-v1.json` and `automaton-v1.json` are intentional schema-v1 regression assets. The golden test compares their
serialized bytes and verifies that each fixture loads and round-trips without change.

After reviewing an intentional schema-compatible change, refresh both files with:

```sh
UPDATE_IBEX_IR_FIXTURES=1 bundle exec ruby -Itest test/ir/golden_fixture_test.rb
```

Do not refresh the fixtures merely to silence a failure. A schema-breaking change requires a new schema version and new
versioned fixture names.
