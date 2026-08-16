# V004 table-artifact fault injection

## Problem evidence

V002 validates the closed data-only table shape and V003 binds table, report,
manifest, input, and logical IR identities. Existing tests cover individual
validation rules, but they do not publish one named mutation inventory spanning
the table-artifact boundary. A regression could therefore preserve generic
schema tests while dropping a required cross-artifact rejection.

## Contract

V004 commits a versioned mutation corpus covering grammar identity, symbol and
production structure, action/GOTO/default cells, the selected conflict action,
compact displacement arrays, entry states, CST metadata, cross-artifact hashes,
and malformed or duplicate artifacts. Every mutation names the layer and
invariant expected to reject it.

The corpus distinguishes structural validation from digest binding. It may
refresh the table payload digest to reach a deeper structural invariant. It
refreshes the derived canonical byte count only when a structurally valid
survivor would otherwise stop at that derived cost field. A semantically
plausible in-range cell mutation is expected to cross the table validator and
then fail the unchanged report or manifest binding. It never
claims to reject an attacker who coherently replaces and re-signs every layer;
V003 explicitly excludes authenticity and table semantic derivation.

## Trust label

Table parsing, canonical JSON, SHA-256, table validation, report validation,
and manifest validation are trusted. Generated wrapper bytes are bound but are
not loaded. Fixture grammar actions do not execute.

## Compatibility

The task adds tests and documentation only. It changes no v1 artifact field,
runtime table ABI, CLI default, or generation output. A newly exposed surviving
mutation would require either a validator fix or an explicit documented trust
boundary, not an incompatible silent schema change.

## Configuration admission

No configuration is admitted. The fixture fixes compact representation,
default verification, and explicit resource bounds through existing APIs.

## ABI assessment

No Ruby, RBS, native, generated-source, or persisted format ABI is added. The
mutation helper is test support and is not packaged.

## Bounds

The inventory is finite and exact. Each mutation is applied to a fresh in-memory
copy and validated once. Parser recognition, semantic actions, external
commands, and unbounded search are outside the test.

## Oracle

The oracle is rejection at the named invariant. Messages are matched narrowly
enough to distinguish structural, table/report, and manifest failures. For
in-range mutations, the test first demonstrates that standalone structural
validation still succeeds, then requires the unchanged outer binding to fail.

## Tests

- all V004 work-order fault classes occur in the exact inventory;
- each mutation is deterministic and independent;
- refreshed structural mutations reach their intended validator;
- in-range semantic mutations are stopped by report/manifest binding;
- table/report and report/manifest byte bindings, truncated JSON, and duplicate
  manifest artifact roles fail closed;
- no mutation is accepted as a valid unchanged bundle.

## Claims

The allowed claim is limited to detection of the committed v1 mutations under
the stated single-fault model. This is neither authenticity, cryptographic
signing, semantic equivalence, exhaustive mutation coverage, nor proof that the
persisted table was correctly derived from Automaton IR.

## Kill conditions encountered

If a mutation survives because it requires authenticity or semantic derivation,
the task records that boundary instead of mislabeling a digest as a signature.
If a supposedly structural mutation survives after only its payload digest is
refreshed, the corresponding validator must be fixed before V004 is complete.
