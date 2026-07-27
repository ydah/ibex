# 0052: Separate static racc migration checks from differential execution

- Status: Accepted
- Date: 2026-07-25

## Context

A migration command can inspect grammar structure safely, but comparing semantic results necessarily executes grammar actions and
user code. Running those actions inside the generator process, or automatically as part of a check command, would turn a
read-only compatibility inspection into arbitrary application-code execution. A useful workflow must make that boundary
visible, keep generation deterministic, and still automate the repetitive two-generator/two-parser comparison.

## Decision

`ibex migrate-check [--format=text|json] GRAMMAR` is static. It parses and normalizes in default mode, reports structured syntax and
normalization failures, detects an explicit `Racc::` superclass, and flags user-code chunks that require the racc runtime or
reference a `Racc::` constant. Opaque semantic actions and user-code chunks are never evaluated. Errors produce status 1;
warnings remain compatible and produce status 0. JSON follows `schema/migration-check-v1.schema.json`.

`ibex migrate-harness [-o FILE] GRAMMAR` first requires a successful static check and then emits a standalone Ruby program. It
does not invoke racc, Ibex, Ruby, or grammar code while generating the file. The generated program starts with an empty `CASES`
array and refuses to run until the user adds an explicit reviewed token corpus.

Running the generated program is an explicit application-code execution boundary. Its header says so. It:

- invokes generator and parser commands as argument arrays without a shell;
- generates into a private temporary directory;
- embeds the Ibex runtime in the comparison parser;
- runs each parser in a separate Ruby child process;
- sends ordinary test token/value arrays through Marshal data owned by the harness;
- compares result/error payloads plus incidental stdout and stderr;
- limits every child to 15 seconds and 1 MiB per output stream; and
- removes the temporary directory on exit.

`RACC` and `IBEX` environment variables select single executable paths. Subprocess separation is not a security sandbox:
untrusted grammars still require a container, VM, or other boundary chosen by the user. Custom parser constructors,
non-Marshallable values, external services, and filesystem assertions require editing the generated harness and remain
application-owned.

## Consequences

- CI can gate grammar syntax and known runtime coupling without executing application code.
- Teams get a reviewable starting point for repeatable black-box parity cases instead of a hidden execution side effect.
- The generated harness is intentionally source, not a long-lived Ibex runtime API; users own its cases and isolation policy.
- The clean-room compatibility boundary remains based on public commands and observable behavior.
