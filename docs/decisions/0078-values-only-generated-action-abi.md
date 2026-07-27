# ADR 0078: Version values-only generated semantic actions

- Status: Accepted
- Date: 2026-07-27

## Context

Generated semantic-action methods historically received five runtime
arguments: the reduction values, a copy of the remaining value stack, the
reduction locations, a copy of the remaining location stack, and the result
location. Composed actions added a sixth lookahead-location argument. Most
ordinary public grammars use only `val`, but each reduction still constructed
the unused stack and location snapshots before dispatch.

The runtime also has an observability-gated fast path for actionless
reductions. Extending that path to arbitrary actions would be unsound:
application callables retain the historical two-argument contract, generated
actions may depend on locations or left context, and an action can install
debugging, observers, hooks, or semantic control flow while it runs.

## Decision

Parser-table format v4 adds an explicit `values_action: true` production
marker. The runtime honors it only for a generated `_ibex_action_N` Symbol.
Such a method receives one argument: its reduction-values array. Unmarked
actions retain the two-argument application ABI, `location_action` retains the
five-argument generated ABI from format v2, and `composition_action` retains
the six-argument ABI from format v3. Formats v1 through v3 ignore the new
marker and continue to execute their original contracts.

The generator selects the values-only ABI only when the action needs no
left-context stack, composition plan, semantic location expression
(`@N`, `@$`, `loc`, or `result_loc`), or legacy generated parameter
(`_values`, `_ibex_locations`, `_ibex_location_stack`, `_ibex_location`, or
`_ibex_lookahead_location`). AST constructors and requested implicit actions
are values-only. Location and legacy-parameter detection uses Ruby lexical
tokens so strings, comments, regular expressions, symbols, and heredoc bodies
do not create false dependencies.

Format-v4 tables are rejected before input when a values marker names anything
other than a generated Symbol, is combined with a location or composition
marker, or declares a nonzero location context. Format-v3 composition tables
remain accepted after the current version advances.

An unobserved, location-free values-only reduction may use the runtime fast
path. It preserves separate pre-action hook values and mutable action values.
The action sees a shared frozen empty semantic-location array, so the ordinary
case does not allocate a per-reduction location array. If the action installs
a reduction hook, enables debug or observation, requests `yyaccept` or
`yyerror`, or otherwise invalidates eligibility, the reduction completes the
same generic tail ordering. A newly installed location hook receives a lazily
materialized all-nil location array of the correct RHS length. A newly
installed observer starts at the next documented event boundary; debug output
includes the current reduction, as in the generic path.

Ruby truthiness defines debug eligibility. Both `false` and `nil` mean debug is
disabled; every truthy value selects the generic path.

Parser-table version constants live in the lightweight
`runtime/table_format.rb` boundary so generator loading does not require the
runtime parser implementation merely to emit the current version.

## Consequences

- Ordinary generated actions avoid copies of the value stack and location
  stack, location-span construction, and dormant location-hook payloads.
- Existing hand-written actions and parser tables keep their exact two-,
  five-, and six-argument dispatch contracts.
- Source that intentionally used a formerly generated parameter continues on
  the five-argument ABI rather than being silently broken.
- Location-, context-, composition-, CST-, debug-, observed-, repaired-, and
  recovery sessions retain the generic runtime as their authority.
- The values-only marker is an internal generated-code contract. Manually
  marking an action that depends on omitted inputs violates the table ABI and
  is rejected when that dependency is representable in table metadata.
