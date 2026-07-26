# ADR 0063: Declarative debug value printers

- Status: Accepted
- Date: 2026-07-26

## Context

Human parser traces need useful semantic values, but calling `inspect` implicitly can expose secrets, execute application code,
or produce unbounded output. A single runtime callback is safe and explicit but cannot express the grammar-level `%printer`
contract required by the extended language or refine each formatter's input type.

## Decision

Extended grammars accept `%printer SYMBOL { Ruby code }` for terminals and nonterminals in the final normalized grammar.
Declarations are unique per symbol and become optional Grammar IR v2 `printers` records containing the canonical symbol name,
opaque code, and source location.

Ruby generation compiles each formatter into a private, source-mapped method receiving `value`. Declared parser parameters are
bound as locals. A compact symbol-id table dispatches formatters for committed shifts and reductions. Generated RBS and static
action-shadow source include the formatter methods and use the symbol's declared semantic type.

Formatting occurs only when `yydebug` is enabled. A parser-wide `trace_value_printer` callback takes precedence over generated
formatters. Formatter exceptions do not affect parsing and are represented only by exception class; the runtime never falls back
to `inspect`.

## Consequences

- Normal parsing does not call formatters or expose semantic values.
- Debug traces can format terminal and reduced nonterminal values independently.
- Formatter code receives the same source mapping, parameter injection, IR round-trip, and static-check support as semantic
  actions.
- Existing grammars omit printer metadata and retain their prior generated table shape.
