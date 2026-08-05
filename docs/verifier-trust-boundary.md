# Verifier trust boundary

`ibex verify` checks a validated Automaton IR document against expectations
derived from the Grammar IR embedded in that document. It is a semantic
cross-check for the current Automaton IR. It is not a proof checker for a
generated parser, a verifier for arbitrary Ruby, or a security sandbox.

## Input and result boundary

The command reads one complete JSON document with `File.binread`.
`IR::Validator` first parses it and validates its raw shape, schema version,
symbol/state/production references, and conflict records and summaries. It
then calls `IR::Serialize.load` to construct immutable Grammar and Automaton
IR objects. Finally, before returning the Automaton, it recomputes and checks
the embedded-grammar digest. Those validation and construction steps are a
prerequisite to, not a substitute for, the semantic checks below.

The embedded Grammar IR is the verifier's semantic source of truth. Supplying
`--grammar=GRAMMAR.json` requires byte-deterministic serialized equality with
that embedded Grammar IR, but does not bind either IR to an original `.y`
file. Recomputing `grammar_digest` detects accidental inconsistency inside the
document; an author who changes both the embedded grammar and its digest has
created a different self-consistent input, not a verifier failure.

A semantic violation produces an invalid result and CLI exit status 1. A
completed run with no named violation produces a valid result and exit status
0 within this document's boundary. Reference-construction exhaustion is a
separate result with exit status 2; it is neither validity nor a violation.

## Named invariants

The report's invariant IDs are stable schema values. “Default” means every
run; “strict” means the ID is listed only for `--strict`.

<!-- verifier-checks:start -->
| ID | Mode | What the implementation checks |
| --- | --- | --- |
| V1 | default | The embedded grammar digest, state item soundness against the algorithm-specific reference, transition shift preservation, nonterminal transition/GOTO agreement, and exact single-candidate ACTION selection. Unsupported programmatic algorithm values are also V1. |
| V2 | strict | Collection completeness: exact LR(0) core coverage for SLR; exact derived-state/item coverage for LALR(1) and LR(1); and canonical-core lookahead-union coverage for IELR(1). |
| V3 | default | Every completed SLR item has exactly its independently requested FOLLOW lookaheads (or EOF for an augmented production). Non-completed SLR lookaheads cannot select ACTION cells and are deliberately outside this check. |
| V4 | default | Default actions are reductions, terminals with no candidate remain errors after expanding defaults and explicit masks, and rebuilt plain/compact ACTION, GOTO, and default rows are equal. A table transformation failure is also V4 in default mode. |
| V5 | strict | The same rebuilt plain/compact row equality that default mode reports as V4 is classified as V5 in strict mode. Strict mode does not consume a separately supplied table artifact. |
| V6 | default | Every submitted state is reachable from an entry through submitted transitions, GOTOs, or shift actions, and every embedded-grammar nonterminal derives some terminal sentence. |
| V7 | default | For each terminal, effective zero-length reductions and their submitted GOTOs do not form a state cycle that can reduce forever without consuming that terminal. |
| V8 | default | A cell with multiple derived candidates has a declared resolver; resolver records are unique and complete for their token, name only cell candidates, and choose the effective ACTION (or an allowed error). |
<!-- verifier-checks:end -->

Default and strict both construct the algorithm-specific reference and both
rebuild and compare plain and compact rows. Strict adds the V2 completeness
requirements. It also changes a row mismatch's identifier from V4 to V5; it
does not add another table representation or inspect generated table bytes.
In particular, default-mode item checks are soundness/subset checks and can
accept an incomplete collection that strict mode rejects.

## Supported algorithms and reference cost

The CLI validator accepts only the following serialized algorithm identities.

<!-- verifier-algorithms:start -->
| Automaton IR value | Reference and comparison |
| --- | --- |
| `slr` | Build the full LR(0) collection. Completed submitted items use FOLLOW sets for lookaheads. Strict mode requires exact LR(0) core coverage. |
| `lalr1` | Build the full canonical LR(1) collection and union states with the same LR(0) core. Submitted items are subsets by default; strict mode requires the complete merged states. |
| `ielr1` | Build the full canonical LR(1) collection and its LALR core unions. Each submitted partition must be a subset of its core union; strict mode requires the union of submitted partitions to cover it. This does not prove IELR adequacy or the reason for each split. |
| `lr1` | Build the full canonical LR(1) collection. Submitted items are subsets by default; strict mode requires the complete canonical states. |
<!-- verifier-algorithms:end -->

Thus LALR(1), IELR(1), and LR(1) verification enumerate the canonical LR(1)
collection even in default mode. That collection can grow exponentially with
the grammar. SLR enumerates LR(0), but is still a whole-collection operation.
The current verifier is consequently a bounded reference oracle, not a
scale-independent certificate checker. A serialized unknown algorithm is
rejected structurally before the CLI verifier runs; an Automaton object made
directly with an unknown value receives V1.

The supported `ielr1` check is intentionally narrower than a future direct
IELR verifier: it checks membership and, in strict mode, union coverage. It
does not establish conflict preservation, canonical state correspondence, or
split witnesses.

## Limits and exhaustion

The two CLI limits must be positive and apply only to reference collection
construction.

<!-- verifier-limits:start -->
| Limit | Default | Meaning |
| --- | ---: | --- |
| `--max-states` | `100000` | Maximum distinct reference states inserted. |
| `--max-items` | `1000000` | Work-account limit for augmented seed items and new closure-expansion items. It is not the final collection's unique-item count and does not count every moved GOTO kernel item. |
<!-- verifier-limits:end -->

