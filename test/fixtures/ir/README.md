# Versioned IR fixtures

`grammar-v1.json` and `automaton-v1.json` are intentional schema-v1 regression assets. The golden test compares their
serialized bytes and verifies that each fixture loads and round-trips without change.

`grammar-v2.json` and `automaton-v2.json` capture declaration-free pipeline output. The
`grammar-v1-migrated-v2.json` and `automaton-v1-migrated-v2.json` fixtures pin the explicit version-1 loss record and upgraded
automaton digest. All version-1 fixtures remain frozen when version-2 fixtures are refreshed.

`grammar-v3.json` and `automaton-v3.json` pin an explicit root parser contract and its selected construction facts.
`grammar-v2-migrated-v3.json` and `automaton-v2-migrated-v3.json` prove that migration records historical effective
configuration as unavailable instead of guessing current built-in defaults. The migrated automaton therefore records
`entry_construction` as `unknown`.

After reviewing an intentional version-2 or version-3 change, refresh the generated fixtures with:

```sh
UPDATE_IBEX_IR_FIXTURES=1 bundle exec ruby -Itest test/ir/golden_fixture_test.rb
```

Do not refresh fixtures merely to silence a failure. Never overwrite an older-version fixture for a newer-version change.
A later schema-breaking change requires another schema version and new versioned fixture names.
