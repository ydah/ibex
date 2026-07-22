# Architecture and IR schemas

Ibex keeps syntax, grammar meaning, automaton construction, and output concerns behind two versioned immutable contracts.

```text
.y Lexer -> Token adapter -> self-hosted LR Parser ─┐
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

The text frontend's canonical syntax is `lib/ibex/frontend/grammar.y`. Ibex generates and commits
`lib/ibex/frontend/generated_parser.rb`; the public `Frontend::Parser` always delegates to that class. Lexer `Token` objects remain
the semantic values passed through `TokenAdapter`, preserving their `Location` in AST nodes and diagnostics. The explicitly named
handwritten `BootstrapParser` is excluded from normal loading and exists only to break the regeneration cycle. See
[ADR 0015](decisions/0015-self-hosted-grammar-frontend.md) for the update procedure and boundary.

The RBS generator emits the generated class namespace, superclass, parser-table constants, and `.parser_tables` contract. The
gem also ships a one-to-one rbs-inline-generated signature tree under `sig/` for every Ruby source in `lib/`, including the
self-hosted parser. CI regenerates into an empty temporary directory, compares the complete trees, validates the RBS environment,
and runs Steep against the entire library. Token/location records, grammar AST nodes, parser classifier state, IR records, and
automaton actions use concrete domain types. Generated-parser reduction values, dynamic parser-table cells, decoded JSON values,
and user methods embedded as opaque Ruby source remain `untyped`; applications can reopen the generated class in their own RBS
files to declare embedded methods.

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
- an optional reduce `default_action`, selected only when explicit error masks preserve every terminal lookup and reduce the
  total encoded ACTION entries;
- every conflict, including precedence-resolved conflicts and the resolution reason.

`conflict_summary.sr` counts unresolved default-shift conflicts for `expect`; `resolved_sr` counts retained precedence or
associativity decisions; `rr` counts reduce/reduce cells.

## Runtime table contract

Generated subclasses expose `.parser_tables` with external `tokens`, display `token_names`, ACTION and GOTO tables, per-state
default actions, and production `{lhs,length,action}` records. Plain tables are arrays of Hash rows. Compact tables use row
displacement with offsets, values, and row-ownership checks; both expose equivalent lookups. Default reductions are restricted
to known token ids, and explicit error masks preserve the pre-optimization result of every declared terminal cell, including
the synthetic `error` terminal. The deterministic size policy is fixed by
[ADR 0014](decisions/0014-compatibility-safe-default-reductions.md).

The runtime maintains state and value stacks, pulls a lookahead only when required, and applies tagged `shift`, `reduce`,
`accept`, and `error` actions. Recovery pops to a state that shifts token id 1, suppresses repeated reports for three successful
shifts, and honors `yyerrok`. No-op `on_shift`, `on_reduce`, and `on_error_recover` extension points observe successfully
committed events without changing parser results; the recovery hook retains the pre-pop error context and is distinct from an
ordinary token shift. Their ordering and payload contract is fixed by [ADR 0013](decisions/0013-runtime-observation-hooks.md).

## Clean-room boundary

Implementation work uses public racc documentation, CLI black-box behavior, and published LR algorithms only. racc implementation
sources and generated source are not inputs to the design. Self-authored compatibility grammars execute both outputs in separate
processes and compare observable results.
