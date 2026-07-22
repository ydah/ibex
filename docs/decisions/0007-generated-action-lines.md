# 0007: Generated semantic actions and source lines

- Status: Accepted
- Date: 2026-07-22

## Context

Generated action failures should point to the grammar source by default, while `-l` must expose generated-file lines. Inline
actions also need a view of preceding values that are not RHS values of their synthetic empty production.

## Decision

Generate one method per semantic action. With line conversion enabled, evaluate the opaque action string using that method's
binding and Ruby's `eval(code, binding, file, line)` location parameters. With `-l`, write the action directly into the method.
For inline actions, initialize `val` from the value-stack suffix described by Grammar IR `context_length`.

## Consequences

Default backtraces name the `.y` file accurately without padding generated files. Direct mode is easier to inspect and supports
generated-file debugging. Action calls have a small Pure Ruby cost, which `omit_action_call` avoids for implicit actions.
