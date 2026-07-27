# ADR 0037: Collect frontend diagnostics with bounded boundary recovery

- Status: Accepted
- Date: 2026-07-25

## Context

The strict frontend stops at its first lexical or syntax error. Editors and migration tools need several useful diagnostics from
one file, but speculative recovery inside arbitrary grammar expressions produces cascades and risks diverging from the
self-hosted parser. The generated parser remains the sole authority for grammar meaning, and the normal `Parser#parse` contract
must keep its first error text and successful AST unchanged.

Lossless source documents from ADR 0036 provide exact spans and opaque action/heredoc segments. They do not by themselves define
where a failed parse may resume. CPCT+-class minimum-cost repair remains a separate runtime feature with a different cost,
candidate, and synthetic-value policy.

## Decision

`Frontend::Parser#parse_with_diagnostics(max_diagnostics: 20)` returns an immutable `Frontend::ParseResult`. Its ordered,
deduplicated `diagnostics` contain immutable `Frontend::Diagnostic` values with a stable `code`, phase, message, severity,
defensively copied location, byte span, expected descriptions, and received spelling. The limit must be a positive integer.
Lexical and syntax phases each retain at most that many records; their union is deduplicated, sorted by original source position,
and truncated to the globally earliest records. Consequently a later lexical error cannot consume the budget before an earlier
syntax error, while no more than twice the requested number of phase results are retained before the merge. `success?` is true
only when there are no diagnostics and a complete AST exists.

The strict parser remains authoritative. Diagnostic parsing creates a fresh generated parser for each attempt and never reads or
copies generated-parser implementation details. On failure it locates the original semantic token and suppresses one conservative
top-level source region before retrying:

- a whole declaration through the next declaration or `rule` boundary;
- a whole rule through the next LHS or grammar `end`; or
- one outer alternative together with the adjacent `|`.

Parenthesized and separated-list delimiters must be balanced before `|`, `;`, LHS, or `end` is considered a synchronization
boundary. Actions and their heredocs are already one opaque lexical token. Every retry must suppress at least one previously
visible token, and attempts cannot exceed the original token count. Failure to find a boundary, failure to make progress, or
reaching the diagnostic limit stops recovery.

Lexical recovery is separate from syntax recovery. An unexpected character becomes an `invalid` lossless segment and advances
one character; adjacent invalid bytes are represented by one concrete-syntax segment where possible. The recovering lexer
continues scanning to make later syntax analysis possible but never retains more diagnostics than its positive limit. Parser
construction retains only the first lexical failure required by the strict API and re-lexes with the caller's bound when batch
diagnostics request more. An unterminated block comment or already-consumed opaque construct retains the affected bytes as one
invalid segment and stops naturally at EOF. When a scanner reports a more precise `file:line:column:` inside such a span, that
escaped exact prefix supplies the diagnostic location and is removed from the machine message. Invalid UTF-8 produces one
positioned lexical diagnostic without a source document; `parse_document` raises that same strict error. The ordinary
`Lexer#tokenize` stays strict.

`Parser#parse` raises the first saved lexical error with its exact previous message before invoking the generated parser. A
generated-parser syntax failure is also saved, so every later strict call raises the same message rather than reusing mutated LR
state.

A successful repaired parse may produce a partial AST containing valid declarations, rules, and later constructs. It is exposed
only as `ParseResult#ast`, with `partial? == true`. When diagnostics exist, the original `ParseResult#document` deliberately keeps
`document.ast == nil`; callers cannot mistake a repaired projection for the meaning of the unchanged source. Token-array input
can return a partial AST but has no source document.

`ibex diagnose [--format=text|json] [--max-diagnostics=N] [--mode=default|extended] grammar.y` is the explicit CLI boundary. It
never generates a parser or executes application code. After an error-free root parse, extended-mode include resolution may
add the first cross-file security, missing-target, cycle, or fragment-syntax failure as `frontend.resolution_error`; recovery
across files is deliberately bounded to that single record and exposes no AST. Text and JSON go to stdout. A structured
`ResolutionIOError` keeps permission and other actual root/fragment read failures in the invocation-error path on stderr, with
no JSON envelope. The command exits zero only for a complete error-free parse. JSON uses the shipped
`schema/frontend-diagnostics-v1.schema.json` envelope and requires every diagnostic's stable machine code.

## Consequences

- Existing generation commands and strict parsing retain first-error behavior.
- Batch results are deterministic, globally source-ordered, bounded per phase, and useful after more than one broken region.
- Later valid constructs can survive in an explicitly partial AST without being attached to the original source document.
- Recovery reparses from the beginning and is intentionally more expensive than strict parsing.
- Minimum-cost runtime repair remains a separate runtime decision.
