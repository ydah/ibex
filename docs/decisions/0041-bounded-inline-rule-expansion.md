# ADR 0041: Expand inline rules with resumable semantic-action plans

- Status: Accepted
- Date: 2026-07-25

## Context

Small grammar rules often exist only to name a reusable phrase. Keeping such a rule as an LR nonterminal can add states or
introduce a conflict that disappears when the phrase is written directly at each use. Textual substitution is not sufficient:
one inline rule may have several alternatives, nested or parameterized calls multiply those alternatives, and every eliminated
reduction still has observable Ruby action, named-reference, semantic-location, precedence, documentation, and provenance
behavior.

Unbounded substitution can grow exponentially or loop through direct, mutual, or indirect recursion. Compiling composed Ruby
source into one opaque string would also lose the individual action locations needed for useful backtraces and would make
Grammar/Automaton IR reload unable to resume code generation.

## Decision

`%inline` is an extended-mode marker immediately preceding a rule definition:

```text
%inline atom: NUM { result = val[0] }
expression: atom
```

The lexer recognizes only the exact `%inline` directive followed by trivia. A percent sign inside a Ruby action, quoted token,
or user-code block remains ordinary source text. Root grammars and fragments retain `AST::Rule#inline`; its backward-compatible
default is `false`.

All definitions of one rule name must agree on both inline marking and ordered parameter formals. Inline names cannot collide
with terminals, cannot be selected as the start symbol, and are never emitted as final Grammar IR symbols or productions.
Cycles whose strongly connected path contains an inline rule are rejected before expansion, including paths through ordinary
rules, nested EBNF, and parameterized templates. This intentionally rejects recursive substitution even when an individual
same-key parameter specialization would otherwise be memoizable.

Normalization may temporarily lower inline definitions and invoked parameter specializations into internal nonterminals.
Before diagnostics or LR construction, a deterministic post-pass substitutes each marked nonterminal alternative into every
use, from left to right, and removes the marked symbols. Nested and repeated occurrences form a source-ordered cartesian
product. Formal liveness is propagated to a fixed point before parameter actuals contribute cycle edges, so an unused actual
cannot fabricate a cycle while a transitively used actual cannot hide one. Cycle validation and alternative expansion use
explicit heap worklists rather than the Ruby call stack. A public positive-Integer `max_inline_expansions:` option bounds the
number of materialized cartesian productions; its default is 10,000. The call-site production location identifies a budget
failure.

The caller's explicit precedence override wins. Otherwise, an inline alternative's override is retained when that expansion is
the rightmost precedence-contributing phrase; a later flattened terminal or inline phrase restores its own natural or explicit
precedence. Without an override, the LR builder continues to use the resulting flattened production's rightmost terminal.

An eliminated reduction is represented by Grammar IR v2 `Action#composition` with strategy `sequence`. Ordered fragments retain
nullable source provenance, while their corresponding plan steps retain inline `rule` names. An optional strict `plan` contains
version 1, the physical RHS width, and
post-order steps. Each step records its logical input slots, action code or an implicit default, action location, named
references, result-variable mode, context length, surrounding-stack input slots, and the physical boundary used as an
empty-reduction lookahead. [ADR 0042](0042-static-action-shadow-source.md) makes new output include a nullable `result_type` on
each step while accepting older v2 input where it is absent. Slot numbers first address flattened RHS values and then earlier
step results. The last step is the caller result.
This representation is fully serialized and validated, so code generation after Grammar or Automaton IR reload has the same
semantics and static fragment types.

Generated Ruby keeps non-composed action methods byte-for-byte on the existing path. A composed production receives its
flattened values and locations, evaluates private source-mapped fragment methods in logical reduction order, reconstructs one
logical value and `LocationSpan` per eliminated reduction, then runs the caller fragment. Empty inline spans use the next
physical location, or the runtime lookahead at the end of the production. Direct and source-mapped output share the same plan.
Generated RBS describes the flattened production tuple. ADR 0042 additionally describes private fragment helpers so extracted
action bodies can be checked without exposing them as public API. Parser table
format v3 marks composed actions explicitly and supplies the runtime lookahead as their sixth argument; v1 and v2 call shapes
remain unchanged. After every logical fragment, `yyaccept` or `yyerror` short-circuits the remaining fragments and caller.
`yyerrok` does not cancel a semantic `yyerror` raised in that fragment.

Fragment action code remains mapped to its own grammar file and line. Byte-exact ranges are not claimed because the current AST
retains locations rather than full action byte spans. Composed fragments therefore publish file/root provenance with a nullable
byte span. Mid-rule helper actions that remain real zero-width productions retain their original execution point; composed
final reductions execute when the flattened caller reduces.

Every affected production records Grammar IR v2 `expansion.inline: {rule: NAME}` while preserving caller parameter and include
metadata. Fragment provenance carries nested inline definitions that cannot fit in the single production expansion record.
Grammar IR v1 omits expansion and composition metadata as before.

## Consequences

- Inline rules can reduce LR states or conflicts without losing their semantic values and ordinary final actions.
- Multiple and nested alternatives are deterministic but can grow exponentially, so grammars have an explicit configurable
  budget and positioned failure.
- Reloaded v2 IR remains executable because composition is data, not a generator-only closure.
- Source-mapped failures identify the individual action's file and line, while byte-exact composed ranges remain deliberately
  unspecified.
- Recursive paths involving inline rules are invalid even where retaining a nonterminal would have made the grammar finite.
- Version-1 output remains structurally compatible and intentionally cannot preserve inline composition provenance.
