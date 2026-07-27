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
offsets and allocate no offset table. Non-ASCII sources build one frozen array
that maps every character boundary, including EOF, to its byte offset.

`advance` reads only the current leading byte to recognize LF and moves through
the cached boundaries without creating one-character strings. Public `index`
and columns remain character-based; `byte_offset` and spans remain byte-based.

`peek` retains `String#[]` absolute character-index behavior, including negative
indices, and slices the corresponding byte range. `peek` and `rest` return a
fresh, mutable UTF-8 string on every call, including an empty remainder at EOF.
The established handling and return values for zero, negative, overshooting,
and unsupported advance counts remain part of the compatibility contract.

## Consequences

- ASCII grammars avoid both per-character strings and an offset map.
- Non-ASCII scanning has constant-time character lookup and advance at the cost
  of one Integer entry per character boundary.
- The offset map and cached length are private representation details and do
  not alter token, AST, CST, diagnostic, or grammar IR formats.
- Future cursor changes must preserve both character coordinates and byte span
  boundaries, plus the mutability and encoding of returned source slices.
