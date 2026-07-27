# ADR 0086: Use byte-oriented source cursor storage

- Status: Accepted
- Date: 2026-07-27

## Context

The frontend cursor previously selected a one-character `String` for every
advance. Grammar scanning observes both character-based columns and byte-based
source spans, so simply treating a UTF-8 source as bytes would make locations
incorrect for non-ASCII input. Repeated character indexing also makes scanning
later portions of a multibyte source increasingly expensive.

The cursor is private frontend machinery, but its source copy, locations,
positions, spans, lookahead strings, remainder strings, and advance return
values are observable through lexer and parser behavior.

## Decision

Validate and freeze the same UTF-8 source copy as before, then cache its
character length. Valid ASCII sources use character indices directly as byte
offsets. Non-ASCII sources retain no per-character index: `advance` derives the
next byte offset in constant time from the validated UTF-8 leading byte.

`advance` reads only the current leading byte to recognize LF and moves through
the source without creating one-character strings. Public `index` and columns
remain character-based; `byte_offset` and spans remain byte-based.

`peek` retains `String#[]` absolute character-index behavior, including negative
indices. It locates arbitrary character offsets by walking UTF-8 boundaries
from whichever of the current position, source start, or EOF is closest.
Backward walks skip UTF-8 continuation bytes. Production lookaheads at offsets
zero and one remain constant-time; distant relative lookaheads take time
proportional to the nearest boundary distance.

`peek` and `rest` return a fresh, mutable UTF-8 string on every call, including
an empty remainder at EOF. The established handling and return values for zero,
negative, overshooting, and unsupported advance counts remain part of the
compatibility contract.

## Consequences

- ASCII and non-ASCII grammars use O(1) auxiliary cursor memory regardless of
  source size.
- Non-ASCII `advance` and the common zero/one lookaheads are constant-time.
  Arbitrary lookahead deliberately trades bounded relative boundary scanning
  for eliminating a retained Integer per character boundary.
- The cached length and encoding flag are private representation details and do
  not alter token, AST, CST, diagnostic, or grammar IR formats.
- Future cursor changes must preserve both character coordinates and byte span
  boundaries, plus the mutability and encoding of returned source slices.
