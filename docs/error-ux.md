---
title: Error experience evidence
description: Bounded diagnostics, repair behavior, and the evidence boundary for parser errors.
---

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

## Independent review gate

The fixed observations include a maintainer repair assessment. They do not
include an independent diagnostic or repair assessment.

<!-- r001-review-status:start -->
R001: `HOLD` — [`awaiting_independent_review`](error-ux-review-status-v1.json).
<!-- r001-review-status:end -->

Third-party reviewers use the versioned
[`rubric`](error-ux-review-rubric-v1.md) and closed
[`review-record schema`](../schema/error-ux-review-v1.schema.json). Run:

```sh
bundle exec rake quality:error_ux_review_kit
bundle exec rake quality:error_ux_review_status
bundle exec ruby tool/error_ux_review.rb template review.json
```

The generated payload contains the reviewer identity, reviewed maintainer
roster, structured consent, labels, rationales, and disagreements, but no
permalink. Publication metadata is kept separately in the status registry so a
reviewer can commit the final payload without a self-referential SHA. The first
command verifies the immutable snapshot, corpus identities, schema, local
byte/digest bindings, reports, claims, and truthful status entirely offline
while allowing the expected HOLD in ordinary CI.

`bundle exec rake release:error_ux_review` is the separate promotion gate and
returns nonzero until a valid published external payload exists. When PASS is
claimed, it additionally fetches the full-SHA blob without redirects, compares
the exact imported bytes, and requires the source repository owner, GitHub
commit API author, status publisher login, and reviewer login to agree
case-insensitively. This verifies control of the named GitHub namespace and
GitHub account metadata, not a cryptographic identity or signature. Network or
account-metadata uncertainty fails closed. Neither path changes the normative
observation fixture.

## Comparison method

<!-- comparative-evidence:racc-error-ux-json-v1:start -->
At Ibex revision cc20c5eb799cc218ebea665df64261f10d030f75, on ten fixed malformed
JSON inputs with the Ruby, OS, CPU, kernel, processor-count, and YJIT environment unrecorded,
the committed result artifact records Ibex diagnostics,
Racc 1.8.1's public on_error callback values, and a maintainer assessment of ten bounded repairs;
independent subjective review is pending, so this is not a completed comparative UX claim.

Evidence record ID: `racc-error-ux-json-v1`. The observations and assessment
are registered in [`claims.yml`](claims.yml), including every unrecorded
environment field and the still-pending independent review.

Ibex uses [`examples/json.y`](../examples/json.y), including its generated
lexer locations. The migration from its previous handwritten lexer is guarded
by exact location and error-snapshot tests. The comparison uses the self-authored compatible grammar
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
[ADR 0012](decisions/0012-bounded-nonexecuting-analysis.md). It remains
experimental: a selected edit can require a nil semantic value, and the search
does not enumerate every equal-cost CPCT+ repair. The stable default answer
remains exact expected tokens plus explicit yacc/synchronization recovery.
<!-- comparative-evidence:racc-error-ux-json-v1:end -->
