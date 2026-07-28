# ADR 0002: Keep grammar-embedded Ruby opaque until code generation

- Status: Accepted
- Date: 2026-07-28

## Context

Semantic actions and user-code sections contain Ruby constructs whose braces,
quotes, regular expressions, interpolation, and heredocs overlap grammar
delimiters. Parsing Ruby in the grammar frontend would add a second language
implementation and would still not validate parser-local bindings correctly.

## Decision

The grammar lexer delegates action bodies to a balanced source scanner. That
scanner recognizes only the Ruby lexical structure needed to find the matching
grammar boundary and preserves the original bytes and source location.
User-code sections are likewise retained as ordered opaque chunks.

The frontend, normalizer, IR tools, reports, and static analysis never evaluate
or rewrite the opaque body. Ruby compilation occurs only when generated parser
methods are loaded. Tools that promise not to execute application code must
operate entirely before that boundary.

## Consequences

- Grammar parsing is independent of a Ruby parser and preserves exact user
  source for mapping and generation.
- The balanced scanner has an explicit lexical coverage obligation; unsupported
  Ruby syntax must fail instead of being silently truncated.
- Features that need meaning from an action must use conservative lexical
  evidence or decline the optimization.
