# 0033: Generate bounded samples from productive derivations

- Status: Accepted
- Date: 2026-07-23

## Context

Grammar authors need small valid token sentences for smoke tests and fuzz seeds. Blind random expansion can loop on recursive
rules, exceed useful sizes, or fail opaquely when the start symbol derives no terminal sentence.

## Decision

`Ibex::Samples` computes exact, arbitrary-precision integer minimum terminal costs and derivation heights for Grammar IR symbols.
An absent minimum is represented separately from a finite cost, so very large finite derivations are not confused with an empty
language. Reverse production dependencies propagate improved minima without repeatedly scanning every production.

Seeded generation may choose among productive alternatives while below the depth bound. At the bound it chooses minimum-height
alternatives, which forces progress toward terminals. Generation uses an explicit work stack rather than the Ruby call stack. A
token budget is checked before and during expansion, and a configurable total expansion-step limit bounds work from deeply nested
or nullable derivations. The library default is 100,000 steps per `generate` call; `ibex samples --max-expansions` exposes the same
limit.

Samples contain canonical grammar terminal names, not display labels or semantic values. The generator is deterministic for the
same Grammar IR, seed, count, and bounds. It reports empty languages and impossible budgets as `Ibex::Error`.
`ibex samples` exposes the generator as JSON Lines and can resume from either versioned IR stage.

## Consequences

Generated sentences are suitable as lexer-token fixtures and fuzz seeds without adding a property-testing dependency. They prove
syntactic derivability only; applications still choose semantic token values and can layer corpus-specific weighting separately.
