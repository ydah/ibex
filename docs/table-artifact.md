# Data-only parser table artifact

The table artifact is an Experimental, separately versioned JSON sidecar for
inspecting and recognizing parser token streams without parsing or loading
generated Ruby. Version 1 is a prototype persistence and execution boundary;
it is not accepted directly by the current parser runtime and is not part of
the Stable generated-parser ABI.

Load the prototype explicitly:

```ruby
require "ibex/table_artifact"

document = Ibex::TableArtifact.build(automaton, representation: :compact)
loaded = Ibex::TableArtifact.load(document.dump)
result = Ibex::TableArtifact::Executor.new(loaded).recognize([number_token_id])
result.accepted?
```

`recognize` consumes internal terminal IDs. It does not lex source text,
convert external token values, run semantic actions, build semantic values, or
perform recovery search. Callers may select a named entry and must treat
`max_steps` as the execution bound for hostile or cyclic input.

## Authority and representation

The artifact is executable table authority for its limited recognition
profile. The executor reads its actions, defaults, GOTOs, productions, and
entry states directly; it does not reconstruct an automaton or call the parser
builder. This is the execution benefit over retaining only Automaton IR.

The canonical payload contains:

- all symbol and terminal names, display names, and internal IDs;
- entry names and initial states;
- signed action codes, GOTOs, and default actions in either closed sparse rows
  or row-displacement arrays;
- production left sides, right sides, stack lengths, and opaque action slots;
- static CST kind/field metadata and recovery declaration IDs;
- Grammar IR, Automaton IR, whole-payload, CST-metadata, and recovery-metadata
  SHA-256 identities; and
- static byte, occupied-cell, lookup, and recognition-cost descriptions.

Signed action codes use `0` for accept, `-1` for error, `1 + state` for shift,
and `-2 - production` for reduce. Artifact schema version 1 pins those meanings
to parser-table format version 6. This is a semantic identity, not a claim that
the JSON object has the Ruby hash/object shape accepted by the v6 runtime.

Objects are serialized with recursively sorted string keys. Array order is
part of the format and is either semantic or validated as canonical. The
authoritative closed contract is
[`schema/table-artifact-v1.schema.json`](../schema/table-artifact-v1.schema.json),
and the Ruby loader additionally checks referential and canonical invariants
that JSON Schema cannot express.

`canonical_payload_bytes` is the exact byte count of compact canonical JSON for
the payload only. Compact lookup is an O(1) row-displacement probe; plain sparse
rows use O(log row width) binary search. These complexity strings and the
occupied-cell counts are static descriptions. `measurement: not-measured`
means none of them is a
wall-clock, allocation, RSS, or end-to-end parser benchmark.

## Validation and trust boundary

The loader applies a 16 MiB default byte bound, parses JSON, rejects unknown
fields, checks table encodings and references, recomputes payload/CST/recovery
digests and static cost fields, then deeply freezes the document. It never
loads generated classes or evaluates action strings. Semantic action slots are
production-ID bindings with `verified: false`; action bodies are deliberately
absent.

The grammar and automaton digests are provenance linkage claims copied from
the builder input. An artifact alone cannot recompute either source object or
establish its authenticity. A caller that has the source IR must recompute and
compare those digests, and a publication system must separately authenticate
the artifact. Digests detect inconsistency; they are not signatures.

The validator checks structural and internal table consistency. It does not
prove that the table implements a claimed grammar, that CST or recovery
metadata was derived correctly, or that the parser runtime and semantic
actions are correct. The separately recomputed CST and recovery digests make
those metadata regions explicit identities for later bundle binding, but do
not make them independently true.

This does not extend the claims of [`ibex verify`](verifier-trust-boundary.md).
Default and strict verification still rebuild tables from Automaton IR; strict
still adds collection-completeness checks only. Neither mode consumes this
sidecar. A later bundle report may bind verified IR, this table identity, a
wrapper, and a manifest without changing that distinction.

## Compatibility and stop-condition result

The prototype is intentionally absent from the default `ibex` require path,
the generator CLI, `Codegen::Ruby`, generated constants, and `ibex-runtime`.
Existing generation therefore emits byte-for-byte the same output when the
feature is not explicitly used, and runtime packaging has no new dependency.

The V002 stop conditions do not apply to this scoped adoption:

- wrapper/table separation does not change the Stable ABI because the sidecar
  is separate Experimental data;
- direct bounded recognition supplies execution value beyond duplicating
  Automaton IR; and
- action bodies remain opaque wrapper authority, so loading or parsing them is
  not required.

Promoting the sidecar into generated output, accepting it in `ibex-runtime`,
binding action calling conventions, or promising compatibility beyond schema
version 1 requires a separate compatibility decision and migration plan.
