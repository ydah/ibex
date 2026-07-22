# 0012: Unknown tokens invoke the error callback

- Status: Accepted
- Date: 2026-07-22

## Context

An external lexer can return an object absent from a generated parser's token map. A black-box probe observed that racc may enter
an `error` production for such an undeclared object without invoking `on_error`, while declared but invalid tokens do invoke the
callback. Silently skipping the callback loses the unexpected token value and prevents consistent logging or policy checks.

## Decision

Assign an unknown external token a temporary negative internal id, preserve its printable representation for `token_to_str`, and
invoke `on_error` through the ordinary syntax-error path. If the callback returns, continue with the same yacc-style `error`
token recovery used for declared invalid lookaheads. The default callback still raises `Ibex::ParseError`.

## Consequences

Every lexer/parser vocabulary mismatch is observable before recovery, and declared and undeclared invalid tokens have one public
callback contract. This is an intentional behavioral difference from the observed undeclared-token racc edge case and is listed
in the migration guide.
