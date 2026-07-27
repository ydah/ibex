# ADR 0040: Preserve grammar text in a lossless source document

- Status: Accepted
- Date: 2026-07-25

## Context

Formatting, documentation comments, includes, and language-server features need comments, whitespace, exact byte ranges, and
opaque Ruby bodies. The semantic frontend previously discarded trivia before the self-hosted parser saw its token stream.
Re-lexing source later would duplicate grammar interpretation and could disagree with the token stream that produced the AST.
Adding spans to serialized token hashes or AST records would also change established AST and Grammar IR fixtures.

Source coordinates must remain useful for Ruby diagnostics while providing byte offsets for slicing and future editor protocols.
Ruby strings can carry misleading encoding labels, CRLF has two bytes but one line break, and UTF-8 supplementary-plane
characters occupy four bytes but one source column. These cases require an explicit contract.

## Decision

`Frontend::Lexer` now produces semantic tokens and lossless segments during the same cursor pass. `Lexer#tokenize` keeps its
existing semantic result, while `Lexer#tokenize_document` returns a `Frontend::SourceDocument`. `Frontend::Parser#parse_document`
uses that same token array to build the AST and returns one document containing the original text, semantic tokens, AST, and an
immutable `CST::Document` lexical root. `Parser#parse` and `parse_document` share the single semantic parse. A parser constructed
from an application-supplied token array cannot invent source and rejects `parse_document`.

Each immutable `Segment` has a kind, exact text, half-open `SourceSpan`, optional semantic token type, and optional index into
the document's token array. Whitespace, line breaks, line comments, block comments, ordinary tokens, actions, EOF, user-code
markers, and user-code bodies are distinct segment kinds. An action, including quoted or interpolating heredocs, is one opaque segment.
User-code bodies are also opaque, and repeated marker/body pairs remain distinct and ordered. The CST is deliberately a flat,
lossless lexical root beside the semantic AST: later tools correlate them through token indexes and spans instead of parsing the
grammar a second time.

Spans use zero-based byte offsets with an exclusive end. Their start and finish positions use the existing one-based line and
column convention; columns count Unicode scalar values, so a supplementary-plane character advances one column. `\n` advances
the line and resets the column, making CRLF one line break while the preceding `\r` remains a source character. A lone `\r` does
not start a new line. `SourceDocument#position_at` and `#byte_offset_at` convert between these coordinates,
`#slice` extracts by span, and both the CST and document `#render` reproduce the original bytes.

Grammar input bytes are interpreted as UTF-8 without transcoding. The frontend duplicates the input, applies the UTF-8 label,
and rejects an invalid byte sequence before tokenization. This preserves every accepted byte and never mutates the caller's
string. LSP UTF-16 code-unit conversion is intentionally a later adapter over this byte/scalar contract.

`Token#span` is an optional in-memory field. `Token#to_h`, normalized IR, and all existing locations remain unchanged by this
decision. ADR 0043 later uses segment positions to add nullable documentation to `AST::Rule` and reserved Grammar IR v2 fields
without changing token serialization. Segment and CST collections are immutable; semantic token objects retain their existing
compatibility behavior.

## Consequences

- `document.render == input` is a checked invariant, including comments, trailing whitespace, CRLF, Ruby actions, heredocs,
  repeated user code, and EOF.
- Formatting, includes, and LSP work can share one source contract without altering grammar meaning. ADR 0043 completes
  doc-comment attachment on this model.
- Byte slicing is exact and editor coordinate conversion has one documented starting point.
- Invalid UTF-8 fails earlier and more clearly than an incidental regular-expression or token error.
- The CST does not claim semantic nesting. Tools that need grammar meaning use `SourceDocument#ast`; tools that need exact text
  use segments and spans.
