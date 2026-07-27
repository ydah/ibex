# ADR 0056: Lazy semantic locations and additive runtime observation

- Status: Accepted
- Date: 2026-07-26

## Context

Location-aware lexers already pass a third token element and generated actions already support `@N` and `@$`. The public API
still lacks a concrete immutable range, named and programmatic action access, discard observation, and location-aware hook
payloads. Maintaining a parallel location array for every parse would impose cost on the common two-element token contract.
Middle actions also lower to synthetic empty productions, which can hide the source responsible for a parser conflict.

## Decision

`Ibex::Location` is the built-in immutable one-based range. Optional byte offsets are zero-based and half-open. Joining ranges
requires one file and retains byte boundaries only when both operands provide them.

Generated tables carry a `uses_locations` capability bit and action records carry middle-action context length and named
location indexes only when needed. The runtime starts without a location stack, allocates it eagerly only for a
location-sensitive generated parser or runtime tooling observer, and otherwise backfills it once if a three-element token
appears. `loc(position_or_name)` and `result_loc` expose the active action context.

The original `on_shift`, `on_reduce`, and `on_error_recover` signatures remain unchanged. Additive location-aware companions run
after each original hook, and `on_discard` reports input removed by yacc recovery. Human `yydebug` traces continue to omit values
unless the application supplies `trace_value_printer`; formatter failures are contained and identified without inspecting the
value as a fallback.

Conflicts involving a middle-action helper carry one or more `midrule_origins` locations in Automaton IR. Text, HTML, and
version-1 explain output surface that optional additive field.

## Consequences

- Existing two-element lexers and hook overrides remain source-compatible.
- Ordinary unobserved parsers pay no location-array allocation.
- Three-element tokens, pull/yield/push drivers, recovery, composed inline actions, and named locations share one stack
  alignment contract.
- Applications can use the supplied range type without being required to replace existing hash or object locations.
- Synthetic middle-action conflicts point back to actionable grammar coordinates.
