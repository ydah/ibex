# Stability, compatibility, and deprecation

Ibex separates support level from availability. An opt-in feature can be
complete and well tested without being part of the stable compatibility
contract.

## Maturity ladder

| Level | Activation | Guarantee |
|---|---|---|
| Stable | Default compatible mode or a documented stable API | Semantic versioning; compatible-mode behavior remains unchanged |
| Preview | Explicit pragma, mode, command, or algorithm | Breaking changes require notice one minor release in advance |
| Experimental | Explicit policy/object or research entry point | May change without notice; budgets and failure modes are part of the experiment |

Promotion requires representative use in a shadow or gallery grammar,
feature-specific invariant/property tests, two released versions without a
specification change, dependent-tool support where applicable, and complete
public documentation. Only stable features may be adopted by the production
self-hosted grammar.

## v1 inventory

Stable:

- racc-compatible grammar input and generated `do_parse`/`yyparse` runtime;
- default direct LALR construction, parser tables, recovery callbacks,
  observation events, resource limits, migration checks, and bounded
  counterexample/ambiguity analysis;
- versioned core Grammar IR, Automaton IR, Lexer IR, table formats, report
  schemas, and their validators.

Preview:

- `pragma extended` / `--mode=extended`, including EBNF groups, parameterized
  and inline rules, middle actions, multiple entries, canonical imports,
  generated lexers, semantic locations/types, AST/CST generation, grammar
  tests, and documentation tooling;
- the conservative `--algorithm=ielr` backend;
- LSP, watch, debug, coverage, browser playground, and static action-shadow
  integration.

Experimental:

- opt-in bounded insertion/deletion/replacement repair through
  `Runtime::RepairPolicy`.

No preview feature is promoted in this freeze: all are missing the required
two-release field period. Repair passed its usefulness spike but remains
experimental because two of ten baseline plans were not useful and inserted
semantic values may be nil.

## Research decisions

- IELR passed its correctness/state-bound spike and remains preview while it
  gains field experience. Direct LALR remains the default.
- Bounded repair passed SP-4 with 8/10 useful plans and remains experimental.
- GLR and `%dprec`/`%merge` did not enter the product: no delayed-action spike
  met the ≤5% deterministic-overhead and ambiguity-policy gates.
- Incremental parsing did not enter the product: no CST edit prototype met the
  tree-equivalence and measured-latency gates.

The supported alternatives are canonical LR(1) or IELR for LALR inadequacy,
bounded ambiguity/counterexample analysis for ambiguous grammars, and
`--watch` with full deterministic reparsing for editing workflows.

## Core IR freeze

The required fields, meanings, identity rules, ordering, and validation
semantics of the published core Grammar IR and Automaton IR versions are
frozen. Existing version-1 and version-2 documents retain byte-stable
round-trips and one-generation read compatibility.

Additive optional core fields require a minor release. Meaning changes,
required-field changes, or removals require a new major schema version and
continued reading of the immediately preceding major version.

The `x-` namespace is reserved for future experimental data and is not frozen.
Current closed schemas intentionally reject unknown fields and do not emit
`x-` data. Introducing an experimental envelope therefore requires a new
additive schema version; it cannot silently place fields into an existing
closed document. Promotion moves reviewed data into a documented core field in
a later schema version.

## Compatibility policy

Compatible mode is the permanent default. Opt-in extensions, exact lookahead
defaults, repair, and research algorithms do not silently replace compatible
behavior. Public migration evidence uses public commands and black-box
behavior; implementation and generated-source layouts are not compatibility
surfaces.

An undeclared invalid token intentionally calls `on_error` before ordinary yacc
recovery. This is the documented recommended behavior and is not changed by
the freeze.

## Deprecation policy

A removable API or syntax first emits a migration warning for at least two
minor releases. Removal is allowed only when `ibex lint --autocorrect` can
perform the documented migration. Preview features receive at least one minor
release of notice; experimental features may change without notice.

The release notes and documentation must name the first warning release,
replacement, autocorrect command, and earliest removal release. There are no
stable removals scheduled at this freeze.

