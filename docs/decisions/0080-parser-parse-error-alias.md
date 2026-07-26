# ADR 0080: Expose the parser-local parse error alias

- Status: Accepted
- Date: 2026-07-26

## Context

A maintained public grammar uses `raise ParseError` inside semantic actions to
reject combinations that are syntactically valid but invalid for the
application. The generated parser class inherits that constant from its parser
runtime in the established API.

Ibex already provides the structured `Ibex::Runtime::ParseError`, but it was
defined beside `Runtime::Parser` rather than on the class. Consequently,
unqualified lookup in an application action raised `NameError` and bypassed
the application's intended rescue path.

## Decision

`Ibex::Runtime::Parser::ParseError` is a constant alias of
`Ibex::Runtime::ParseError`. Generated parser subclasses therefore resolve an
unqualified `ParseError` through ordinary ancestor constant lookup.

The exception class, message contract, and unknown-token `on_error` behavior
do not change.

## Consequences

- Existing semantic actions retain their explicit rejection and rescue flow.
- There is one exception class, not a wrapper or translated failure.
- New code may use the fully qualified structured error name for clarity.
