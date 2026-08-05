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
Version 1 closes both forms to one basename, exactly four input-index digits,
and at most 10,000 inputs.

IR claims use the explicitly named `source-logical-v1` identity scope. Bundle
construction rebuilds an immutable Automaton IR copy from the supplied IR and
`source_records`: every location file becomes its ordered logical input
identity and each non-null source root becomes `input`. The table and verifier
consume that same copy, so its Grammar IR digest, embedded Automaton IR
grammar digest, Automaton IR digest, table identity, report claims, and report
evidence digest cannot disagree. An unmapped or ambiguous source location is
an error. The original Automaton, its diagnostic provenance, and ordinary
V002 table construction remain unchanged.

The bundle validator checks report self-identity, manifest artifact bytes,
input identity, table identity and payload, and IR/table linkage without
parsing or loading generated Ruby.

The API stays outside the default `ibex` require path and generator CLI. An
application must explicitly require and invoke it. This preserves existing
generation bytes and leaves CLI/stability promotion to a later compatibility
decision.

## Consequences

- A manifest is the single non-cyclic publication marker for table, wrapper,
  and report coherence.
- Equivalent source records produce identical table and report evidence
  across checkout roots when their ordered logical basenames and bytes match.
- Missing, stale, duplicated, or cross-generation table/report/manifest
  combinations are rejected before generated Ruby is loaded.
- A passing report remains bounded evidence for named V1-V8 checks, not proof
  of table semantic derivation, wrapper, action, lexer, runtime, application,
  source-to-IR, authenticity, or grammar-unambiguity correctness.
- The new schema and validator are persistence and trusted-computing-base
  obligations. Future schema versions may extend evidence only without
  silently widening version 1 claims.
- Default CLI generation and the Stable generated-parser ABI do not change.
