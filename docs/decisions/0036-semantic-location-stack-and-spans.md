# 0036: Carry semantic locations through a parallel runtime stack

- Status: Accepted
- Date: 2026-07-24

## Context

ADR 0026 added an optional lookahead location for structured syntax errors but deliberately deferred locations for semantic
actions. Supporting `@1`, `@2`, and `@$` requires more than textual substitution: shift, reduction, recovery, pull, yield, and
push paths must agree on location lifetime; empty and middle actions need deterministic spans; and Ruby instance variables,
strings, comments, regular expressions, and heredocs must remain untouched.

ADR 0035 therefore required a separate phase with a parallel location stack, reduction-span rules, generated-action syntax, and
typed action contracts before full semantic locations could ship.

## Decision

The runtime keeps a location stack exactly parallel to its semantic-value stack. Shifting an ordinary token stores the
application-owned location object unchanged. Recovery shifts the original unexpected-token location with the synthetic `error`
value, and every recovery pop removes the matching location.

Every reduction computes an immutable `Ibex::Runtime::LocationSpan`:

- A nonempty reduction covers the first through last non-`nil` RHS location. Nested spans contribute their outer start and finish
  boundaries. If the RHS has no located entry, the result location is `nil`.
- An empty reduction is a zero-width span whose start and finish are the current lookahead's start boundary. Its `end_*` readers
  equal its start coordinate even when the lookahead object carries a wider end coordinate. It is `nil` when that lookahead is
  unlocated.
- A middle action remains an empty helper reduction. Its `@$` is therefore zero-width at the following lookahead, while `@1`,
  `@2`, and so on address the left-context locations exposed to that action.

`LocationSpan#start` and `#finish` preserve the boundary objects. Its `file`, `line`, `column`, and `source_line` readers delegate
to the start; `end_file`, `end_line`, and `end_column` use explicit end fields on the finish when present and otherwise use its
point coordinate. `empty?` distinguishes an empty reduction. A later enclosing reduction flattens nested spans so it retains the
original outer boundary objects.

Inside a generated action, `@N` addresses the one-based location corresponding to `val[N - 1]`, and `@$` addresses that
reduction's span. Out-of-range `@N` references fail generation at the action's grammar location. The generator uses Ruby's
standard `Ripper` lexer to rewrite only code-level references, including interpolation expressions; ordinary instance/class
variables and occurrences in literal content, comments, regular expressions, symbols, and heredoc bodies are unchanged.

Generated reduction methods receive the RHS values, surrounding value stack, RHS locations, surrounding location stack, and
reduction span. Generated RBS declares that five-argument private contract, and generated production entries explicitly opt into
it with `location_action: true`. The runtime honors that marker only for generated `_ibex_action_N` Symbol methods; application
callables cannot be upgraded accidentally by a stray marker. Every other application method or callable continues to receive
exactly two arguments, regardless of optional or rest parameters, preserving hand-written parser tables and older generated
action methods.

This decision supersedes the semantic-location deferral in ADR 0035 and completes the phase deferred by ADR 0026. Other deferred
extensions in ADR 0035 are unchanged.

## Consequences

Pull `do_parse`, yielding `yyparse`, and caller-driven `push` use identical location semantics. AST-building actions can retain
token objects or immutable nonterminal spans without consulting parser internals. Location-less lexers remain valid and produce
`nil` semantic locations rather than fabricated coordinates. Generated action signatures grow, but the runtime's arity bridge
keeps the prior two-argument extension contract operational.
