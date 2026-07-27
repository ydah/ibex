# ADR 0064: Versioned generated lexer

- Status: Accepted
- Date: 2026-07-26

## Context

Handwritten `next_token` methods keep the runtime general, but repeat matching,
state, streaming, and location code across grammars. Lexer rules must survive
source parsing, JSON resumption, parser generation, and static validation
without becoming an unversioned field hidden inside Grammar IR.

Ruby regular expressions can require unbounded work. General partial-regexp
matching is also unavailable, while IO and Fiber chunks may end inside a token.

## Decision

Extended roots may contain one root-only `lexer` declaration. Normalization
produces immutable Lexer IR v1 with its own discriminator and schema version.
Grammar IR v2 optionally embeds that exact document; `--emit=lexer-ir` and
`validate-ir` expose the standalone contract.

Rules are flat after named state blocks. Runtime matching prepends `\A`, tries
the active state's rules in declaration order, selects the longest match, and
uses the lowest rule id for a tie. Empty matches are rejected. Token rules
return their lexeme or action result; `skip` consumes; `on` explicitly emits or
skips. Mutable buffers and state stacks remain per parser instance.

The incremental input adapter accepts String, IO, and Fiber. When a match could
extend at a chunk boundary it reads another chunk and retries, so token and
position results do not depend on chunking. Locations retain grapheme and byte
columns and half-open byte offsets. Parser actions may set only the documented
`lexer_state` API; reductions containing that assignment may run before
requesting speculative lookahead.

Static lint warns on common nested-quantifier ReDoS shapes and strict warnings
may reject them. Documentation explicitly leaves arbitrary-regexp safety and
untrusted-input bounds with the application.

## Consequences

- Existing handwritten lexers and push/yield parser inputs remain compatible.
- Lexer JSON can evolve independently from Grammar and Automaton IR versions.
- Streaming correctness favors a simple O(rules) retry strategy over a DFA or
  regex-engine-specific partial-match API.
- Lexical states are exclusive, flat, and explicit; hidden global mode is not
  introduced.
- The lint is a review aid, not a security proof.
