# JSON error UX evidence

This report fixes the Phase 14 error-experience baseline against ten malformed
inputs for the gallery JSON grammar. It is generated from
[`json-errors-v1.json`](../test/fixtures/error_ux/json-errors-v1.json) by:

```sh
bundle exec ruby tool/error_ux_snapshot.rb
```

Use `--write` only after reviewing a deliberate diagnostic, parser-table, racc,
or repair-policy change. CI regenerates the evidence and requires byte-for-byte
equality.

## Comparison method

Ibex uses [`examples/json.y`](../examples/json.y), including its handwritten
lexer locations. The comparison uses the self-authored compatible grammar
[`json_racc.y`](../test/fixtures/error_ux/json_racc.y), racc 1.8.1, and only the
public `racc` executable and `on_error(token, value, value_stack)` callback.
Neither racc implementation files nor generated source are inspected. Both
parsers receive the same source strings and equivalent token streams.

The racc column records the neutral callback wrapper's token argument. It does
not claim that an application cannot build richer diagnostics around racc; it
shows what the compared parser runtime exposes at that boundary without an
additional state-to-message layer.

| Case | Invalid source | Ibex diagnostic evidence | racc callback | Selected repair | Useful |
|---|---|---|---|---|---|
| EUX-01 | `{"a":,}` | line 1, column 6; 7 expected values; caret | token 9 | delete `,`, insert `STRING` | yes |
| EUX-02 | `{"a" 1}` | line 1, column 6; expected `:`; caret | token 3 | insert `:` | yes |
| EUX-03 | `{"a":1,}` | line 1, column 8; expected `STRING`; caret | token 8 | insert a complete member | no |
| EUX-04 | `[1,]` | line 1, column 4; 7 expected values; caret | token 12 | insert `STRING` | no |
| EUX-05 | `[1 2]` | line 1, column 4; expected `,` or `]`; caret | token 3 | insert `,` | yes |
| EUX-06 | `{"a":[true false]}` | line 1, column 12; expected `,` or `]`; caret | token 5 | insert `,` | yes |
| EUX-07 | `{"a":null "b":2}` | line 1, column 11; expected `}` or `,`; caret | token 2 | insert `,` | yes |
| EUX-08 | `{]` | line 1, column 2; expected `STRING` or `}`; caret | token 12 | replace `]` with `}` | yes |
| EUX-09 | `[}` | line 1, column 2; 8 expected values/closer; caret | token 8 | replace `}` with `]` | yes |
| EUX-10 | `true false` | line 1, column 6; expected EOF; caret | token 5 | delete extra `FALSE` | yes |

The committed JSON is the normative snapshot and also retains exact messages,
LR states, expected-token arrays, token values, repair costs, configuration
counts, and edit positions. Its public structure is validated by
[`schema/error-ux-v1.schema.json`](../schema/error-ux-v1.schema.json).

## SP-4 decision

The bounded insertion/deletion/replacement search produced a completing plan
for all ten cases. Eight plans are reasonable representations of the likely
human edit; two trailing-comma cases invent a missing value/member where
deleting the comma would usually be preferable. The measured useful rate is
therefore **8/10 (80%)**, above the required majority.

SP-4 is **go** for the existing opt-in bounded single-plan repair described by
[ADR 0053](decisions/0053-bounded-minimum-cost-runtime-repair.md). It remains
experimental: a selected edit can require a nil semantic value, and the search
does not enumerate every equal-cost CPCT+ repair. The stable default answer
remains exact expected tokens plus explicit yacc/synchronization recovery.
