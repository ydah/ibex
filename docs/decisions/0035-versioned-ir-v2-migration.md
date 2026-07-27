# ADR 0035: Upgrade generated IR to version 2 without rewriting version 1

- Status: Accepted
- Date: 2026-07-25

## Context

Grammar composition, parameterized and inline rule expansion, rule documentation, and lossless multi-file source handling need
metadata that Grammar IR version 1 cannot represent. Adding those records to version 1 would make its previously byte-stable
contract ambiguous. Automaton IR embeds Grammar IR and hashes its canonical serialization, so the two document kinds must move
together. Existing checked-in artifacts and external consumers still need deterministic version-1 reads.

Those frontend extensions therefore require an explicit schema-version plan.

## Decision

New `Normalizer` and builder results use schema version 2. `Ibex::IR::Grammar` and `Ibex::IR::Automaton` retain
`schema_version` per instance, and the loader and untrusted validator accept versions 1 and 2 while rejecting every other
version. Loading and dumping a valid version-1 document preserves its bytes and never injects version-2 fields.

Grammar IR version 2 adds nullable but explicit metadata keys:

- grammar `source_provenance` stores an optional file, source root, and zero-based byte span;
- symbol and production `doc` fields reserve documentation without requiring the current frontend to invent it;
- production `expansion` can retain parameter arguments, an inline-rule origin, and a cross-file include chain;
- action `composition` can retain an ordered sequence of rule and inline fragments; and
- grammar `migration` records the source version and metadata that an upgrade could not reconstruct.

The current text frontend records the known grammar filename and uses `null` for the unknown root and byte span. ADRs 0042,
0043, and 0044 populate include chains, documentation, and parameter specialization respectively; unsupported metadata remains
`null`. Version-1 migration does not infer provenance or documentation from nearby locations. It writes
`migration.from_schema_version: 1` and explicitly lists unavailable source, documentation, expansion, action-composition, and
grammar-test metadata.

Automaton IR version 2 always embeds Grammar IR version 2. Upgrading an automaton upgrades the embedded grammar and recalculates
the SHA-256 digest over its canonical version-2 serialization. A new automaton built from a version-1 grammar performs the same
upgrade before construction.

`Ibex::IR::Migration.to_version` supports identity at the requested version and the single meaning-preserving upgrade from 1 to
2. Downgrades are deliberately unsupported. `ibex migrate-ir INPUT --to=2` writes the canonical result to stdout; `-o FILE`
writes a temporary file in the destination directory, flushes and synchronizes it, and renames it atomically. Input/output
aliases are rejected before any write. `validate-ir` accepts both versions, and `compare` compares documents of the same kind
across versions while ignoring transport-only metadata.

The public Draft 2020-12 schemas are `schema/grammar-ir-v2.schema.json` and
`schema/automaton-ir-v2.schema.json`. Version-1 schemas and golden fixtures remain shipped and unchanged. Separate version-2
goldens cover direct generation, migration, idempotence, validation, and dump/load/dump stability.

## Consequences

- Future lossless source, include, parameter, inline, documentation, and coverage work has a versioned place to retain origins
  without another incompatible envelope change.
- Consumers can upgrade local artifacts deterministically and can distinguish absent historical information from an empty
  current value.
- Version 1 remains a supported read contract, but new pipeline output is version 2 and there is no version-2-to-version-1
  conversion.
- Canonical Grammar and Automaton IR bytes change for new builds. Generated frontend identity headers and deterministic benchmark
  IR/artifact digests therefore change even when parser states, tables, generated code size, and runtime results do not. The
  version-1 benchmark observation remains append-only; a new result tied to this implementation revision becomes the CI
  reproducibility baseline.
