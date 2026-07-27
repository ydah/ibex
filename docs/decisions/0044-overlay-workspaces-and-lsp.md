# ADR 0044: Serve overlay-backed grammar workspaces over LSP

- Status: Accepted
- Date: 2026-07-25

## Context

Ibex already has a lossless frontend, bounded diagnostic recovery, canonical fragment includes, rule documentation, and stable
byte/scalar locations. Editor integration must reuse those authorities without executing Ruby actions or user-code sections.
Open editor buffers also need to override disk for a complete include closure, including a newly created unsaved fragment.

LSP positions count UTF-16 code units rather than frontend Unicode scalars or bytes. JSON-RPC framing is an untrusted input
boundary: malformed headers, oversized documents, stale versions, invalid request lifecycle, and non-file URIs must not corrupt
workspace state or write non-protocol text to stdout. Rename crosses files and therefore needs a stronger semantic guard than
textual replacement.

## Decision

`Frontend::SourceLoader` owns canonical path and source reads. Its default behavior is the existing realpath/filesystem contract.
An optional overlay map takes precedence for open files and may represent a new file below the nearest real existing directory.
Canonicalization still resolves existing symlinks before root-containment checks. Directories cannot become overlays. Resolver
accepts an injected loader but retains its realpath, root containment, symlink escape, cycle, diamond deduplication, and
`ResolutionIOError` contracts. Dangling symlinks cannot become overlays, and close re-resolves the current disk target without
overlay aliases before removing the buffer, preventing a newly created symlink from crossing the workspace boundary.

`ibex lsp` implements LSP 3.17 over Content-Length-framed stdio JSON-RPC using only the `json` and `uri` standard libraries.
Stdout contains framed JSON only; operational and notification errors go to stderr. The server supports
`initialize`/`initialized`/`shutdown`/`exit`, full-text open/change/save/close notifications, diagnostics, definition,
references, prepare-rename, rename, and hover. Initialization accepts `rootUri` or initial `workspaceFolders`; every document
must use a local `file` URI below one of those canonical roots. Remote authorities, query/fragment components, invalid or
ambiguous percent escapes, encoded separators/NUL, and decoded parent traversal are rejected. Raw authorities are validated
before URI normalization so userinfo and ports cannot be discarded and mistaken for localhost.

Headers, input messages, open documents, and output messages have explicit byte limits. Malformed JSON uses JSON-RPC parse
errors, invalid envelopes and lifecycle use standard request errors, and unknown requests use method-not-found. Unknown `$/`
notifications are ignored. Protocol error text and request identifiers are bounded so even a near-limit invalid request receives
an in-limit response. Shutdown alone does not make EOF a successful session: a following `exit` notification is required.

`LSP::DocumentStore` owns open versions, overlay source, parsed snapshots, include closures, and reverse dependencies. Versions
increase monotonically within one open epoch; reopening after close starts a new epoch. A fragment change reanalyzes every known
root that includes it, including multiple roots and a root whose include was previously missing. Close publishes an empty
diagnostic set before replacing the buffer with a disk snapshot, and an open root is removed from root membership. Publications
carry the current open version and are discarded if that version has become stale. Diagnostics are owned per root and aggregated
by path, so closing or replacing one root cannot erase another root's contribution for a shared fragment. Root sources reuse
`Parser#parse_with_diagnostics(max_diagnostics: 20)`. Fragment identity is retained through recovering first-token lexing;
because the current recovery parser owns the root grammar contract, a malformed fragment safely falls back to its first
positioned strict frontend error rather than being misclassified as a root.

No workspace operation normalizes, generates, loads, or evaluates application parser code. Actions, heredocs, and
`header`/`inner`/`footer` bodies remain opaque frontend segments.

`LSP::PositionCodec` converts half-open frontend byte spans to zero-based UTF-16 ranges. Astral characters occupy two code
units, combining codepoints remain distinct, CRLF bytes are excluded from line content, and surrogate midpoints or out-of-line
positions are errors.

`LSP::SymbolIndex` indexes repeated rule definitions, RHS and parameterized references, rule-local formal parameters, terminal
declarations and metadata uses, precedence/convert/start uses, and include literals. Parameter names resolve only inside their
rule. Definition, references, and hover never scan comments, actions, user code, or named-reference labels as symbols. Hover
reports rule signature, `%inline`, parameters and documentation, or terminal display/type/precedence and include target.

Rename is limited to source identifiers with a definition. Quoted, reserved, unresolved, generated, and colliding names are
rejected. A shared fragment with multiple roots is conservatively ambiguous. Edits use canonical nonoverlapping spans, retain
the exact URI spelling and version of each open document in `documentChanges`, are applied to temporary source copies, and are
returned only when every affected document reparses and every affected root re-resolves successfully. Definition, reference, and
include-target locations use the same open URI identity and fall back to canonical URIs after close.

## Consequences

- Resolver callers that do not inject a loader keep their filesystem behavior.
- Unsaved roots and fragments participate in the same secure include semantics as disk files.
- Editor diagnostics and navigation share the self-hosted frontend and cannot execute grammar-provided Ruby.
- Stale versions, invalid UTF-16 positions, unsafe URIs, and semantically invalid renames fail at the protocol boundary.
- FIRST/FOLLOW enrichment is not part of this initial hover contract; it can be added later from resolved analysis without
  changing source indexing or transport.
