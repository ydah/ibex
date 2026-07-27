# ADR 0054: Isolate browser grammar analysis in a replaceable worker

- Status: Accepted
- Date: 2026-07-26

## Context

Ibex's Pure Ruby implementation can run through ruby.wasm, but browser input is
untrusted grammar text and analysis can perform bounded but nontrivial work.
The browser has no process boundary, semantic action bodies must remain opaque,
and a stalled VM must not make the page permanently unusable.

## Decision

The Ruby VM and every grammar-analysis operation run in a dedicated module
worker. The main thread terminates and replaces the worker after 15 seconds.
Input is limited to 100,000 bytes, frontend diagnostics to 20, displayed
conflicts to 100, and counterexample search to the library's token and
configuration budgets. Parameter and inline expansion retain their library
bounds.

Grammar text crosses the JavaScript/Ruby boundary as UTF-8 hex decoded by
`Array#pack`; it is never interpolated into Ruby source. The browser bundle
uses the same frontend, normalization, automaton, and serialization components
as the Ruby library. Semantic action bodies stay opaque and are never
evaluated.

Assets are self-hosted under a Content Security Policy that permits only
same-origin resources and the WebAssembly compilation needed by ruby.wasm.
The main thread owns form interaction and worker replacement; the worker owns
all Ruby objects and returns only serialized analysis results.

The interface has explicit labels, keyboard submission, visible focus, live status text, at least 44-pixel controls, responsive
single-column behavior, and reduced-motion handling. Analysis results can be downloaded as Automaton IR without a server
round-trip.

## Consequences

- Untrusted grammar work cannot block the main thread beyond the replacement
  timeout or retain Ruby state after replacement.
- No application server or submitted-source storage exists.
- A roughly 31 MiB WebAssembly asset is paid by the browser and can be cached
  independently from analysis results.
- Browser support follows ruby.wasm, Web Workers, WebAssembly, module scripts, and the declared Content Security Policy.
