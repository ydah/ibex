# 0018: Version generated parser tables

- Status: Accepted
- Date: 2026-07-23

## Context

Generated parser classes and the runtime communicate through an unversioned Hash returned by `.parser_tables`. Future changes to
that private data shape could otherwise make an older generated parser fail deep in a parse, or silently interpret a table with
the wrong semantics after the runtime gem is upgraded.

## Decision

`Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION` is the stable integer version supported by the runtime. Generated classes expose the
same integer as `PARSER_TABLE_FORMAT_VERSION` and include it under `:format_version` in `PARSER_TABLES`. The generator writes a
literal integer, so loading a newly generated parser on an older runtime remains possible while the added Hash member is ignored.

Before reading the first token, the runtime requires `:format_version` to equal its supported version. A missing version is
treated as a legacy, unverifiable table and is rejected rather than guessed compatible. Missing and unsupported versions raise
`Ibex::Runtime::ParseError` with the synthetic `(tables):1:1` location, both version values when available, and an instruction to
regenerate the parser with the installed Ibex version.

Changing the meaning or required shape of parser tables requires incrementing this format version. Additive fields that old
runtimes safely ignore do not by themselves require an increment.

## Consequences

Upgrading the runtime can make hand-written or previously generated unversioned parsers fail immediately; users must regenerate
them or deliberately add the current version to audited hand-written tables. The failure occurs before token consumption or any
semantic action, so an incompatibility cannot partially execute a parse. Current generated parsers and their RBS declarations
make the contract directly inspectable.
