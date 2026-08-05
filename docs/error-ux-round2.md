# Error UX evidence round 2

H003 expands repository-owned diagnostic and repair evidence beyond R001's ten
JSON cases. The machine-readable result is
[`error-ux-round2-v1.json`](error-ux-round2-v1.json), validated by
[`error-ux-round2-v1.schema.json`](../schema/error-ux-round2-v1.schema.json).
It does not replace or revise the R001 snapshot, rubric, review records, or
release gate.

## Status and authority

The deterministic repository capture is **complete**. The external subjective
gate is separately **HOLD**: there are no external review records, and every
case has `status: pending` with an empty label list. Repository observations
cannot be promoted into external `useful`, `misleading`, `unsafe`, or `unclear`
labels.

The immutable machine capture intentionally has no slot for later subjective
labels. H003's separate
[`review status registry`](error-ux-round2-review-status-v1.json) and
[`review schema`](../schema/error-ux-round2-review-v1.schema.json) provide that
pathway without rewriting the capture. The registry binds the exact capture
SHA-256 and required case inventory. It remains `HOLD` with `records: []`.

The fixed corpus covers these distinct dimensions:

| Case | Shape | Observation | Fresh reparse |
| --- | --- | --- | --- |
| `H003-DELIMITER-01` | nested delimiter-heavy calls | mismatched closer | accepted |
| `H003-STATEMENT-01` | assignment statement | missing semantic value | accepted |
| `H003-STATEFUL-01` | stateful string lexer | EOF in the string state | accepted |
| `H003-EOF-01` | delimiter EOF | missing closer | progress; the proposed edit over-closes |
| `H003-MULTI-01` | synchronized statements | two errors at distinct offsets, then continuation | accepted |
| `H003-UNKNOWN-01` | external token adapter | unknown token after a complete word | accepted |
| `H003-LEXER-01` | generated lexer | no matching lexer rule | accepted |

Indentation-sensitive input is explicitly `excluded-unimplemented`. Ibex has
no indentation-tokenization contract, so the corpus does not simulate one.

## Capture semantics

Each case binds the grammar and input digests, exact runtime expected tokens,
full diagnostic message, source line and caret, bounded repair result, a
repository-authored byte-range edit, the outcome of applying that edit and
parsing with a fresh parser, semantic-value risk, and external-review state.
The capture also binds the exact frontend, normalization, code generator,
runtime parser, generated lexer, repair implementation, and H003 generator
source bytes used to produce those observations.

Parser expected-token arrays come directly from the existing runtime API. A
generated-lexer failure occurs before a parser state exists, so its exact array
is empty with the closed reason
`lexer-failure-precedes-parser-state`; it is not presented as a parser
prediction. Runtime repairs remain distinct from proposed source edits.
Insertion can supply nil, replacement retains the original runtime value, and
deletion can discard intent. A successful fresh parse establishes syntax only,
not that an invented literal, deleted token, or replacement matches the user's
intended semantics.

The multi-error case overrides the normal error hook only to record the same
runtime token, expected-token, state, and location fields while allowing the
grammar's explicit `error ';'` synchronization path to continue. The committed
capture requires at least two diagnostics at strictly increasing byte offsets
and a non-nil result after recovery; it cannot be satisfied by duplicating one
error.

## Trust boundary

The capture compiles and executes generated lexer and parser action code.
Execution is allowlisted to the four repository-owned fixtures under
`test/fixtures/error_ux_round2/`. It does not download or execute external
grammars, reviewer payloads, or user-supplied code. These fixtures are trusted
test programs, not a sandbox claim.

The existing R001 normative snapshot is bound to its unchanged SHA-256. H003
generation fails if those bytes change. H003 uses its own corpus, schema,
evidence ID, generator, and quality gate so comparative R001 evidence and this
repository study cannot silently become duplicate authorities.

## Limits and kill conditions

This evidence has no external workloads or reviewers, observes one bounded
repair plan rather than every equal-cost plan, and does not infer intent from
acceptance. It must fail closed when fixture/corpus bytes drift, a required
dimension disappears, R001 changes, review state is overstated, synchronized
diagnostics collapse, or the committed fresh-reparse outcome changes.

The same quality gate validates the external registry fail-closed. `PASS`
requires at least two complete, independent, external records from
reviewers whose names remain distinct after Unicode NFKC normalization, full
case folding, trimming, and whitespace collapse. Every record must assess all seven cases with a
label, rationale, and semantic-value risk assessment. If reviewer labels
differ, every reviewer-pair disagreement must remain explicit rather than
being reduced to a majority conclusion. See the
[`records workflow`](error-ux-round2-reviews/v1/records/README.md).

Independence and identity remain human attestations: schema validation can
require the declarations and reject duplicate normalized names, but cannot
prove who authored a review. A record must never be added merely to clear the
gate. Evidence drift, incomplete case coverage, duplicate reviewer identity,
or missing disagreement entries kills `PASS`.

Regenerate only after reviewing intentional parser, lexer, diagnostic, or
repair changes:

```sh
bundle exec ruby tool/error_ux_round2.rb --write
bundle exec rake quality:error_ux_round2
```

The ordinary quality command never writes evidence.
