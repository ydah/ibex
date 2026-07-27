# ADR 0087: Preserve default diagnostics in cold generation benchmarks

- Status: Accepted
- Date: 2026-07-27

## Context

ADRs 0082 and 0083 define cold generation as a fresh invocation of the public
CLI. That boundary includes process startup, grammar parsing, automaton
construction, diagnostics, and code generation.

Under ADR 0021, an unexpected unresolved shift/reduce conflict or any
reduce/reduce conflict in a LALR grammar can trigger an advisory IELR build.
The build determines whether IELR lowers the unexpected conflict count before
the CLI suggests `--algorithm=ielr`. Profiling the fixed-revision Nokogiri CSS
workload showed that this canonical/IELR analysis accounts for a large part of
its cold generation time.

Skipping the advisory analysis makes that workload substantially faster, but
it also removes accepted default CLI behavior. It would make a nominally
end-to-end comparison measure a private benchmark path instead of the command
users run. A generator-core profile can isolate construction stages, but it
does not include the same work as cold CLI generation.

The formal comparison also fixes Racc's native runtime as the reference
environment. Reclassifying a Ruby-backend or core-only diagnostic as a formal
result would conceal rather than close a remaining implementation boundary.

## Decision

Formal cold generation continues to execute the default CLI behavior,
including ADR 0021's unexpected-conflict analysis and advisory IELR
diagnostic. The comparison harness will not disable, stub, or bypass that work
and will not expose a benchmark-only switch for doing so.

Performance work may optimize canonical LR and IELR internals only when
generated tables, conflicts, diagnostics, output, and failure behavior remain
unchanged. Stage-level and generator-core profiles may be used to locate work,
but they are labelled diagnostic and cannot replace the cold generation
series in formal evidence.

Reports retain the native-Racc reference and publish the observed ratio and
confidence interval even when the target is not met. A residual gap is not
converted into a passing result by narrowing the measured boundary.

## Consequences

- Cold generation measures the command and diagnostics users actually receive.
- Conflict-heavy grammars can remain slower than a core-only construction
  profile even after canonical and IELR internals improve.
- Profiling data remains useful for optimization without being mistaken for
  release evidence.
- The native-Racc cold and runtime gaps remain visible, and the performance
  target can honestly remain unmet.
- Future diagnostic changes must be decided as user-visible behavior changes,
  not introduced solely to improve a benchmark.
