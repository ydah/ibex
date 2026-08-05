# ADR 0022: Bind scoped verification evidence through the generation manifest

- Status: Accepted
- Date: 2026-08-05

## Context

The independent Automaton IR verifier and the data-only parser table sidecar
have useful but separate identities. A published parser also includes a Ruby
wrapper containing opaque actions. Consumers need to detect a table, report,
wrapper, or input taken from another generation without loading the wrapper or
overstating what the verifier checks.

A report could contain every artifact digest including its manifest, be
embedded in generated Ruby, use physical paths as artifact identities, or be
published as a separate manifest-bound artifact. Including the manifest
digest creates a hash cycle because the manifest must hash the report.
Embedding evidence in Ruby makes nonexecuting inspection depend on a source
container that also carries opaque code. Physical paths make equivalent
evidence differ between checkouts.

## Decision

Adopt an Experimental, separately versioned scoped verification report and an
explicit verifiable-generation-bundle API. The report records logical input
identities, Grammar and Automaton IR digests, the data-only table artifact and
payload digests, checker version, verification profile, completed checks,
bounds, outcome, and a closed excluded-trust list. That machine-readable
exclusion includes semantic derivation or language equivalence from Automaton
IR to persisted table data; version 1 validates table structure and digest
linkage but does not independently prove that projection.

The report never contains the manifest digest or path. Generation renders the
table, wrapper, and report in memory, then renders a generation manifest that
lists and hashes all three. The existing transaction publishes non-marker
artifacts and the wrapper before installing that manifest as the final
coherence marker.

Canonical report evidence uses ordered logical identities rather than
absolute paths: indexed input basenames and a role-qualified table basename.
The required IR digests are preserved unchanged. The bundle validator checks
report self-identity, manifest artifact bytes, input identity, table identity
and payload, and IR/table linkage without parsing or loading generated Ruby.

The API stays outside the default `ibex` require path and generator CLI. An
application must explicitly require and invoke it. This preserves existing
generation bytes and leaves CLI/stability promotion to a later compatibility
decision.

## Consequences

- A manifest is the single non-cyclic publication marker for table, wrapper,
  and report coherence.
- Equivalent source records can produce identical report evidence across
  checkout roots when their IR and logical basenames are identical.
- Missing, stale, duplicated, or cross-generation table/report/manifest
  combinations are rejected before generated Ruby is loaded.
- A passing report remains bounded evidence for named V1-V8 checks, not proof
  of table semantic derivation, wrapper, action, lexer, runtime, application,
  source-to-IR, authenticity, or grammar-unambiguity correctness.
- The new schema and validator are persistence and trusted-computing-base
  obligations. Future schema versions may extend evidence only without
  silently widening version 1 claims.
- Default CLI generation and the Stable generated-parser ABI do not change.
