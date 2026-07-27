# ADR 0084: Pack generated integer literals

- Status: Accepted
- Date: 2026-07-27

## Context

The public-parser comparison showed that compact generated files were still
12% to 52% larger than racc output. Inspection attributed most of the
difference to comma-separated Ruby literals for action offsets, action codes,
ownership checks, goto data, and production fields. Those arrays are decoded
once when a generated parser is loaded and then remain frozen for its
lifetime. Replacing them with a compressed data structure in the hot parser
loop would trade source size for runtime cost.

## Decision

Compact generation maps nil to zero and nonnegative integers to their value
plus one, encodes the result with Ruby's BER `w*` pack directive, and writes
the bytes as strict Base64 string literals. The runtime decodes those literals
once into the same frozen Array representation used by the parser loop.

Generated production action Symbols are derived from nonzero action ABI flags
and the production index instead of being repeated in source. Plain table
output and the public constructors remain unchanged.

## Consequences

- Compact generated source scales with the encoded integer width rather than
  decimal spelling and separators.
- Runtime table lookup and parser-loop representations do not change.
- Parser load performs a bounded decode proportional to the generated table
  size.
- The encoding accepts only nil and nonnegative integers; malformed or
  inconsistent packed data raises `ArgumentError` during parser loading.
