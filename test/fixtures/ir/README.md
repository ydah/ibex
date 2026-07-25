# Versioned IR fixtures

`grammar-v1.json` and `automaton-v1.json` are intentional schema-v1 regression assets. The golden test compares their
serialized bytes and verifies that each fixture loads and round-trips without change.

`grammar-v2.json` and `automaton-v2.json` capture current pipeline output. The
`grammar-v1-migrated-v2.json` and `automaton-v1-migrated-v2.json` fixtures pin the explicit version-1 loss record and upgraded
automaton digest. All version-1 fixtures remain frozen when version-2 fixtures are refreshed.

After reviewing an intentional version-2 change, refresh the version-2 files with:

```sh
UPDATE_IBEX_IR_FIXTURES=1 bundle exec ruby -Itest test/ir/golden_fixture_test.rb
```

Do not refresh fixtures merely to silence a failure. Never overwrite the version-1 files for a version-2 change. A later
schema-breaking change requires another schema version and new versioned fixture names.
