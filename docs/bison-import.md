# Bison grammar import for analysis

`ibex import bison` converts Bison-shaped grammar structure into ordinary
extended Ibex source for analysis. It is a one-way adapter, not a parser
generator compatibility mode. Imported C actions remain opaque, are never
executed by analysis, and make Ruby generation fail before code is emitted.

```sh
ibex import bison parser.y -o parser.analysis.y
ibex import bison --format=json parser.y > import-report.json
ibex explain --state=STATE parser.y
ibex metrics parser.y
```

`explain`, `metrics`, `diff`, and the other read-only grammar analysis paths
recognize a file with two Bison `%%` section markers and import it in memory.
Source-repair commands need a canonical imported file because edits against
the generated analysis source do not map byte-for-byte onto the Bison input.

## Conversion contract

| Classification | Directives | Treatment |
|---|---|---|
| converted | `%token`, `%left`, `%right`, `%nonassoc`, `%precedence`, `%start`, `%expect`, `%expect-rr`, `%empty`, `%prec` | existing extended declarations or production syntax |
| recognized metadata | `%nterm`, `%type`, `%union`, `%destructor`, `%printer`, `%param`, `%parse-param`, `%lex-param`, `%define`, `%code` | positioned report entries; no new Ibex syntax is invented |
| unsupported | `%dprec`, `%merge`, GLR controls, generator/output controls, and every unknown directive | every occurrence is reported with its original line and column |

`$$`, `$1`, `$<type>1`, and `@$` become `result`, `val[0]`, `val[0]`, and
`result_loc` inside an opaque hexadecimal action sentinel. Ordinary `@1`
locations remain `@1`. Balanced action scanning handles nested braces,
strings, character literals, and C comments iteratively.

Bison permits uppercase nonterminals, lowercase terminals, names that collide
after punctuation removal, and names that are Ibex declaration words. The
adapter deterministically namespaces nonterminals as `bison_nt_*`, maps
lowercase terminals into `BISON_T_*`, and adds stable numeric suffixes to
sanitization collisions. Named LHS forms such as `expression[result]:` are
recognized.

The source and JSON report distinguish general unsupported directives from
structural gaps. Output/language controls and opaque initialization hooks do
not make the recovered production graph incomplete. Unknown directives,
`%dprec`, `%merge`, GLR semantics, and grammar-macro directives do. A generated
header therefore contains exactly one of:

```text
# ibex-bison-structural-status: complete
# ibex-bison-structural-status: incomplete
```

`ibex fix` refuses a structurally incomplete import. This prevents a repair
from being called safe when the bounded comparison only covered an
approximation of the source grammar.

## Limits and failure behavior

The defaults are 20 MiB of input, 1,000,000 structural tokens, 50,000 rule
groups, and 100,000 actions. Override them with `--max-bytes`,
`--max-tokens`, `--max-rules`, and `--max-actions`; every value must be
positive. Exhaustion produces a version-1 JSON envelope and exits 2.
Successful import exits 0 even when unsupported directives are present,
because the report—not silence—is the result. Invocation and malformed-input
errors go to stderr and exit 1.

`-o` writes atomically, rejects an input/output alias, and refuses symlink
targets or files with multiple hard links. Third-party grammar files are not
packaged or committed.

## External evidence and the `parse.y` boundary

The scheduled external gate downloads five checksum-pinned GNU Bison grammars
listed in [`gallery/EXTERNAL.md`](../gallery/EXTERNAL.md). It validates the
import report, parses the generated source, normalizes it, and builds an Ibex
LALR automaton. Current aggregate evidence is:

| Grammar | Rule groups | Actions | Productions | Ibex states | Unresolved S/R |
|---|---:|---:|---:|---:|---:|
| GNU Bison calc | 5 | 7 | 13 | 22 | 0 |
| jq | 29 | 167 | 167 | 311 | 408 |
| PHP | 177 | 552 | 635 | 1,203 | 0 |
| PostgreSQL | 795 | 2,436 | 3,640 | 6,942 | 0 |
| CRuby Bison-era `parse.y` | 223 | 594 | 781 | 1,303 | 0 |

For the pinned Bison-era CRuby grammar, GNU Bison 3.8.2 and Ibex both recover
781 non-augmented productions and zero unresolved conflicts. Bison reports
1,304 states while Ibex reports 1,303. The one-state difference is explained
by the acceptance convention: Bison shifts end-of-input into a separate
accept state, while Ibex accepts from the completed augmented start item.

Current CRuby `parse.y` is an Lrama input, not raw GNU Bison input. The pinned
current file imports 231 rule groups and 486 actions, but reports 22
structurally unsupported occurrences, including `%rule` grammar macros. The
approximate automaton has 1,152 states and 27 unresolved S/R conflicts.
Selecting state 413 keeps `explain` bounded and yields one nonunifying
reachability witness for the `'rescue' modifier` shift/reduce choice within 8
tokens and 10,000 configurations. That is useful diagnostic evidence about
the recovered approximation, not a claim about CRuby's actual Lrama table.
`fix` refuses this input because proposing a language-preserving repair across
unexpanded `%rule` definitions would be unsound.

The external gate reads public grammar text and GNU Bison's black-box report
only. It does not inspect Bison implementation source or generated C, and
publishes only aggregate counts.
