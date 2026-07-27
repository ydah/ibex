# ADR 0079: Drive eligible compact pull parsers from displacement arrays

- Status: Accepted
- Date: 2026-07-27

## Context

Profiles of the fixed Namae, BCDice, and Nokogiri grammars showed that an
eligible runtime session still crossed the generic action-selection,
table-lookup, and action-dispatch methods for every LR step. Those boundaries
are necessary when debugging, locations, recovery, CST construction,
observers, or application hooks can observe the parser. They are redundant
after the existing fast-path gate has proven that none of those facilities is
active.

Generating a grammar-specific `case` driver would remove dispatch too, but it
would substantially increase generated source and duplicate the runtime state
machine in every parser. Compact tables already expose immutable
row-displacement arrays that can support a shared direct driver.

## Decision

Compact Ruby generation marks its parser tables with
`compact_fast_driver: true`. Plain tables and older generated parsers omit the
marker.

For pull parsing only, the runtime enters a shared compact driver when:

- the existing runtime fast-path gate accepts the session;
- both action and goto tables are exact `Ibex::Tables::Compact` instances;
- the generated compact-driver marker is present; and
- the grammar has no eager reductions.

The driver snapshots the session's frozen action, goto, production, and
default-action tables, then performs ordinary shifts, actionless reductions,
values-only generated reductions, and acceptance directly from the compact
arrays. It keeps stack-limit checks and the versioned values-only action ABI.

The generic driver remains authoritative for push parsing, eager reductions,
unknown tokens, syntax errors, malformed or unsupported production shapes,
locations, recovery, CST construction, debug output, observers, application
hooks, and non-compact tables. Lexer and semantic-action callbacks retain the
existing invalidation boundary. If either callback enables an observable
facility, the committed operation finishes with its required hooks and the
next action resumes in the generic driver. No token or parser action is
replayed during fallback.

## Consequences

- Eligible generated compact pull parsers avoid repeated method dispatch and
  generic table introspection in their LR loop.
- Generated source grows only by one parser-table marker rather than by a
  grammar-sized driver.
- Existing parser tables and all observable runtime modes keep the generic
  behavior.
- Eager-reduction grammars can be admitted later only after their pre-lookahead
  feedback boundary has dedicated equivalence coverage.
