# ADR 0046: Generate non-executable semantic-action shadow source

- Status: Accepted
- Date: 2026-07-25
- Supersedes: the opaque-action static-checking boundary in ADR 0035

## Context

Generated parser RBS describes reduction method boundaries, but ordinary parser output mixes those methods with runtime tables,
runtime loading, and user `header`, `inner`, and `footer` code. Pointing Steep at that runtime artifact makes the static-checking
input depend on executable infrastructure and still leaves composed inline fragments without public signatures. Extracting
action text through a second formatter would risk checking code that differs from the code actually generated, especially for
named references, result-variable mode, semantic locations, and heredocs.

Inline action plans also identify physical and prior-step value slots without retaining the semantic type of each logical step.
After IR serialization, a generator can therefore recover physical symbol types but cannot type a reference to an eliminated
reduction result.

## Decision

`ibex --action-source[=FILE]` opt-in generates a Ruby shadow source intended only as a Steep input. With no explicit path it is
written beside the parser by replacing the parser extension with `.actions.rb`; `parser.rb` therefore produces
`parser.actions.rb`. `--check` compares the requested shadow source byte-for-byte and reports missing or stale content without
rewriting it. Input, parser, RBS, action source, report, message, and visualization targets are checked pairwise through their
canonical filesystem identities before generation writes anything.

The shadow source reopens the grammar's real module and class names without requiring or inheriting from the runtime parser. It
contains only private semantic reduction or composed-fragment method definitions. Parser tables, generated orchestration,
runtime requires, and `header`, `inner`, and `footer` blocks are omitted. Its preamble states that it is static-check-only and
must not be loaded or executed. Every method has a preceding `file:line:column` grammar-origin comment.

Runtime Ruby generation and shadow generation use one action-method source builder. The builder owns the exact method body,
named-reference bindings, result-variable initialization/return, location rewriting, middle-action context, and composed
fragment source. Quoted and dynamic heredocs remain opaque action text handled by the existing scanner and therefore pass
through the same builder. Enabling the shadow source does not alter ordinary parser output.

Generated parser RBS now declares private composed-fragment methods in addition to the composed orchestrator. New Grammar IR v2
composition-plan output always includes a nullable `result_type`. The input schema keeps that field optional so v2 documents
written before ADR 0046 remain loadable and fall back to `untyped`. Normalization records the eliminated production LHS semantic
type; the caller step records the final production LHS type. A generator resolves a fragment input type from either the
flattened physical RHS symbol or a preceding step's `result_type`, so direct and reloaded v2 IR produce the same typed
signatures. A missing semantic type remains `null` in new JSON and `untyped` in RBS. Version-1 output continues to omit
composition plans.

Ibex never invokes Steep. Static checking is an explicit application or CI execution boundary: callers generate Ruby, RBS, and
the shadow source, then configure and run their chosen Steep command. `Ibex::RakeTask#action_source` exposes the same opt-in as
`nil`, `true` for the default path, or an explicit String path.

## Consequences

- Semantic bodies can be checked without loading parser runtime code or executing any grammar-provided Ruby.
- The checked body is built by the same component as runtime action methods, preventing a second semantic formatter from
  drifting.
- Composed inline values retain enough v2 IR type data for deterministic checking after dump/load.
- The shadow file is not an application entry point and deliberately excludes user helper method implementations; applications
  declare those APIs in their RBS as usual.
- Existing CLI and generated-parser output are byte-identical when the opt-in is absent.
