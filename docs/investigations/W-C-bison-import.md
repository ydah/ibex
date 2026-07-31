# Investigation: Bison grammar analysis import

## Existing facilities

- The canonical frontend accepts yacc-shaped productions but its declaration
  vocabulary and action language are Ruby-specific.
- Grammar AST and IR retain semantic actions as opaque source until Ruby code
  generation. Analysis, independent verification, simulation, equivalence,
  metrics, and conflict explanation do not execute those actions.
- `RaccMigration::Checker` already demonstrates the clean-room rule: inspect
  public grammar text and observable behavior, never another generator's
  implementation or generated source.
- CLI report schemas are closed and versioned. Atomic output helpers and
  alias checks already exist.

## Boundary and contracts

The importer is a one-way analysis adapter. It recognizes declaration and rule
structure, emits ordinary extended Ibex source, and places each transformed C
action in an opaque hexadecimal sentinel. Analysis can consume that source, but
Ruby generation must reject the sentinel before producing code.

The adapter does not change Grammar IR, Automaton IR, parser tables, the
frontend grammar, or the runtime. It uses explicit byte, token, rule, and
action budgets. Unsupported directives are retained as positioned report
entries; none is silently discarded.

## Directive classification

| Classification | Directives | Treatment |
|---|---|---|
| converted | `%token`, `%left`, `%right`, `%nonassoc`, `%precedence`, `%start`, `%expect`, `%expect-rr`, `%empty`, `%prec` | emitted as existing extended Ibex declarations or rule syntax |
| recognized metadata | `%nterm`, `%type`, `%union`, `%destructor`, `%printer`, `%param`, `%parse-param`, `%lex-param`, `%define`, `%code` | retained in the versioned report, not invented as new Ibex syntax |
| unsupported | GLR, language/skeleton/output controls, push/pull/API controls, `%dprec`, `%merge`, and every unknown directive | one positioned entry per occurrence |

This compatibility table is a tool input contract, not a new core
architecture decision. The durable opaque-code and nonexecuting-analysis
boundaries are already recorded by the existing design decisions, so no new
design-decision file is added.

## Alternatives

| Option | Benefit | Cost | Decision |
|---|---|---|---|
| add Bison syntax to the canonical frontend | direct parsing | violates the v1 grammar freeze | reject |
| add an action-language field to Grammar IR | explicit | violates the closed core IR freeze | reject |
| discard C actions | easy analysis | loses source and can be mistaken for executable equivalence | reject |
| encode opaque actions and reject Ruby generation | no schema change; analysis remains useful | imported source is an analysis artifact | use |
| invoke Bison as the parser | high compatibility | runtime tool/network dependency and correlated behavior | reject |

## Unknowns resolved by tests

- Nested braces, strings, comments, and middle actions are scanned
  iteratively and covered by adversarial fixtures.
- Known and unknown directives are enumerated from a synthetic all-directive
  input.
- Five pinned public grammar files are downloaded only in the external CI
  gate; none is packaged.
- Large public grammars may contain project-specific preprocessing. Import
  success means the adapter produces a complete positioned report and
  analysis source. A build-count difference is acceptable only when the report
  explains which unsupported constructs caused it.

## External and flagship results

The pinned GNU Bison corpus is GNU Bison calc, jq, PHP, PostgreSQL, and the
Bison-era CRuby `parse.y`. Every file imports, reparses as extended Ibex,
normalizes, and builds an LALR automaton. The scheduled gate checks exact
SHA-256 bytes and aggregate rule/action/production/state/conflict counts.

CRuby's Bison-era grammar recovers 781 non-augmented productions in both
tools. GNU Bison 3.8.2 has 1,304 states and Ibex has 1,303 because Bison shifts
end-of-input to a separate accept state while Ibex accepts on the completed
start item. Both have zero unresolved conflicts.

Current CRuby `parse.y` is an Lrama input with grammar-macro `%rule`
definitions before the first `%%`. The importer reports those and hook
directives at their original positions. Its 1,152-state automaton is therefore
an explicitly incomplete approximation. A state-413 `explain` query returns a
bounded nonunifying witness, but `fix` refuses to propose a repair across the
unexpanded structural macros. Treating those 27 approximate S/R conflicts as
CRuby table conflicts would be a false claim.
