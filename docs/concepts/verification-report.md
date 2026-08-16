---
title: Verification report
description: Validate parser-table artifacts and understand the independent verifier trust boundary.
---

# Scoped generation verification report

Ibex can explicitly render a verifiable generation bundle containing a
data-only parser table, generated Ruby wrapper, scoped verification report,
and generation manifest. This Experimental API is opt-in and is not part of
default CLI generation:

```ruby
require "ibex/verifiable_generation_bundle"

bundle = Ibex::VerifiableGenerationBundle.new(
  automaton,
  wrapper_path: "build/parser.rb",
  wrapper_source: generated_ruby,
  table_path: "build/parser.tables.ibex.json",
  report_path: "build/parser.verification.ibex.json",
  manifest_path: "build/parser.ibex.json",
  source_records: generation_inputs,
  manifest_options: { "table" => "compact" },
  strict: true
)
bundle.publish

Ibex::VerifiableGenerationBundle.validate_file("build/parser.ibex.json")
```

`render` returns the four in-memory artifacts without publishing them.
`publish` passes the complete artifact set and exact input records to the
existing generation transaction. The transaction installs the table and
report, then the parser wrapper, and installs the manifest last as the
coherence marker. Rendering or verification failure changes no target.

## Claims and outcomes

The version 1 report is a closed JSON document described by
[`schema/verification-report-v1.schema.json`](../../schema/verification-report-v1.schema.json).
It records:

- logical input identities, content digests, and byte sizes;
- canonical Grammar IR and Automaton IR digests and the construction
  algorithm;
- the data-only table artifact and payload digests, schema version, and
  representation;
- the Ibex checker version, default or strict profile, requested checks,
  completed checks, and state/item bounds; and
- a distinct `pass`, `violations`, or `exhausted` outcome.

A completed default report names V1, V3, V4, V6, V7, and V8. A completed
strict report additionally names V2, V5, and V9. V9 executes only for IELR
and records a bounded canonical acceptance witness. An exhausted report conservatively
records no completed checks, includes the requested profile and bounds, and
is not a pass. The meanings and limitations of V1-V9 remain those in
[`verifier-trust-boundary.md`](../policy/verifier-trust-boundary.md).

The report's `evidence_digest` covers the complete report except that digest
field itself. Input identities use `input/NNNN/BASENAME`, and the table uses
`table/BASENAME`. These logical identities preserve ordering and artifact
roles without embedding an absolute checkout path. Both forms are closed:
`NNNN` is exactly four decimal digits, a report contains at most 10,000 input
records, and `BASENAME` is one non-empty component other than `.` or `..`
without slash, backslash, or control characters.

The `ir.identity_scope` value `source-logical-v1` defines the versioned digest
scope. Before building the bundle table, Ibex rebuilds an immutable Automaton
IR copy in which every source-location `file` is the corresponding indexed
input identity and every non-null source-provenance `root` is `input`. The
Grammar IR digest, embedded Automaton IR grammar digest, Automaton IR digest,
table source identities, report IR claims, and evidence digest all derive
from that same copy. Every IR source file must map uniquely to
`source_records`; an absent or ambiguous mapping is rejected.

This normalization is limited to the explicit bundle/report boundary. It does
not mutate the supplied Automaton, change diagnostic locations, or alter the
ordinary V002 `TableArtifact.build(automaton)` identity. Lower-level callers
that render a report directly can obtain the required copy with
`VerificationReport.canonical_automaton`; pairing a raw-path table with the
canonical report is rejected as an IR/table mismatch.

## Non-cyclic manifest binding

The report binds input, Grammar IR, Automaton IR, table artifact, and table
payload identities. It deliberately contains neither a manifest path nor a
manifest digest. After the report is rendered, the generation manifest lists
and hashes the table, wrapper, and report. This gives one direction of
dependency:

```text
input + IR -> table -> verification report -> generation manifest
                    wrapper ---------------> generation manifest
```

Adding the manifest digest to the report would require the report hash before
the manifest can be completed and the manifest hash before the report can be
completed. Version 1 rejects that circular format.

`validate_bundle` checks supplied manifest, report, and table bytes without
loading generated Ruby. `validate_bundle_file` additionally resolves all
artifacts from the manifest and verifies every manifest byte count and digest.
Both reject a missing or duplicate report/table/wrapper entry, stale report or
table bytes, mismatched logical table identity, input mismatch, IR/table
identity mismatch, payload mismatch, and an invalid report evidence digest.
Digests detect inconsistency; they are not signatures or authenticity claims.

## Excluded trust surface

This artifact is a **verification report**, not a proof-carrying parser. The
closed `excluded_trust` field always identifies the following boundaries:

- source parsing and normalization into IR;
- semantic derivation or language equivalence from Automaton IR to the
  persisted table (the sidecar receives closed structural validation and
  digest binding only);
- generated wrapper structure and behavior;
- semantic action meaning, safety, termination, and side effects;
- generated or handwritten lexer actions and tokenization;
- the Ruby and Ibex runtime implementations;
- application hooks; and
- grammar unambiguity.

The manifest binds the wrapper's bytes to the same publication, but neither
the report builder nor validator parses, loads, or executes those bytes.
Likewise, the table sidecar exposes opaque production action slots with
`verified: false`. V1-V9 rebuild internal table views but do not consume the
persisted sidecar or prove the builder's Automaton-IR-to-sidecar projection.
A `pass` applies only to the named V1-V9 checks over the supplied Automaton IR
plus the reported structural validation and digest relationships.

The checker, IR validator and serializer, reference collection, set analysis,
table construction/validation, JSON and digest implementations, host runtime,
and publication filesystem remain trusted as documented. Hostile input also
requires outer byte, time, memory, and process limits beyond the two reference
collection bounds.
