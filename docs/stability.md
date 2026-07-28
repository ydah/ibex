# Stability, compatibility, and deprecation

Ibex separates support level from activation. Opt-in controls do not determine
maturity: a documented opt-in API can be Stable, Preview, or Experimental.

## Maturity ladder

| Level | Activation | Guarantee |
|---|---|---|
| Stable | Default compatible mode or a documented stable API | Semantic versioning; compatible-mode behavior remains unchanged |
| Preview | Explicit pragma, mode, command, or algorithm | Breaking changes require notice one minor release in advance |
| Experimental | Explicit policy/object or research entry point | May change without notice; budgets and failure modes are part of the experiment |

After v1.0, promotion requires representative use in a shadow or gallery
grammar, feature-specific invariant/property tests, two released versions
without a specification change, dependent-tool support where applicable, and
complete public documentation. For the initial v1.0 contract, accepted ADRs,
versioned benchmark evidence, invariant/property coverage, dependent-tool
support where applicable, and complete public documentation replace the
impossible two-prior-release requirement. Only Stable features may be adopted
by the production self-hosted grammar.

## v1 inventory

Stable:

- racc-compatible grammar input and generated `do_parse`/`yyparse` runtime;
- default direct LALR construction, parser tables, recovery callbacks,
  observation events, resource limits, migration checks, and bounded
  counterexample/ambiguity analysis;
- versioned core Grammar IR, Automaton IR, Lexer IR, table formats, report
  schemas, and their validators;
- format-v6 Red/Green batch CST parsing, typed syntax views, persistent editing
  and diffing, and the closed `ibex_cst` schema v1 serialization contract.

Preview:

- `pragma extended` / `--mode=extended`, including EBNF groups, parameterized
  and inline rules, middle actions, multiple entries, canonical imports,
  generated lexers, semantic locations/types, AST generation, grammar tests,
  and documentation tooling;
- the conservative `--algorithm=ielr` backend;
- LSP, watch, debug, coverage, browser playground, and static action-shadow
  integration.

Experimental:

- opt-in bounded insertion/deletion/replacement repair through
  `Runtime::RepairPolicy`;
- syntax-only incremental CST sessions and conservative Blender subtree reuse.

The batch CST contract is selected for the initial v1 API under the
initial-major evidence rule above. The remaining Preview features have not
completed the normal two-release field period. Repair passed its usefulness
spike but remains Experimental because two of ten baseline plans were not
useful and inserted semantic values may be nil.

## Research decisions

- IELR passed its correctness/state-bound spike and remains preview while it
  gains field experience. Direct LALR remains the default.
- Bounded repair passed SP-4 with 8/10 useful plans and remains experimental.
- GLR and `%dprec`/`%merge` did not enter the product: no delayed-action spike
  met the ≤5% deterministic-overhead and ambiguity-policy gates.
- Syntax-only incremental parsing entered as experimental after fixed-seed
  structural edits matched fresh Green trees and the representative benchmark
  measured 1.04–2.83x over Stage A and 1.66–4.48x over fresh syntax sessions.
  It remains experimental until it completes the two-release field period.

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

Parser-table formats v1 through v6 remain readable for non-CST parsers. CST
tables must use the current format v6 structured metadata; older CST tables
and the boolean `cst: true` shape fail before token consumption with a
regeneration instruction. Format v6 is the only writer and does not change
Grammar IR v2. The closed `ibex_cst` schema v1 is a versioned interchange
contract. Additive meaning requires a new schema version; readers do not
accept unknown fields.

## Deprecation policy

After v1.0, a Stable API or syntax first emits a migration warning for at least
two minor releases. The release notes and documentation must name the first
warning release, replacement, migration command or procedure, and earliest
removal release. Automated migration is supplied when practical; policy does
not promise a command that the product does not provide. Preview features
receive at least one minor release of notice, and Experimental features may
change without notice.

The pre-v1 mixed semantic/syntax CST was a Preview contract and is removed
while selecting the initial stable API. Its parser tables are rejected with a
regeneration instruction, as recorded by
[ADR 0099](decisions/0099-stabilize-current-red-green-cst.md). There are no
Stable removals scheduled.
