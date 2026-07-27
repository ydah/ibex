# Implementation architecture decisions

This directory records decisions about the implementation of Ibex itself.
An ADR belongs here when it fixes a durable choice in executable behavior or
architecture, such as:

- grammar, lexer, parser, runtime, or CLI semantics;
- internal component boundaries and data flow;
- public APIs, versioned IR, schemas, or generated formats;
- parser-construction algorithms and compatibility-preserving optimizations;
- safety, isolation, resource, or transactional guarantees implemented in
  code; or
- the architecture of a shipped tool such as the formatter, language server,
  debugger, or browser playground.

Testing and evidence may explain why an implementation choice is safe, but
they must not be the decision by themselves.

The following subjects belong in their operational documents instead:

- contributor workflow, CI jobs, test matrices, dependency automation, and
  quality gates: [`docs/development.md`](../development.md);
- benchmark protocols, artifact ingestion, and comparison rules:
  [`benchmark/README.md`](../../benchmark/README.md);
- documentation organization, generation, hosting, and publication:
  the relevant documentation or workflow;
- maturity, compatibility, and deprecation policy:
  [`docs/stability.md`](../stability.md);
- release decisions and release gates:
  [`docs/release-readiness.md`](../release-readiness.md); and
- error-experience evidence and human assessments:
  [`docs/error-ux.md`](../error-ux.md).

Use [`0000-template.md`](0000-template.md) for a new implementation decision.
