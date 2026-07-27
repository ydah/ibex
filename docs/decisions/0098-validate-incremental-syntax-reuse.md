# ADR 0098: Validate incremental syntax reuse in two stages

- Status: Proposed
- Date: 2026-07-27

## Context

Parser production actions may depend on arbitrary instance or external state.
Skipping actions for a reused subtree cannot reproduce those effects. Ruby
regular expressions also do not expose how far matching looked ahead, so a
general lexer cannot soundly restart at a nearby token boundary.

Incremental state belongs to one editing session. It must not be stored in
shareable Green values because one interned value can occur at multiple tree
positions with different parser states.

## Decision

`ParserClass.incremental_session(SourceText)` is syntax-only. Its initial parse
and every edit suppress parser production actions and return `SyntaxResult`
without a semantic value. Generated lexer actions continue to run because they
define token emission and lexer-state transitions. Handwritten token sources,
push input, pre-v6 CST tables, and `drop` trivia are rejected explicitly.

Stage A always lexes and parses the edited source from the beginning. A
session-owned `NodeCache` preserves physical identity for equal Green tokens
and bounded nodes. `TokenMemo` records each token's full offset and lexer state
at token start. `Relexer` compares exact state, boundary, kind, text, flags,
and trivia before the damage region. After all edits, an old boundary shifted
by the total byte delta and the same lexer state proves that the unchanged
remaining bytes will produce the old suffix, so comparison stops there.

`TextEdit.normalize` sorts edits, merges adjacent ranges, and rejects
intersections before applying them. Session memo storage is bounded by
`ResourceLimits#max_session_memo_bytes`; exhaustion clears reusable cache state
and reports `cst_fallback`. `cst_built`, `cst_fallback`, and `cst_reuse` are
additive runtime-event v1 variants. Incremental session objects, Red wrappers,
memo arrays, and caches remain single-owner mutable state.

Stage B records one `left_state` per Green occurrence in a preorder-parallel
`ParseMemo`. The key is position, not Green identity. A reused memo segment is
copied by `descendant_count`, and serialized memo is accepted only when grammar
digest, state count, and production count remain compatible.

`Blender` may feed a Green nonterminal directly to the LR driver only when:

1. its token range is outside every damage range and has lexically
   resynchronized;
2. its recorded `left_state` equals the current LR state;
3. its following Green token is identical in the old and new token streams;
4. it has none of `CONTAINS_ERROR`, `CONTAINS_MISSING`, or
   `CONTAINS_SKIPPED`;
5. its `full_width` is positive.

When these conditions hold, old and new drives start in the same state and
consume the same subtree tokens followed by the same lookahead. A complete
nonterminal cannot reduce across its own left boundary. Error and recovery
paths that could violate that property are excluded by condition 4. Therefore
pushing the old Green node and applying `goto(state, lhs)` reaches the same LR
configuration as replaying its internal shifts and reductions. If a candidate
does not match the live state, the source offers a smaller candidate or the
fresh token instead.

Candidate decomposition is bounded. Exhaustion clears all candidates and uses
the already scanned fresh token stream, reporting `cst_fallback`. `blender:
false` selects the same Stage-A stream explicitly. The incremental-versus-batch
property suite remains authoritative.

## Gate 2 evidence

The versioned 100-term/100-edit benchmark on Ruby 4.0.0 records:

- lexical comparison counts of 1, 101, and 199 tokens for edits at the
  beginning, middle, and end;
- a 0.995 Green-token reuse ratio at all three positions;
- Stage-A wall-clock speedups of 0.95–0.96x versus fresh syntax sessions.

This confirms the expected position-dependent scan cost and shows that shared
tokens alone do not offset a complete LR drive. Gate 2 therefore approves
continuing to conservative Stage B. The optional declared lookahead bound is
not pulled forward: parser/tree construction, rather than the initial scan,
is the larger remaining cost in this measurement.

The subsequent version-2 benchmark uses a 100-term recursive grammar and 100
one-byte edits at each position. Stage B is 1.04–2.83x faster than Stage A and
1.66–4.48x faster than a fresh syntax session. Direct subtree reuse ranges
from 49.3% at the beginning to 98.3% at the end. A fixed-seed structural-edit
suite additionally performs 500 insertions, deletions, and replacements while
comparing Green structure, source, flags, diagnostics, and memo cardinality
against fresh syntax sessions.

## Consequences

- Incremental callers cannot accidentally receive stale semantic values or
  omit semantic side effects.
- Stage A is correct for arbitrary generated regular-expression lexers,
  including lexer-action state changes, at the cost of a fresh lexical scan.
- Edits retain Green identity where structural equality and cache policy allow
  it, while batch syntax remains the reference result.
- Parser-controlled lexer-state changes performed only by production actions
  are intentionally unavailable to syntax-only sessions; such a grammar will
  fail lexically rather than execute the action.
- Runtime-event readers must ignore unknown event types to remain forward
  compatible under the additive v1 policy.
