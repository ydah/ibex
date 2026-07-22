# ADR 0019: Enable extended grammar syntax with a file pragma

## Context

Extended EBNF and named references can currently be selected only by passing `--mode=extended`. The design also promises a
grammar-local `pragma extended` form. A grammar-local switch must take effect while the frontend is parsing later productions,
without leaking parser configuration into normalized Grammar IR or making resumed IR pipelines depend on source-only directives.

## Decision

`pragma extended` is an optional preamble directive. It appears after the `class` line (including an optional superclass) and
before `token`, precedence, `options`, `expect`, `start`, `convert`, or `rule`. The directive enables extended syntax for the rest
of that grammar. It may promote CLI/API `mode: :racc` to extended mode; `mode: :extended` remains extended whether the pragma is
present or absent. A CLI option never disables an explicit grammar pragma.

Only `extended` is defined. An unknown pragma value fails at the value location. A second pragma fails at its `pragma` keyword,
even if both values are `extended`. A pragma after a regular declaration is outside the preamble and fails as a positioned
declaration syntax error.

The bootstrap and generated frontends consume the directive as parser configuration. It creates no AST node and makes no
Grammar IR schema change. Therefore AST output describes the grammar's semantic declarations and rules, while Grammar IR and
Automaton IR resumed pipelines remain independent of the source directive.

## Consequences

- A grammar can opt into extensions without requiring a command-line convention at every invocation.
- Compatible grammars without the pragma retain `racc`-mode rejection of extended syntax.
- The directive cannot silently change meaning through duplication or an ignored unknown value.
- Tooling that needs to retain the spelling of source directives must inspect the source; the semantic IR deliberately does not.
