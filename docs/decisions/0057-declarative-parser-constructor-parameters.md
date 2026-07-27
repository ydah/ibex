# ADR 0057: Declarative parser constructor parameters

- Status: Accepted
- Date: 2026-07-26

## Context

Applications often need one shared context in semantic actions and lexer methods. Requiring every generated parser to hand-write
an initializer weakens generated RBS, is easy to break when a superclass changes, and cannot survive Grammar IR round trips.
The extended grammar design calls this `%param`.

## Decision

Extended root grammars accept `%param name` and `%param name "RBS type"`. Names are unique Ruby local identifiers and Ruby
keywords are rejected. Parameters are additive optional Grammar IR v2 metadata; metadata-free documents retain their prior
bytes, and v1 does not accept the field.

Generated parsers prepend a small initializer module. It consumes the declared required keywords, assigns matching instance
variables before calling `super`, and forwards remaining keywords. Every explicit semantic-action method binds same-named locals
from those variables, including middle and composed inline actions. An `inner` lexer method accesses the shared object through
the instance variable.

Generated RBS declares the constructor keyword types and instance variables. Missing types become `untyped`; the same
declarations support static action-shadow checking. A `%param` declaration is root-only because fragments cannot independently
change the constructor contract.

## Consequences

- Parser dependencies are explicit at construction and preserved through IR serialization.
- Semantic actions, lexer methods, generated runtime code, RBS, and static shadow source share one injection contract.
- Existing grammars emit byte-identical constructor-free generated code.
- A user initializer remains reachable through `super`; undeclared remaining keywords follow the superclass contract.
