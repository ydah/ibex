# Implementation architecture decisions

This directory records only durable implementation choices whose rationale
cannot be recovered safely from code or reference documentation alone.

An ADR belongs here only when every answer below is yes:

1. Were at least two credible implementation approaches available?
2. Does the choice cross a component, execution, persistence, packaging, or
   security boundary?
3. Would reversing it require coordinated changes or invalidate stored or
   generated artifacts?
4. Does a future maintainer need the rejected alternatives and trade-offs to
   avoid repeating the decision?

Delete or merge an ADR when the answer stops being yes. Renumber the remaining
files; this directory is a current architecture index, not an append-only
project diary.

The following are not ADRs:

- feature and command specifications;
- descriptions of code that has already been implemented;
- compatibility fixes and migration edge cases;
- individual performance optimizations or rejected experiments;
- test plans, benchmarks, acceptance evidence, and release gates;
- maturity or stability declarations; and
- decisions superseded by the current implementation.

Those facts belong in reference documentation, tests, benchmark artifacts, or
version control. Evidence may support an ADR, but it is not the decision.

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

## Current decisions

- [0001: Separate pipeline stages with versioned IR](0001-versioned-ir-pipeline.md)
- [0002: Keep grammar-embedded Ruby opaque until code generation](0002-opaque-user-code-boundary.md)
- [0003: Self-host the grammar parser behind an explicit bootstrap](0003-self-hosted-grammar-frontend.md)
- [0004: Derive semantic and lossless source views from one lexing pass](0004-shared-semantic-and-lossless-source-model.md)
- [0005: Resolve grammar composition in a contained filesystem boundary](0005-contained-grammar-composition.md)
- [0006: Lower grammar extensions structurally and under explicit bounds](0006-bounded-structural-grammar-lowering.md)
- [0007: Share one downstream pipeline across parser algorithms](0007-shared-parser-construction-pipeline.md)
- [0008: Separate the runtime behind a versioned parser-table ABI](0008-versioned-runtime-package-boundary.md)
- [0009: Isolate mutable parser sessions from immutable parser data](0009-isolated-parser-sessions.md)
- [0010: Observe only committed runtime transitions](0010-committed-runtime-observation.md)
- [0011: Compile opaque actions once behind a versioned calling boundary](0011-versioned-semantic-action-boundary.md)
- [0012: Keep parser analysis bounded and free of semantic execution](0012-bounded-nonexecuting-analysis.md)
- [0013: Publish generated artifacts as a verified transaction](0013-transactional-generation-publication.md)
- [0014: Model generated lexers as an independently versioned stage](0014-versioned-generated-lexer.md)
- [0015: Isolate browser analysis in a replaceable worker](0015-worker-isolated-browser-analysis.md)
- [0016: Represent concrete syntax with immutable Green data and lazy Red views](0016-red-green-concrete-syntax.md)
- [0017: Persist and edit syntax through Green structure](0017-persistent-syntax-artifacts.md)
- [0018: Reuse incremental syntax only with conservative proofs](0018-conservative-incremental-syntax-reuse.md)
- [0019: Keep generated-language syntax sessions in the runtime](0019-runtime-syntax-session-boundary.md)
- [0020: Persist parser contracts in Grammar IR](0020-grammar-ir-parser-contract.md)
