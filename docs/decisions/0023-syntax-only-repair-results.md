# ADR 0023: Keep editor repair proposals syntax-only

## Status

Accepted as an Experimental runtime API boundary.

## Context

The semantic repair path selects a `RepairPlan` whose buffered token positions
and replay values are meaningful to a parser application, but an editor needs
source edits and a fresh syntax result. Exposing replay values would couple the
editor boundary to application semantic actions and could be mistaken for an
intent or correctness guarantee.

## Decision

Add `SyntaxSession#repair` as a separate, additive operation. It runs a fresh
private parser with production actions suppressed, captures token identity and
absolute byte ranges, resolves source spelling only from caller-provided text
or conservative punctuation literals, applies byte edits to an immutable
`SourceText`, and validates the edited bytes with another fresh syntax session.
The result contains bounded search status, immutable syntax edit metadata,
diagnostics, exact updated source bytes, and the validation snapshot, but no
semantic value. The originating session is never mutated and the application's
repair callback is not invoked.

## Alternatives rejected

1. Reuse the semantic replay result: rejected because it would expose or
   fabricate application values and would make editor output depend on action
   execution.
2. Add a second editor-specific search algorithm: rejected because it would
   create two bounded-search semantics and a new proof surface.
3. Infer arbitrary token spellings: rejected because a token name does not
   define source bytes; missing named-token spelling therefore fails closed.

The v1 boundary accepts one selected repair segment. Overlapping edits,
multiple segments, exhaustion, cancellation, and hard service limits cannot
be converted into successful results.

## Consequences

The runtime API and RBS surface grow additively while parser-table format v6,
IR schemas, and grammar syntax remain unchanged. Embedded generated parsers
must be regenerated to acquire the implementation. Accepted proposals prove
only fresh syntactic acceptance; they do not prove semantic correctness or
user intent. Error validation retains exact edited bytes separately because an
error CST may contain only the consumed prefix.
