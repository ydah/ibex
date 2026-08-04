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

## Execution trust is independent of maturity

Stable, Preview, and Experimental describe compatibility and promotion, not
sandbox strength. Static grammar and IR tools do not execute parser actions,
generated lexer actions, or `header` / `inner` / `footer` sections. Generated
semantic parses execute parser and lexer actions, while generated syntax-only
parses suppress parser production actions but still execute lexer actions.
Both generated runtime paths may load user sections and are trusted application
code, not sandboxes.

A future nonexecuting syntax profile is a separate product contract. It must
require a declarative built-in-only lexer and reject all user-code sections;
neither the Stable batch CST API nor the Experimental incremental API currently
makes that guarantee. See the [execution trust matrix](../README.md#execution-trust-matrix).

## Feature development budget

Feature development is not frozen. A `HOLD` release decision blocks publication
of that release candidate, not investigation or feature development. The
following limits keep new work reviewable:

- at most three active new Preview development tracks;
- at most one of those tracks may introduce grammar syntax; and
- at most five Experimental product features.

A development track starts when its first user-visible change is merged and
ends when the feature becomes Stable or Experimental, or is removed. An
investigation, an ADR, and an unmerged spike do not consume the budget. An
existing Preview feature consumes a track only while its specification is being
changed; promotion work that preserves its specification does not.

There are currently no active new Preview development tracks. A pull request
that starts or ends one must update this statement and the inventory below.
These limits do not relax the versioned core IR contracts described under
[Core IR freeze](#core-ir-freeze).

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

The v1 review evaluated every Preview feature. All eighteen remain Preview;
none was silently promoted, downgraded, deleted, or left without a decision.
These are product-maturity judgments, so they live in this inventory rather
than being added to the design-decision log.

| Feature | v1 judgment | Evidence and reason | Re-evaluate when |
|---|---|---|---|
| EBNF groups | Keep Preview | lowering/property coverage is strong; normal field period is incomplete | two released versions without a syntax change |
| parameterized rules | Keep Preview | bounded specialization and shadow use exist; field period is incomplete | two unchanged releases plus another gallery use |
| inline rules | Keep Preview | bounded expansion and action-order tests exist; field period is incomplete | two unchanged releases plus catalog-impact evidence |
| middle actions | Keep Preview | opaque lowering and source mapping are tested; field period is incomplete | two unchanged releases with production use |
| multiple entries | Keep Preview | shared/isolated matrix coverage exists; external use is still narrow | two unchanged releases with multi-entry field use |
| canonical imports | Keep Preview | containment, cycles, aliases, and transactional snapshots are tested | two unchanged releases with a multi-file public grammar |
| generated lexers | Keep Preview | versioned Lexer IR and adversarial regex diagnostics exist | two unchanged releases with more stateful-lexer field use |
| semantic locations/types | Keep Preview | runtime and generated-RBS contracts are tested; declarations may still evolve | two unchanged releases without signature changes |
| AST generation | Keep Preview | Data/Visitor/Listener/RBS coverage exists; field period is incomplete | two unchanged releases with two public users |
| grammar tests | Keep Preview | subprocess isolation and coverage thresholds are tested | two unchanged releases with gallery adoption |
| documentation tooling | Keep Preview | deterministic Markdown/HTML/railroad output is tested | two unchanged releases and accessibility review |
| IELR | Keep Preview | correctness/state-bound spike and independent verification pass | two unchanged releases with LALR-inadequacy users |
| LSP | Keep Preview | protocol/overlay/rename tests exist; editor field coverage is narrow | two unchanged releases and two editor integrations |
| watch | Keep Preview | transactional publication and cancellation are tested | two unchanged releases with long-running field use |
| debug | Keep Preview | table simulation is nonexecuting and schema-tested | two unchanged releases with public debugging reports |
| coverage | Keep Preview | collection/merge/check contracts are deterministic | two unchanged releases with CI adoption |
| browser playground | Keep Preview | worker isolation and site CI pass; browser support remains narrow | two unchanged releases and accessibility review |
| action-shadow | Keep Preview | static-only source generation is isolated and tested | two unchanged releases with type-checker field use |

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

- The Stage A matrix, golden, reproducibility, schema, adversarial, gallery,
  fuzzing, dependency, and network gates now make feature-off and
  algorithm-crossing regressions reviewable before promotion.
- Independent verification detects all twenty committed structural table
  faults across every gallery/algorithm/table combination.
- Bounded grammar comparison distinguishes concrete shortest differences from
  completed searches with no difference and never labels the latter a proof.
- Conflict repair passed its first fixed twenty-case capability measurement at
  20/20. The corpus is intentionally described as a regression baseline, not
  a general repair-rate claim.
- The analysis-only Bison adapter imports and builds five checksum-pinned
  external grammars. Bison-era CRuby production counts match, its one-state
  acceptance-convention delta is explained, and current Lrama-only `%rule`
  structure is reported as incomplete instead of receiving unsafe repairs.
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

<!-- stable:compatibility-policy:v1 -->

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
regeneration instruction. There are no Stable removals scheduled.
