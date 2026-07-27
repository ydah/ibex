# ADR 0085: Gate a narrow runtime fast path by observability

- Status: Accepted
- Date: 2026-07-27

## Context

The generic runtime constructs token display strings, semantic-location arrays,
hook snapshots, trace payloads, and event payloads at every committed parser
operation. Those values are required when applications use debug output,
runtime events, locations, concrete syntax trees, repair, or the public shift
and reduction hooks. They are not observable in the common session that uses
none of those facilities. Actionless productions also have no semantic-action
callback through which application code can observe their temporary values.

Removing the generic work unconditionally would weaken established hook and
observer ordering, location behavior, recovery diagnostics, and the
two-, five-, and six-argument semantic-action contracts. A second generated
table format would also make performance depend on regenerating application
parsers.

## Decision

The generic runtime remains the reference implementation. At session start,
the parser enables a private fast path only when all of these conditions hold:

- debug output, runtime observers, repair, and concrete syntax trees are off;
- the parser tables do not declare location use and no location stack exists;
- the effective `on_shift`, `on_shift_location`, `on_reduce`, and
  `on_reduce_location` methods are the original `Parser` no-ops.

Comparing the complete bound method implementation, rather than only its
owner, rejects singleton methods, subclass overrides, prepended modules, and
replacement of a base hook before the session.

An eligible shift commits only the state and semantic-value stacks, resource
limit, recovery-shift count, lookahead clearing, and compatible stack aliases.
It does not materialize the token display or invoke dormant traces, events,
locations, or hooks. An eligible reduction is limited to an actionless
production with a valid nonnegative reduction length. It preserves the
generic actionless result (`values.first`) without constructing the values,
locations, or hook snapshots. Productions with any semantic action always use
the generic reduction and retain every action ABI.

Eligibility is one-way within a session. Public observer registration,
assignment through `yydebug=`, legacy JSON-lines tracer attachment, or the
first non-nil input location disables the fast path immediately. Pull lexers
and semantic actions are followed by another eligibility check so
instrumentation installed by application callbacks applies before the next
optimizable operation. Push calls perform the same check at each driver
boundary. Errors, recovery, and synthetic error-token shifts always use the
generic path; token display is materialized lazily before an error or
synchronization transaction.

Changing parser methods concurrently from another thread remains outside the
parser instance's supported threading contract. Hook changes made by a lexer,
semantic action, or between push calls are detected. This optimization changes
neither generated Ruby bytes nor the parser-table ABI.

## Consequences

- Ordinary location-free and unobserved parsers avoid dormant diagnostic,
  hook, and location allocations.
- Enabling a supported observation facility during a session preserves its
  documented next-operation boundary and never re-enters the fast path until a
  new session.
- Hooked, debugged, observed, repaired, location-aware, CST, error, and
  recovery behavior continues through the generic reference path.
- Action-bearing productions retain a small eligibility check after user code;
  actionless reductions receive the larger allocation reduction.
- New public runtime observation mechanisms must explicitly invalidate or
  disqualify this fast path.
