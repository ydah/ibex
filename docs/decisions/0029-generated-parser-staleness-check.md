# 0029: Verify generated parser content without rewriting it

- Status: Accepted
- Date: 2026-07-23

## Context

Timestamp-based build tasks avoid unnecessary local generation, but they cannot prove that a committed parser was generated with
the current grammar, options, and generator. CI needs a side-effect-free byte comparison like the frontend self-host check.
The existing `--check-only` validates grammar semantics and intentionally stops before code generation.

## Decision

`ibex --check` runs the normal pipeline and compares the would-be Ruby output byte-for-byte with the configured or inferred output
path. It exits successfully only for an exact match. A missing or stale output is an error and is never rewritten.
When `--rbs` is requested, its would-be signature is checked as well. Report and visualization options are suppressed during a
check, including when their paths collide with the parser path.

`--check-only` keeps its existing meaning. The names are intentionally distinct: one checks the grammar, the other checks the
generated artifact. `--check` requires Ruby emission and cannot be combined with `--check-only`.

## Consequences

Projects can enforce reproducible committed parsers in CI without a dirty-worktree probe. The check includes every generation
option because it compares final bytes, and it remains independent of filesystem timestamp resolution.
