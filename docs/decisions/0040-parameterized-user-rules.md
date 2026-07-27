# ADR 0040: Specialize extended-mode parameterized user rules

- Status: Accepted
- Date: 2026-07-25

## Context

Repeated list, wrapper, and delimiter patterns are easier to maintain as grammar-level templates than as copied productions.
Parameterized user rules cross the self-hosted syntax, AST identity, include and documentation provenance, action locations,
normalization hygiene, recursion termination, and Grammar IR versioning. A textual macro would lose structural locations and
could capture user symbols. Expanding recursively without a memo or budget would also let an argument-growing definition exhaust
the Ruby stack or memory.

The existing extended grammar already uses `(` for EBNF groups. Parameterized calls therefore need a lexical boundary that
cannot reinterpret existing `ITEM (A | B)` input. Grammar IR version 2 has already reserved
`expansion.parameter {rule, arguments}` for specialized productions; version 1 must retain its existing shape.

## Decision

Parameterized definitions and calls are an extended-mode feature, enabled by `--mode=extended` or a root
`pragma extended`. A definition lists ordered identifier formals after its LHS:

```text
list(X): X | list(X) X
numbers: list(NUM)
```

The callee and opening parenthesis of a definition or call must be byte-adjacent. In particular, `list(NUM)` is a call while
`list (NUM)` remains the existing symbol followed by an EBNF group. Arguments are structural extended RHS expressions without
actions or precedence overrides; calls may be nested. Named references and `?`, `*`, and `+` suffixes after a call apply to the
specialized nonterminal exactly as they do to a symbol reference. Default mode rejects the opening parenthesis at its source
location. Named references inside arguments are rejected; named references on formal occurrences and on the completed call have
unambiguous scopes.

`AST::Rule` retains an ordered `parameters` array. `AST::ParameterizedReference` retains the callee, ordered argument items,
call-site named reference, and call location. Lossless documentation enrichment, canonical include resolution, recursive
freezing, and AST serialization preserve those fields without source re-parsing.

Normalization gathers template definitions separately from parameterless user rules. Repeated definitions of one template are
allowed only with identical ordered formals. Duplicate formals, mixed plain and parameterized definitions, collisions with
terminal declarations, undefined templates, and wrong arity are positioned errors. A template is not itself a grammar symbol or
standalone production, and cannot be the start symbol. A named reference on a formal occurrence, such as `X:value`, is applied
to the structurally substituted result and therefore retains the template action's stable local name. A formal precedence
override is accepted only when its argument is one plain symbol reference; other argument shapes are rejected at the override
because they cannot name one precedence-bearing terminal. Non-formal precedence overrides are retained unchanged.

Each invocation is specialized into an impossible user name of the form `$parameter_N`. The memo key is the template name plus
the deterministic structural rendering of its arguments; call-site named references and outer suffixes are deliberately not
part of the key. The memo entry and helper symbol are installed before any template body is expanded. Direct and mutual
recursion with the same specialization therefore terminate and reuse one helper. Formal references are replaced structurally
through groups, suffixes, separated lists, and nested calls. All other names remain unchanged, so generated helpers cannot
capture source-level identifiers.

New specializations are expanded by an explicit depth-first worklist. A pending frame retains its template, alternative, item,
and nested EBNF continuation together with definition include chain and expansion metadata while a child
specialization completes. Each source item is lowered before an unrelated later call is scheduled, preserving the helper and
production order of ordinary recursive lowering without tying a configured limit to the Ruby call stack.

The public normalizer defaults to at most 1,000 distinct parameter specializations, configurable through
`max_parameter_specializations:`. A new specialization that recursively re-enters an active template with arguments that
structurally enclose the active arguments is rejected as a constructor-growing cycle. Shrinking calls remain valid, and same-key
recursion still reuses its installed memo entry. This makes termination
structural instead of depending on an arbitrary depth boundary, while the total-instance limit remains defense in depth.

Specialized symbols inherit the template's semantic type, display name, and first consistent documentation. Specialized
productions retain the template alternative's action, precedence, location, documentation, and definition include chain. Every
specialized production writes Grammar IR version 2
`expansion.parameter: {rule: TEMPLATE_NAME, arguments: [CANONICAL_EXPRESSION, ...]}`. It also retains the ordinary
`expansion.include_chain`; no new schema field is introduced. Version-1 serialization continues to omit documentation and all
expansion metadata.

## Consequences

- Existing whitespace-separated symbol/group grammars keep their meaning.
- Templates compose with nested EBNF, includes, documentation, actions, precedence, named references, and semantic types while
  retaining source provenance.
- Same-argument direct and mutual recursion are finite and deterministic; argument-growing recursion fails at the structural
  cycle.
- Internal `$parameter_N` symbols are visible in normalized IR like other EBNF helpers, but cannot collide with grammar source
  identifiers.
- Template definitions do not add unused standalone productions, so automata contain only invoked specializations.
- Racc compatibility remains the default, and Grammar IR version 1 remains shape-compatible.
