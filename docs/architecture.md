# Architecture and IR schemas

Ibex keeps syntax, grammar meaning, automaton construction, and output concerns behind two versioned immutable contracts.

```text
.y Lexer/Parser ─┐
Ruby DSL ────────┴─> Grammar AST -> Normalizer -> Grammar IR
                                                    |
                                               set analysis
                                                    |
                                      SLR/LALR/LR1 Builder -> Automaton IR
                                                                    |
                              Ruby/RBS generators / report / DOT / HTML / counterexamples
```

Frontend changes stop at the Normalizer. Algorithm strategies consume Grammar IR and produce identical Automaton IR shapes.
Outputs consume Automaton IR and never call builder internals. The CLI only connects stages and supports JSON resumption.

The RBS generator emits the generated class namespace, superclass, parser-table constants, and `.parser_tables` contract. The
gem also ships `sig/ibex/runtime.rbs` for the inherited public parser API. User methods embedded as opaque Ruby source are not
inferred; applications can reopen the generated class in their own RBS files to declare them.

## Grammar IR v1

Top-level fields:

| Field | Meaning |
|---|---|
| `ibex_ir`, `schema_version` | `"grammar"`, `1` |
| `class_name`, `superclass` | Generated Ruby class contract |
| `start`, `expect`, `options` | Start name, unresolved S/R expectation, result/action flags |
| `symbols` | Interned terminals and nonterminals; `$eof` id 0 and `error` id 1 |
| `productions` | Numeric LHS/RHS ids, action, precedence override, source origin |
| `user_code`, `conversions`, `warnings` | Concatenated code, external token expressions, structured diagnostics |

Warning records use stable type names (`undeclared_terminal`, `unused_terminal`, `unreachable_nonterminal`,
`duplicate_production`, and `empty_language`) and retain source locations. The CLI applies display/error policy at the boundary;
normalization and IR serialization do not discard diagnostics.

A symbol has `id`, `name`, `kind`, `reserved`, optional `prec {associativity, level}`, and `loc`. A production has `id`, `lhs`,
`rhs`, optional `action`, optional `prec_override`, and `origin`. An action has opaque `code`, `loc`, `named_refs [{name,index}]`,
and `context_length`; middle-action helpers use the last field to view preceding stack values.

IR objects and nested collections are frozen. JSON keys have deterministic order, so dump/load/dump is byte-stable. Incompatible
schema changes require a new version.

## Automaton IR v1

Top-level fields are `ibex_ir: "automaton"`, `schema_version`, `algorithm`, `grammar_digest`, embedded `grammar`, `states`, and
`conflict_summary`. Embedding Grammar IR makes automaton JSON sufficient for code generation after `--from=automaton-ir`.

Each state contains:

- merged items `{production, dot, lookaheads}`;
- named `transitions`;
- resolved terminal `actions` and nonterminal `gotos`;
- `default_action` (currently always null to preserve immediate error cells);
- every conflict, including precedence-resolved conflicts and the resolution reason.

`conflict_summary.sr` counts unresolved default-shift conflicts for `expect`; `resolved_sr` counts retained precedence or
associativity decisions; `rr` counts reduce/reduce cells.

## Runtime table contract

Generated subclasses expose `.parser_tables` with external `tokens`, display `token_names`, ACTION and GOTO tables, and
production `{lhs,length,action}` records. Plain tables are arrays of Hash rows. Compact tables use row displacement with offsets,
values, and row-ownership checks; both expose equivalent lookups.

The runtime maintains state and value stacks, pulls a lookahead only when required, and applies tagged `shift`, `reduce`,
`accept`, and `error` actions. Recovery pops to a state that shifts token id 1, suppresses repeated reports for three successful
shifts, and honors `yyerrok`.

## Clean-room boundary

Implementation work uses public racc documentation, CLI black-box behavior, and published LR algorithms only. racc implementation
sources and generated source are not inputs to the design. Self-authored compatibility grammars execute both outputs in separate
processes and compare observable results.
