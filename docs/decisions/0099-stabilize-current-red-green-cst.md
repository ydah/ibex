# ADR 0099: Stabilize only the current Red/Green CST

- Status: Accepted
- Date: 2026-07-28

## Context

Parser-table format v6 introduced the pure-syntax Red/Green CST while the
runtime continued to execute the mixed semantic/syntax CST produced by
formats v1 through v5. That compatibility branch kept two tree models, two
trivia representations, two recovery paths, and a deprecation promise tied to
an `ibex lint --autocorrect` command that does not exist.

The v6 implementation now has accepted design decisions, fixed-seed fidelity
and incremental property suites, byte-stable error-path fixtures, versioned
benchmarks, generated signatures, and complete user documentation. Ibex is
still pre-1.0, so this is the point at which the initial stable contract can
be selected without preserving an earlier preview representation.

## Decision

The v1 CST contract is parser-table format v6 Red/Green syntax only.
`pragma cst` tables must use the current table format and structured `:cst`
metadata. Older CST tables and the format-v6 boolean `cst: true` shape are
rejected before token consumption with an instruction to regenerate.
`CST::Trivia`, `CST::Token`, `CST::Missing`, `CST::Error`, and `CST::Node`
are removed.

Formats v1 through v5 remain readable for parsers that do not enable CST.
This preserves the semantic parser action ABIs without retaining the obsolete
CST representation. The generator writes only format v6.

Batch Red/Green parsing, typed syntax views, persistent editing and diffing,
and the closed `ibex_cst` schema v1 are Stable for the initial v1 contract.
The usual two-released-version promotion evidence does not apply before the
first stable release; accepted ADRs, public documentation, versioned
benchmarks, and invariant/property coverage are the required initial-major
evidence instead. Once v1.0 is released, ordinary semantic-versioning and
deprecation rules apply.

Syntax-only incremental sessions and Blender subtree reuse remain
Experimental. Their maturity is independent of the stable batch tree and
serialization contracts.

## Consequences

- Applications using an older generated CST parser must regenerate it with
  the installed generator before upgrading the runtime.
- Applications cannot test for or construct the removed legacy result
  classes. They use `SyntaxNode`, `SyntaxToken`, Green values, and
  `ParseResult` instead.
- Non-CST generated parsers keep their original v1-v5 action calling
  conventions.
- There is no warning-only period or nonexistent autocorrect prerequisite for
  the pre-v1 preview CST.
- The overall v1.0 release remains subject to the independent performance and
  error-UX gates in the release-readiness report.
