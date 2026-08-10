# Effective configuration reports

`ibex config` explains every key in `Ibex::Configuration::Registry` without generating or loading a parser:

```console
ibex config grammar.y
ibex config --format=json grammar.y
ibex config --from=grammar-ir --format=json grammar.json
```

The command has a `static-no-user-code` trust boundary. For grammar source it uses the contained source resolver, so
the root grammar and its import closure are parsed as data while parent traversal, absolute imports, glob imports,
and symlink escapes are rejected. Parser actions, lexer actions, user-code sections, and generated parser classes are
never executed or required. Grammar IR input is accepted only through the normal versioned IR validator.

Each setting reports its effective value, owner, override policy, origin and source location when recorded,
explicit or implicit selection, canonical or noncanonical conformance, recording status, and source evidence.
Evidence is classified as `accepted`, `ignored`, `duplicate`, or `conflicting`. The JSON projection is deterministic,
uses schema version 1, and always lists canonical keys in lexical order.

The current Grammar IR `parser_contract` entries are authoritative for `parser.algorithm`, `parser.entries`, and `cst.trivia`.
A matching command-line request is retained as accepted evidence. A contradictory request produces a positioned,
structured conflict report and exits nonzero. An unspecified entry remains explicitly `unspecified`; a document without
the current contract is rejected. A current builtin or CLI value is never presented as a historical fact.

The source grammar syntax supports the root-only declarative parser block in extended mode. CST ownership is
declared as `cst_trivia leading|balanced|drop` and requires `pragma cst`; `ibex config` reports the resulting
value and source location without executing user code. It does not recognize generic or unknown settings.
