# ADR 0017: Render EBNF expansions with origin labels

## Context

Extended EBNF is lowered to ordinary helper nonterminals before automaton construction. Grammar IR records the expansion kind and
source location, but it previously discarded the original expression. Text, DOT, and HTML reports consequently exposed internal
names such as `$optional_1`, even though the extension contract says reports should use production origin metadata to explain the
source grammar.

## Decision

Synthetic EBNF production origins gain an additive `expression` string containing a deterministic rendering of the original AST
item. A code-generation presentation helper builds labels for synthetic LHS symbols from this metadata. Text reports, DOT edges,
and HTML states/rules use those labels; parser tables, symbol identities, counterexample search, and serialized automata continue
to use numeric ids and internal names.

Old schema-v1 IR without `origin.expression` remains valid and falls back to its stored symbol name. The existing schema version
therefore does not change.

## Consequences

- Diagnostics display the grammar syntax users wrote without coupling code generators to frontend AST classes.
- Nested groups and suffixes retain a readable recursive form.
- Presentation changes do not alter parsing, table construction, or IR identity rules.
