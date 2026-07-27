# Versioned CST fixtures

`valid-v1.json` and `invalid-utf8-v1.json` are byte-stable `ibex_cst` schema-v1
documents. The second fixture stores invalid UTF-8 source bytes through the
required `{"b64": ...}` representation.

After reviewing an intentional schema-v1 serialization change, refresh these
fixtures with:

```sh
UPDATE_IBEX_CST_FIXTURES=1 bundle exec ruby -Itest test/runtime/cst_serialize_test.rb
```

Do not refresh fixtures merely to silence a failure. A breaking document change
requires a new schema version and new fixture names.
