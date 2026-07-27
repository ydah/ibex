# ADR 0082: Cache stable runtime-hook eligibility

- Status: Accepted
- Date: 2026-07-27

## Context

The direct runtime still reconstructed bound Method objects for all shift,
reduce, location, and token-display hooks at the start of every parse. An
object-allocation profile of the fixed BCDice workload attributed 26
allocations per parse directly to `UnboundMethod#bind_call`, with additional
callback-owner checks around the singleton mutation tracker. Reused parsers
repeat the same answer while their class and singleton method surfaces remain
unchanged.

Caching only a Boolean would be incorrect: applications may add or remove
singleton hooks between parses, replace singleton mutation callbacks, or
define/include/prepend a hook on the parser class.

## Decision

After the first eligible session installs the per-instance mutation tracker,
the runtime records the singleton-class ancestor chain. Later sessions reuse a
class-level hook result only when:

- the instance tracker has reported no relevant singleton mutation;
- the tracker remains at the same singleton ancestor position;
- the singleton class is not frozen; and
- the parser class's hook version still matches the cached result.

A private tracker on the parser class increments that version for relevant
method addition, removal, or undefinition and for class include/prepend
operations. A cache miss uses the complete effective-method comparison. A
successful full comparison refreshes the instance snapshot; a mutated or
unusual object continues through the full compatibility path.

The tracker remains parse-lazy. A parser allocated for one parse pays the
existing validation cost and does not receive extra constructor work merely
to populate the reuse cache.

## Consequences

- Diagnostic public-workload allocation counts for parser reuse fell by about
  36 objects per parse after the cache was warm.
- Singleton hooks, class hooks, callback replacement, prepend/extend layers,
  frozen singleton classes, and dynamic hooks installed by semantic actions
  retain their existing fallback behavior.
- New-instance parsing intentionally retains full validation because no prior
  instance-local observation exists to reuse.
- Mutating a module that is already in a parser class's ancestor chain during
  an active parse remains outside the parser's threading and method-mutation
  contract, as before.
