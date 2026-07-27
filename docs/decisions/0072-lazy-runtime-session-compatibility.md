# ADR 0072: Complete legacy parser sessions lazily

- Status: Accepted
- Date: 2026-07-26

## Context

The public-gem migration KPI exposed two established application patterns that
the repository fixtures did not exercise:

1. a parser-specific `initialize` method that configures lexer state without
   calling `super`; and
2. a lexer that reads the active semantic-value stack through `@vstack` or
   `@racc_vstack`.

Requiring either application to be rewritten would make a generated-parser
replacement depend on runtime implementation details. Overriding class
allocation or injecting another generated initializer would also change Ruby
constructor dispatch and could conflict with declarative parser parameters.

## Decision

`Runtime::Parser` completes missing runtime session state at the first public
runtime operation. Normal `super` initialization remains eager. Lazy
completion preserves instance variables already assigned by application code,
including debug configuration, and supplies defaults only for missing runtime
state.

Each newly installed semantic-value stack is also exposed through `@vstack`
and `@racc_vstack`. Both aliases point at the same live array used by the
runtime. They are read-compatibility surfaces only; mutation, replacement, and
retention across sessions are unsupported.

Observation registration, configuration access, pull parsing, push parsing,
and push reset all cross the lazy-initialization boundary before reading
session state.

## Consequences

- Existing parser initializers can remain unchanged when they omit `super`.
- Tokenizers that use either historical value-stack name observe current
  semantic values.
- The runtime does not override application state already configured before
  first use.
- Same-instance concurrent first use remains outside the parser contract;
  concurrent parses require distinct parser instances.
- New integrations should use public callbacks and semantic-action arguments
  instead of the internal value-stack aliases.
