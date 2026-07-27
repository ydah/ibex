# ADR 0088: Reuse parser session scratch arrays

- Status: Accepted
- Date: 2026-07-27

## Context

Every pull parse replaced the state stack, value stack, and CST-error scratch
Array before reading input. Reused public parsers therefore allocated three
framework objects per parse even when no CST errors occurred. The runtime
already owns these arrays and clears all logical session state at the parse
boundary.

ADR 0072 exposes the value stack through historical instance-variable aliases
as a read-compatibility surface. It explicitly leaves mutation, replacement,
and retention across sessions unsupported.

## Decision

Pull-session preparation clears the existing state, value, and CST-error
arrays. It pushes the selected initial state into the cleared state stack and
keeps the existing value-stack aliases attached to the same object.

## Consequences

- Reused and newly initialized parsers avoid three session-scaffolding
  allocations per pull parse.
- Live-stack identity is stable across supported parser sessions.
- Applications still must not retain or mutate the compatibility stack aliases
  across sessions, as established by ADR 0072.
- Push reset keeps its existing replacement behavior because it is an explicit
  caller-visible session discard boundary.
