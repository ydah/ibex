# 0026: Carry optional input locations into structured parse errors

- Status: Accepted
- Date: 2026-07-23

## Context

The runtime reports expected tokens but exposes only a formatted exception string at the synthetic `(input):1:1` location.
Editors, command-line applications, and AST builders need machine-readable error context. Lexers can already produce locations,
but the public token source contract has no place to carry one.

Full semantic-location support also requires a parallel location stack, reduction span rules, and a generated-action API. Folding
that larger contract into basic syntax diagnostics would unnecessarily change parser tables and action methods.

## Decision

Pull and yielding token sources may return `[token, value, location]` in addition to the compatible two-element form. Caller-driven
`push` accepts the same optional third argument. `[nil, nil, location]` represents located EOF for a pull source, while
`finish(location:)` does so for a push session. A location is an application-owned object; the default formatter understands a
Hash or object exposing `file`, `line`, `column`, and optional `source_line`. The runtime stores it only for the current lookahead.

The default `on_error` raises `ParseError` with readers for token id/name/value, expected token names, parser state, location, and
deterministic spelling suggestions. When `source_line` is supplied, the message includes that line and a caret. Constructing
`ParseError.new(message)` remains compatible for table and application errors that have no token context.

Suggestion matching is deliberately conservative: only word-like token names participate and the normalized edit distance must
fit a small length-derived threshold. It is presentation metadata and never changes recovery or token identity.

## Consequences

Existing lexers, `on_error` overrides, and parser tables remain compatible. Applications can render their own diagnostics from
exception attributes without parsing strings. `@1`/`@$`-style semantic locations, reduction spans, and location-aware action RBS
remain a separate table/action-contract phase.
