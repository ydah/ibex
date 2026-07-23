# ADR 0023: Make generated parser tables Ractor-shareable

- Status: Accepted
- Date: 2026-07-23

## Context

Generated table constants freeze their outer arrays and hashes, but tagged
actions and other nested containers remain mutable. A parser class can be
shared between Ractors, while reading one of these non-shareable constants
from another Ractor fails. Mutating generated tables is not part of the public
runtime contract and can invalidate parser behavior.

JRuby and other Ruby implementations supported by the gem may not implement
Ractor, so loading a generated parser must not require that API.

## Decision

For grammars using standard symbol and literal token mappings, generated code
conditionally calls `Ractor.make_shareable(PARSER_TABLES)` when Ractor and that
method are available. The operation transitively freezes the plain or compact
ACTION and GOTO data, defaults, token maps, and production records. It runs once
when the generated class loads, before `.parser_tables` can expose the table
set.

An explicit `convert` declaration is arbitrary Ruby source and can return a
caller-owned mutable object or an inherently unshareable object such as
`Thread.current`. Generated parsers with any custom conversion therefore retain
the established shallow-freeze behavior and do not call
`Ractor.make_shareable`. Loading a parser must neither reject such a conversion
nor freeze an object owned by the application.

When eligible, the same operation is emitted for embedded and
runtime-requiring parsers. Implementations without the Ractor API retain the
existing explicit outer freezes. This is an immutability guarantee, not a
change to parser-table format version 1.

## Consequences

- A generated parser class and its table graph can be read from another Ractor
  on Ruby implementations that support Ractor shareability, provided it uses
  only standard token mappings.
- Attempts to mutate nested generated table data fail instead of silently
  corrupting parser behavior for that shareable subset.
- Parser tables containing custom converted token objects are not guaranteed to
  be Ractor-shareable; compatibility and application object ownership take
  precedence.
- Parser instances remain ordinary mutable objects and must be created and
  used within one execution context.
- Hand-written runtime subclasses remain responsible for freezing their own
  table graphs.
