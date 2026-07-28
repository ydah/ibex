# ADR 0016: Represent concrete syntax with immutable Green data and lazy Red views

- Status: Accepted
- Date: 2026-07-28

## Context

A lossless syntax tree must support sharing, navigation, recovery, and editing.
Nodes containing absolute offsets, parents, or semantic action results cannot
be safely interned or reused at multiple source occurrences.

## Decision

Green nodes, tokens, and trivia are immutable, position-independent values.
They contain integer kinds, source bytes, child structure, flags, and derived
widths, but no parent, absolute location, parser instance, or semantic value.
Tokens own trivia deterministically, including final trivia on EOF.

Red values are lazy occurrence views over Green values. They provide parents,
child indexes, and absolute offsets without changing Green identity.

CST-aware parsers maintain a Green stack parallel to the semantic stack.
Every physical reduction builds syntax independently of whether a semantic
action exists. Recovery and repair produce flagged syntax, and the public
syntax root is a synthetic `source_file` containing the selected start node
and EOF. Structured CST metadata in the parser-table ABI selects this path.

## Consequences

- Equal Green subtrees can be interned, shared across Ractors, and reused at
  multiple Red occurrences.
- Syntax shape does not depend on semantic action return values.
- Absolute navigation allocates Red wrappers lazily, while Green construction
  must preserve exact source width and trivia ownership.
