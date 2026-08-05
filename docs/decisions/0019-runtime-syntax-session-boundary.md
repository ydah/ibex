# ADR 0019: Keep generated-language syntax sessions in the runtime

- Status: Accepted
- Date: 2026-08-05

## Context

The Red/Green CST and incremental parser already provide syntax-only parsing,
but application integrations otherwise have to assemble trust checks, edits,
failure expectations, fallback evidence, cancellation, and resource bounds.
This boundary is for one loaded generated language. It is not the existing
grammar-authoring LSP and has no workspace or protocol semantics.

Generated lexer actions and generated-file user sections are arbitrary Ruby.
A session-time flag cannot make an already loaded parser class safe.

## Decision

Add an Experimental `SyntaxSession` façade to `ibex-runtime`, backed solely by
the existing `IncrementalParseSession`. Current parser classes expose
`:trusted_application_code` and require that exact profile as an explicit
caller acknowledgement. No `:declarative` mode is exposed until the generator
can produce a separate action-free syntax artifact with a declarative lexer and
without user-code sections.

Return immutable result and metric snapshots. Treat syntax errors as results,
but represent cancellation and hard resource exhaustion with distinct
exceptions. Preserve the previous completed session state when an edit aborts.

Keep the boundary in `ibex-runtime`: deployed generated languages need the
runtime but not grammar construction. Do not create `ibex-workbench` until a
larger editor-service boundary has independent demand. Do not add LSP,
workspace, indexing, query, or formatting behavior here.

## Consequences

- Parser production actions remain suppressed; lexer actions and runtime hooks
  remain explicit trusted application execution.
- Fresh syntax parsing remains the correctness oracle and the existing CST
  implementation remains the only parser/tree engine.
- Generator output and normal semantic parse behavior do not change.
- Cancellation is cooperative and cannot preempt a nonreturning Ruby lexer
  action.
- The façade remains part of the existing Experimental incremental-CST product
  surface rather than claiming a new Stable editor platform.