Exceeding either limit raises `Verify::BudgetExceeded`; the CLI emits
`result: "budget_exhausted"` with the bounds and exits 2. Strict mode uses the
same two limits and has no separate completeness budget.

These limits do **not** bound input bytes, JSON parsing, IR validation,
embedded grammar size, submitted state/table size, nullable/FIRST/FOLLOW
analysis, table compression, all verifier loops, wall-clock time, Ruby heap,
or process resources. An operating-system failure, timeout, or memory
exhaustion is not converted into a verifier budget result. Callers handling
hostile inputs need an outer byte/time/memory/process boundary.

## Trusted computing base and independence

Here, “independent” means only that `Verify::ReferenceCollection` implements
its own LR(0)/LR(1) closure, GOTO, and collection traversal and does not require
or call `LALR::Builder`. It does not mean independently authored, third-party
reviewed, formally verified, cryptographically certified, or free of shared
implementation defects.

The result trusts all of the following:

| Trusted component or input | Why it is in the TCB |
| --- | --- |
| Embedded Grammar IR | It defines the grammar against which the submitted automaton is checked. |
| `IR::Validator`, `IR::Serialize`, IR migration and IR model classes | They validate, decode, canonicalize, hash, and expose the input. |
| `Verify::Verifier`, `Verify::ReferenceCollection`, and result classes | They derive and evaluate all named semantic invariants. |
| `Analysis::Sets` | It supplies nullable, FIRST, and FOLLOW data. The parser builder also uses this component, so defects here can be correlated. |
| `Tables.build`, `Tables::Compact`, and `Tables::CompactActions` | The verifier rebuilds both in-memory table views with production table code. Plain/compact comparison is therefore not an independent compact-table implementation. |
| Ruby runtime and standard library (`JSON`, `Set`, `Digest`, file I/O) | They parse, enumerate, compare, hash, and allocate the checked data. |
| Host resource isolation | The verifier itself supplies only the two reference-work limits above. |

Excluding `LALR::Builder` is useful deliberate duplication, but the shared
sets, IR, table transformation, language runtime, and embedded input remain in
the TCB. A valid report is evidence against the implemented fault model, not
an unqualified correctness proof.

## Explicit non-goals

<!-- verifier-non-goals:start -->
| Boundary | What is not verified |
| --- | --- |
| `source-to-ir` | Correct parsing or normalization of the original grammar source, or provenance from that source to the embedded Grammar IR. |
| `generated-ruby` | Generated Ruby source, wrapper structure, digests, loading behavior, or binding between generated output and this Automaton IR. |
| `runtime` | The parser runtime implementation, actual parser execution, recovery behavior under application callbacks, or plain/compact behavior after code generation. |
| `semantic-actions` | Meaning, type safety, termination, side effects, or correctness of parser actions and user-code sections. Their text is opaque and is never evaluated. |
| `lexer-actions` | Lexer IR, tokenization, generated lexer actions, handwritten lexers, or parser-to-lexer feedback. |
| `resolver-policy` | Whether a resolver's claimed `by` reason correctly applies grammar precedence/associativity policy; V8 checks record/candidate/selected-cell consistency. |
| `grammar-properties` | Unambiguity, language equivalence to another grammar/parser, completeness of `%expect` as a design claim, or application semantics. |
| `ielr-adequacy` | Conflict preservation, why an IELR state was split, or a proof that every split has the required canonical correspondence. |
| `data-only-artifact` | The standalone `ibex verify` command does not consume a supplied executable table artifact, compact-table bytes, generated bundle, manifest/report binding, or artifact digest. The current Automaton IR contains states and actions, and the verifier rebuilds table views from them. The separate bundle report records this verifier result and binds table identities without widening V1-V8. |
| `security` | Authenticity, trusted publication, signatures, sandboxing, confidentiality, or availability under hostile resource use. |
<!-- verifier-non-goals:end -->

Opaque action and user-code strings participate in serialized Grammar IR and
therefore its digest, but checking that self-contained digest is not semantic
verification of the code and never executes it.

The data-only table and scoped bundle are separate layers around this
verifier. Their validators check closed formats and digest relationships, but
they do not make the standalone V1-V8 implementation consume or independently
verify sidecar bytes. Consequently `ibex verify` must still not be described
as validating generated Ruby, table artifacts, or manifests.

## Committed fault corpus

`test/verify/verifier_test.rb` mutates a generated document in twenty named
ways while keeping it acceptable to `IR::Validator`, then requires strict
verification to reject it. The table records the invariant IDs currently
observed for each mutation. Multiple IDs mean one mutation violates more than
one invariant; they do not turn the finite corpus into completeness evidence.

<!-- verifier-faults:start -->
| Fault | Observed invariant IDs |
| --- | --- |
| `add_lookahead` | V1, V2 |
| `remove_item` | V1, V2 |
| `remove_lookahead` | V2 |
| `move_item_dot` | V1, V2 |
| `remove_transition` | V4 |
| `redirect_transition` | V1 |
| `remove_action` | V1 |
| `redirect_shift` | V1 |
| `replace_reduction` | V1 |
| `remove_goto` | V1 |
| `redirect_goto` | V1 |
| `add_default` | V4 |
| `remove_default` | V1 |
| `remove_error_mask` | V4 |
| `remove_conflict` | V8 |
| `duplicate_conflict` | V8 |
| `redirect_conflict_shift` | V8 |
| `change_conflict_choice` | V8 |
| `add_unreachable_state` | V1, V6 |
| `epsilon_cycle` | V1, V4, V7 |
<!-- verifier-faults:end -->

The corpus demonstrates detection of these twenty constructed, structurally
valid mutations on its committed grammars and construction harness. It does
not establish that all corruptions, all combinations of faults, or faults in
the TCB are detected.
