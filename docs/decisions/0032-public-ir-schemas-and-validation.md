# ADR 0032: Publish IR schemas and validate documents before construction

- Status: Accepted
- Date: 2026-07-23

## Context

Grammar IR and Automaton IR already have stable version-1 JSON envelopes and golden fixtures, but consumers have had to infer
their complete shape from Ruby constructors. `Serialize.load` is intentionally a small trusted-data loader; malformed objects
can therefore expose `KeyError`, `NoMethodError`, or `TypeError` instead of a positioned Ibex diagnostic. JSON Schema alone also
cannot express identity and reference constraints such as production-to-symbol or transition-to-state links.

The version-1 contract has gained compatible optional fields: symbol `display_name` and `semantic_type`, and top-level
`user_code_chunks`. Expansion origins written by current Ibex versions include an `expression`, but early version-1
documents did not; readers must therefore treat that field as optional. Warning type names are an extensible vocabulary,
while warning record fields remain fixed.

## Decision

Ibex publishes `schema/grammar-ir-v1.schema.json` and `schema/automaton-ir-v1.schema.json` as JSON Schema Draft 2020-12
documents. The schemas describe every serialized version-1 record, include the optional additive fields, reject unknown record
fields, and retain an open warning `type` string. Automaton Schema references Grammar Schema because Automaton IR embeds the
complete Grammar IR document. Both files ship in the gem without adding a runtime schema-library dependency.

`Ibex::IR::Validator.validate(source)` is the untrusted-input boundary. It parses JSON, verifies the discriminator and version,
checks the same structural types represented by the schemas, and enforces constraints JSON Schema cannot express:

- symbol, production, and state ids match their array positions;
- `$eof` and `error` retain reserved ids 0 and 1;
- start, production, precedence, warning, item, lookahead, table, action, and conflict references resolve to the required kind;
- LR item dot positions are valid for their production;
- an automaton contains at least one state and its grammar digest is the SHA-256 digest of the canonical serialized embedded
  grammar;
- reduce/reduce conflicts contain at least two distinct alternatives and their chosen production is one of those alternatives;
- conflict summary counts and expectations agree with the recorded conflicts and embedded grammar;
- action named references stay within the production/action context.

After validation it delegates construction to `Serialize.load` and returns the resulting Grammar or Automaton object. JSON
structure errors without source locations use the stable synthetic position `(ir):1:1`; no Ruby collection exception crosses
the public boundary. Every CLI `--from` path and the IR-oriented subcommands use this boundary. `Serialize.load` remains
available for already-trusted version-1 documents.

The schemas are checked against the Draft 2020-12 metaschema in the development test suite. The same tests resolve the
Automaton-to-Grammar schema reference and apply the schemas to the golden documents and the legacy expansion-origin fixture.
Metadata control-character fixtures keep the schema and the in-process validator's accepted strings aligned.
`json_schemer` is consequently a development dependency only; loading Ibex does not require it.

## Consequences

- Editors, CI systems, and non-Ruby consumers can validate IR shape from a published, dependency-free contract.
- Applications accepting external IR can get consistent `Ibex::Error` failures and reference-integrity checks.
- The hand-written validator and public schemas must change together when a compatible field is added.
- Cross-record invariants such as digest equality and conflict-summary consistency remain validator responsibilities because
  JSON Schema cannot express them.
- Version 1 validation parses the source for structural checks and `Serialize.load` parses it again for construction. It also
  does not impose a byte-size limit. This API is intended for bounded local and CI artifacts; callers accepting untrusted
  network input must impose an input limit before validation. A future version may add a size-limited, single-parse
  construction path.
- Incompatible record or semantic changes still require a new schema version and new schema filenames.
