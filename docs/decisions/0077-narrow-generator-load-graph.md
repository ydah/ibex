# ADR 0077: Narrow the ordinary generator load graph

- Status: Accepted
- Date: 2026-07-27

## Context

The command-line generator loaded the complete public frontend, IR, LALR, and
runtime entry points before it parsed any options. Ordinary Ruby generation
therefore initialized formatting, diagnostic recovery, the Ruby DSL, IR
migration and validation, and conflict-counterexample search even though none
of those implementations participates in the default grammar-to-Ruby path.
Fresh-process profiles of the fixed public grammars showed this bootstrap work
as a dominant cold-generation cost.

The broad `require "ibex/frontend"`, `require "ibex/lalr"`, and
`require "ibex/runtime"` entry points are public convenience surfaces. Making
those public entry points partial or order-dependent would trade startup time
for surprising library behavior.

## Decision

The ordinary CLI loads an internal `ibex/frontend/generation` surface containing
the strict parser, resolver, and their direct dependencies. It loads the
Grammar, Lexer, and Automaton IR definitions used by normalization and
construction, while loading IR validation only when `--from` needs it.

The default generator loads only the LALR builder and the construction
components it calls. Counterexample option defaults come from the small shared
search-limits module; the search and rendering implementations remain
demand-loaded by commands and outputs that use them.

The public frontend, IR, LALR, and runtime entry points retain their complete
surfaces. Optional CLI features continue to declare their own dependencies.
Load-graph tests make the deferred boundary observable so a new eager
dependency cannot silently return to the cold path.

## Consequences

- Fresh ordinary generation avoids loading unrelated editor, diagnostic,
  migration, and conflict-search implementations.
- Public `require` behavior is unchanged.
- A file used by the internal generation surface must declare its real
  dependencies instead of relying on a broad aggregator having run first.
- New default-pipeline features must be added to the narrow surface
  deliberately; optional features remain demand-loaded.
