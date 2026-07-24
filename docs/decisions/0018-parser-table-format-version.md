# 0018: Version generated parser tables

- Status: Accepted
- Date: 2026-07-23

## Context

Generated parser classes and the runtime communicate through an unversioned Hash returned by `.parser_tables`. Future changes to
that private data shape could otherwise make an older generated parser fail deep in a parse, or silently interpret a table with
the wrong semantics after the runtime gem is upgraded.

## Decision

`Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION` is the current integer version emitted by the generator. Generated classes expose
the same integer as `PARSER_TABLE_FORMAT_VERSION` and include it under `:format_version` in `PARSER_TABLES`. The runtime separately
publishes `SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS`, the frozen set of versions it can interpret.

Before reading the first token, the runtime requires `:format_version` to belong to that supported set. A missing version is
treated as a legacy, unverifiable table and is rejected rather than guessed compatible. Missing and unsupported versions raise
`Ibex::Runtime::ParseError` with the synthetic `(tables):1:1` location, the accepted versions when available, and an instruction
to regenerate the parser with the installed Ibex version.

Changing the meaning or required shape of parser tables requires incrementing this format version. Additive fields that old
runtimes safely ignore do not by themselves require an increment. Version 2 adds the generated-action `location_action` contract:
v2 `_ibex_action_N` methods marked with that field receive five location-aware arguments. The current runtime retains v1 in its
accepted set and invokes every v1 action with the historical two arguments, even if an audited hand-written v1 table happens to
contain a field with the same name. Older runtimes that accept only v1 reject v2 tables before token consumption.

## Consequences

Upgrading the runtime can make hand-written or previously generated unversioned parsers fail immediately; users must add an
audited supported version or regenerate them. Supported older generated tables remain executable, while unsupported future
tables fail before token consumption or any semantic action. Current generated parsers and their RBS declarations make the
contract directly inspectable.
