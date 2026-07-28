# ADR 0011: Compile opaque actions once behind a versioned calling boundary

- Status: Accepted
- Date: 2026-07-28

## Context

Generated semantic actions need grammar-source backtraces, access to reduction
values and locations, and efficient calls from the runtime. Re-evaluating
source on every reduction is expensive, while changing generated method
arguments can silently break older tables or application callables.

## Decision

The generator builds each opaque action method once and compiles it when the
generated class loads, preserving the grammar filename and line. Direct
generated-file mode emits the equivalent method body for inspection. Static
action-shadow output uses the same method-source builder and is never executed
by Ibex.

Generated action call shapes are explicit production metadata covered by the
parser-table format version. The runtime validates markers before input and
grants generated-only ABIs only to generated action methods. Handwritten
methods and callables keep their documented application ABI.

Action dependency analysis is conservative. It may select a narrower values or
positional ABI only when lexical evidence proves omitted stacks, locations, or
containers are unused; unsupported or unparsable source uses the general ABI.
Location references are rewritten only at Ruby code tokens, not inside literal
or comment content.

## Consequences

- Actions compile once while retaining useful source-mapped failures.
- Generated ABI optimization cannot silently change application callables.
- Conservative fallback can miss an optimization but cannot omit an input the
  action may observe.
