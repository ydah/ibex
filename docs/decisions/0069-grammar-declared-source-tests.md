# ADR 0069: Grammar-declared source tests

- Status: Accepted
- Date: 2026-07-26

## Context

Parser examples kept only in application test files can drift away from the
grammar they document. A grammar-level acceptance suite needs to travel through
includes, normalization, IR validation, and CI without becoming executable
during ordinary parser generation.

Executing arbitrary semantic actions inside the CLI process would let a test
change global constants, terminate the command, or accidentally run a generated
footer. Lexical failures also need to remain distinct from expected syntax
rejections.

## Decision

Extended roots accept ordered declarations:

```text
%test accept "1+2*3"
%test reject "1+"
```

The source must be a double-quoted Ruby string literal. The frontend decodes it
once and Grammar IR v2 stores `expectation`, decoded `source`, and declaration
location. Exact duplicate expectation/source pairs are errors. Tests are
root-only, optional metadata and are not emitted into runtime parser tables.
Version-1 migration records that grammar-test metadata was unavailable.

`ibex test GRAMMAR` builds the selected automaton, generates one embedded parser
in a temporary directory, and loads it from a separate child runner so guarded
footer code does not run. Each case receives a fresh zero-argument parser
instance and calls its `parse(source)` method. A normal return is acceptance;
`Ibex::Runtime::ParseError` is rejection; every other exception is a test error.
Parsers with required `%param` declarations are rejected because the grammar
does not define constructor fixtures.

The suite runs in a child Ruby process under one configurable positive timeout,
ten seconds by default. The command emits ordered TAP-like lines and exits
nonzero for a mismatch, test error, timeout, malformed child result, or empty
suite. Gallery grammars run through a dedicated CI job.

## Consequences

- Acceptance examples and parser syntax evolve in one reviewed file.
- Ordinary generation remains declarative; tests execute only through the
  explicit command.
- Child-process isolation contains constant pollution and `exit`, although it
  is not a security sandbox for untrusted grammars.
- A grammar must expose the small `parse(String)` integration method until the
  generated lexer contract supplies it automatically.
- Constructor-dependent parsers need external application tests or a future
  explicit fixture declaration.
