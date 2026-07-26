# Grammar reference

Ibex's default `racc` mode accepts the compatible grammar described here. `--mode=extended` or an explicit grammar-file
`pragma extended` adds the marked syntax; extensions are never inferred from a production.

## File structure

```text
class Namespace::Parser < OptionalSuperclass
  pragma extended       # optional; must precede ordinary declarations
  declarations
rule
  productions
end
---- header
Ruby copied before the parser class
---- inner
Ruby copied inside the parser class
---- footer
Ruby copied after the parser class
```

The superclass defaults to `Ibex::Runtime::Parser`. Repeated user-code blocks retain their source order and are concatenated.
Grammar comments use `#` through end of line or `/* ... */`.

Extended roots may include explicit fragment files:

```text
fragment
  token SHARED
  include "nested/expressions.y"
rule
  shared_rule: SHARED
end
```

Fragments own no class, superclass, pragma, options, expected-conflict count, start symbol, or user-code blocks. Their `rule`
section may be empty. Token, precedence, conversion, display, and type declarations are merged with their original locations.
`include "relative/path.y"` appears in the declaration section of a root or fragment and requires extended mode. Paths are
resolved relative to the including file, must be double-quoted and relative, cannot contain parent traversal, globs, or NUL, and
must resolve through symlinks to a regular file below the root grammar's canonical directory.

Resolution is deterministic depth-first order at include sites. A canonical file reached twice through a diamond is merged only
at its first occurrence; a cycle reports its exact canonical path loop. `Frontend::Resolver.new(path, mode: :extended).resolve`
returns the merged root and canonical dependency closure. `Parser#parse_fragment` parses fragment text without I/O, while normal
`Parser#parse` continues to return only a root and rejects fragment input. The exposed resolution is recursively immutable,
including AST strings and locations and defensively copied include provenance. Canonical directory ancestry, rather than a
string-prefix comparison, enforces the source-root boundary and remains valid when the source root is a filesystem or drive root.

Immediately preceding `##` line comments attach documentation to a rule:

```text
  ## First line
  ##  one extra leading space is retained
  value: TOKEN
```

Indentation before the comment is ignored. Ibex removes `##` and one optional space, so the example stores
`"First line\n one extra leading space is retained"`. The lines must be consecutive and directly above the LHS. Blank lines,
ordinary `#` comments, block comments, grammar tokens, and opaque actions or heredocs break attachment. The association uses
lossless segment spans rather than rescanning raw text. Documentation works in roots and fragments and is nullable on
`AST::Rule`.

For repeated definitions, every normalized user production keeps its definition's documentation. The nonterminal symbol uses
the first nonnil text; a different later nonnil text is a positioned error, while the same text is accepted. Grammar IR v2
serializes `doc` on symbols and productions. Version 1 omits those fields.

`ibex doc [--format=markdown|html|railroad] [-o FILE] [--mode=MODE] grammar.y` renders the canonical resolved grammar. Output
defaults to Markdown on stdout. HTML is accessible and self-contained, railroad output includes visible wrapped descriptions,
and all formats escape grammar-controlled text. `-o` writes atomically and cannot alias the input grammar.

The programmatic frontend can preserve this file exactly with
`Ibex::Frontend::Parser.new(source, file: path).parse_document`. The returned source document contains the same semantic AST as
`parse` plus immutable token, whitespace, line-break, comment, action, user-code marker/body, and EOF segments. `render` reproduces the input
bytes; spans and `slice` use zero-based half-open byte offsets. Line and column positions remain one-based and count Unicode
scalar values. Input is interpreted as UTF-8 without transcoding and invalid byte sequences are rejected before lexing.
`parse_source_document` accepts either a root or, in extended mode, an explicit fragment.

`ibex fmt [--mode=racc|extended] grammar.y` formats to stdout. `fmt --check FILE...` reports all invalid or noncanonical files,
and `fmt --write FILE...` validates and stages the complete batch before transactionally replacing changed files. Standard input
is available as `fmt -`; `--stdin-filename=FILE` supplies its control-byte-free diagnostic name. Check and write modes require
file paths. Formatting changes only whitespace/newline trivia, retains token, comment, action/heredoc, and user-code bytes in
order, and preserves existing mixed newline spellings at required boundaries. A new boundary uses the first newline even inside
opaque text. The output must reparse to an identical location-free AST through a stack-safe iterative comparison and is
idempotent. Write mode rejects aliased targets, preserves full modes and symlinks, and rolls back every target if rename or
directory synchronization fails. Same-directory hard-link backups are synchronized before installation. A backup whose target
could not be restored is retained and reported; cleanup failures after every target was committed are reported as status-0
warnings because they do not undo the committed update.

`ibex lsp [--stdio]` serves the same lossless frontend over LSP 3.17 Content-Length-framed standard IO. Initialization requires a
local `rootUri` or initial `workspaceFolders`; every document URI must remain within those canonical roots. The server uses
full-text synchronization and UTF-16 positions. Open buffers override disk throughout fragment resolution, so changing or
creating an included fragment re-diagnoses all known dependent roots. It supports diagnostics, definition, references,
prepare-rename, rename, and hover. Rename accepts only defined identifiers, checks scope/collisions, includes open versions in
the workspace edit, and reparses/re-resolves every affected closure before returning edits. Grammar actions, heredocs, and user
code are never executed. See [editor setup](editor-setup.md).

`parse_with_diagnostics(max_diagnostics: 20)` collects up to the limit independently from the lexical and syntax phases, merges
them in source order, and returns the globally earliest records. Recovery is deliberately limited to complete declarations,
rules, or outer alternatives at balanced delimiters, so an error inside a nested group cannot synchronize at that group's `|`.
The result may expose a partial AST containing later valid rules, but `success?` remains false and the original source document
does not adopt that AST. `ibex diagnose` renders the same records as text or versioned JSON. After a clean root parse it resolves
includes and emits the first cross-file security, missing-target, cycle, or fragment-syntax failure as
`frontend.resolution_error`; cross-file recovery is intentionally bounded to that one record. Permission and other actual
filesystem read failures remain CLI invocation errors on stderr and do not produce a JSON envelope.

## Declarations

- `pragma extended` enables extended syntax for this grammar even when the CLI uses its default or explicit `--mode=racc`.
  It must immediately follow the class header, before every ordinary declaration. Unknown, duplicate, and misplaced pragmas
  are positioned errors. The pragma is consumed by the frontend and is not stored in AST or Grammar IR output.
- `include "relative/path.y"` inserts one explicit fragment through the canonical resolver. It is available only in extended
  mode and is intentionally not followed by the source-only `Parser` API.
- `## text` is a lossless line comment rather than a parser declaration. A consecutive block immediately above a rule supplies
  its documentation as described above.
- `token NAME ...` declares terminals for typo diagnostics. It is optional. Uppercase names and quoted strings are terminals;
  lowercase names are nonterminals unless they are `error`.
- A `prechigh ... preclow` block lists precedence from high to low; `preclow ... prechigh` lists it from low to high. Each level
  begins with `left`, `right`, or `nonassoc` followed by one or more terminals.
- `options no_result_var` makes an action's final expression its value. `omit_action_call` is enabled by default;
  `no_omit_action_call` disables it.
- `expect N` suppresses the warning when exactly N unresolved shift/reduce conflicts remain. Conflicts resolved by precedence are
  retained in Automaton IR but are not counted.
- `start name` overrides the first rule as the start symbol.
- `convert ... end` changes external token objects. The second column is a quoted string containing Ruby source, not the value
  itself: `NUM ':number'` uses `:number`, while `NUM '"number"'` uses the String `"number"`.
- Extended mode accepts `display SYMBOL "human name"` to give a terminal or nonterminal a human-facing label without changing
  its identity. Runtime errors, `expected_tokens`, and text, graph, and HTML reports prefer that label.
- Extended mode accepts `type SYMBOL "RBS type"` to describe the symbol's semantic value. Display labels and type spellings
  must be non-empty quoted values on the declaration line. Type spellings are copied as opaque RBS and should be checked with
  normal RBS validation. A type declared for an eliminated `%inline` rule is retained on its composition-plan result; a display
  label for an eliminated inline rule is rejected because no runtime or diagnostic symbol remains to consume it.

## Productions and actions

```text
rule
  expression : expression '+' expression { result = val[0] + val[2] }
             | '-' expression = UMINUS
             | NUMBER
             |                         /* empty */
             ;                         /* optional */
end
```

Alternatives use `|`; a trailing semicolon is optional. `= TOKEN` overrides a production's precedence. The `error` terminal
enables yacc-style recovery.

Actions are opaque Ruby between balanced braces. `val` contains RHS values, `result` begins as `val[0]`, and `_values` is a copy
of the surrounding value stack. With `no_result_var`, the action's evaluated value is used directly. A middle action becomes an
empty helper production and consumes one value position in the enclosing RHS.

When a lexer returns `[token, value, location]`, actions can read the corresponding locations as `@1`, `@2`, and so on. `@$`
is the current reduction's immutable `Ibex::Runtime::LocationSpan`. A nonempty span covers the first through last located RHS
entry; an empty production is zero-width at the current lookahead and remains unlocated if no lookahead location was supplied.
A zero-width span's `end_*` coordinates equal its start even if the lookahead supplies wider end coordinates. A middle action
follows that empty-production rule, while its numbered locations address the visible left context. Numbered
references outside the action's value range are generation errors. Location expressions in strings, regular expressions,
symbols, comments, and heredoc bodies remain literal text, and ordinary Ruby instance variables are unchanged.

Action and `inner` backtraces use the original grammar filename and line by default. `--line-convert-all` applies the same mapping
to `header` and `footer`; `-l` keeps all backtraces on generated-file lines.

### Parameterized rules (extended mode)

A parameterized rule is a structural template:

```text
  list(X): X:value { result = [value] }
         | list(X) ',' X { result = val[0] + [val[2]] }
  wrapped(X): (X | list(X))?
  numbers: wrapped(list(NUM)):items { result = items }
```

The ordered formals are identifiers and calls may be nested. The callee and opening parenthesis must be byte-adjacent.
Consequently, `list(NUM)` is a call while `ITEM (A | B)` retains its existing meaning as a symbol followed by an EBNF group.
A named reference or `?`, `*`, or `+` after the closing parenthesis applies to the specialized result.

Templates are not standalone nonterminals and cannot be the start symbol. Repeated definitions must use the same ordered
formals. Duplicate formals, mixed plain/template definitions, terminal collisions, undefined templates, and arity mismatches
are positioned errors. Formal occurrences are replaced structurally through nested calls, groups, suffixes, and separated
lists. `X:value` applies `value` to the substituted symbol or call. A formal `= X` precedence override requires that invocation
to pass one plain symbol for `X`; ordinary precedence overrides are retained unchanged. Named references inside arguments and
using a formal as a callee are rejected to avoid ambiguous capture.

The Normalizer memoizes a specialization before expanding its body, so direct and mutual same-argument recursion reuse one
internal `$parameter_N` nonterminal. Resumable item and EBNF continuations on an explicit depth-first worklist preserve ordinary
helper and production order while bounding argument-growing recursion without relying on the Ruby stack. The defaults are
1,000 distinct specializations and 16 active expansions; programmatic callers can configure positive-Integer
`max_parameter_specializations:` and `max_parameter_depth:` values. Specialized productions retain template actions,
precedence, types, documentation, locations, and include chains. Grammar IR v2 records
`expansion.parameter {rule, arguments}`; v1 output omits the expansion record.

### Inline rules (extended mode)

`%inline` directly before a definition marks a reusable phrase for structural substitution:

```text
  %inline atom: NUM:value { result = value }
              | '(' expression ')' { result = val[1] }
  %inline pair(X): X X { result = val }
  expression: pair(atom):values { result = values }
```

The marker must be the exact `%inline` directive followed by whitespace; `%` inside Ruby actions remains Ruby. Inline
definitions work in roots and fragments and may be plain or parameterized. They do not become final Grammar IR symbols or
productions. Every definition of a name must agree on its inline marking and parameter formals. Inline rules cannot collide
with terminals or be the start symbol. Direct, mutual, or indirect cycles whose path contains an inline rule are rejected,
including cycles through ordinary rules, nested EBNF, and parameterized calls.

Alternatives are substituted left-to-right before LR construction. Nested or repeated uses form a deterministic cartesian
product. The caller's explicit precedence override wins; otherwise the rightmost precedence-contributing inline phrase retains
its explicit override, and flattened terminals retain normal rightmost-terminal precedence. `Ibex::Normalizer` accepts a
positive-Integer `max_inline_expansions:` limit, defaulting to 10,000 materialized productions. Parameter actuals contribute
cycle edges only when their callee position is transitively live, and both cycle validation and expansion use heap worklists so
grammar nesting is independent of the Ruby call stack.

Eliminated reductions still run their explicit or implicit actions in logical post-order. Named references, `val`, `_values`,
`@N`, `@$`, empty spans, middle actions, `result`/`no_result_var`, and parser instance methods retain their logical rule view.
Grammar IR v2 serializes the executable sequence in `action.composition.plan` and records
`expansion.inline {rule}`; dump/load followed by code generation preserves it. `yyaccept` and `yyerror` stop the remaining
logical fragments and caller after the current fragment completes, and `yyerrok` does not erase that `yyerror`. Version 1 omits
both metadata families.

The action scanner handles nested braces, quoted/backtick strings and interpolation, `%q/%Q/%w/%W/%i/%I/%x/%r/%s`, regular
expressions, comments, character literals, and unquoted, single-quoted, double-quoted, or backtick heredocs. Indented, squiggly,
interpolated, and multiple heredocs on one opener line are supported. Heredoc terminators follow their indentation mode, and
multiple openers on one line are consumed in source order.

## Runtime errors

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it and return to allow an `error`
production to recover. Unknown external token objects receive a temporary negative internal id, remain printable through
`token_to_str`, and always invoke `on_error` before recovery is attempted.

Three optional observer methods default to no-ops. `on_shift(token_id, value, state)` follows each ordinary input-token shift;
`on_reduce(production_id, values, result)` follows a completed semantic action and goto; and
`on_error_recover(token_id, value, value_stack)` follows a successful synthetic `error` shift while retaining the original
unexpected-token context. Hook return values are ignored and exceptions propagate. See
[ADR 0013](decisions/0013-runtime-observation-hooks.md) for exact ordering and snapshot semantics.

For external tooling, `observe { |event| ... }` registers an ordered observer and returns an opaque subscription accepted by
`unobserve`. Events are immutable, sequence-numbered per parse session, and cover `start`, `shift`, `reduce`, `error`, `recover`,
`discard`, `accept`, and `reject`. Semantic values and locations are bounded JSON summaries rather than live objects.
`Ibex::Runtime::EventJSONLTracer.attach(parser, io:)` writes the versioned schema at
`schema/runtime-event-v1.schema.json`; write and serialization failures propagate. This API is separate from the legacy
hook-shaped `Runtime::JSONLTracer`. See [ADR 0050](decisions/0050-stable-immutable-runtime-events.md).

Assign an immutable `Ibex::Runtime::RepairPolicy` before parsing to opt into bounded insertion, deletion, and replacement search.
The default costs are 1/1/2 with maximum cost 3, 5,000 configurations/table actions, eight lookahead records, three successful
shifts, and a 256-state simulated stack. `on_repair(plan)` observes the selected immutable edits after the one `on_error` call and
before normal action replay. Insertions carry nil values, replacements retain the original value/location, and search failure
continues into yacc recovery without reporting the incident twice. Push parsing may return `:need_more` while retaining the
unexpected token. Semantic `yyerror` is not automatically repaired. See [ADR
0053](decisions/0053-bounded-minimum-cost-runtime-repair.md).

The versioned stream can be converted to grammar-test coverage with `ibex coverage collect EVENTS.jsonl`, combined across
processes with `coverage merge`, and gated with `coverage check --min-states=PERCENT --min-productions=PERCENT`. State coverage
counts the initial state plus committed shift, reduce-goto, and recovery destinations; production coverage counts committed
reductions. Complete sessions and generated-parser metadata are required. Reports follow
`schema/runtime-coverage-v1.schema.json`; see [ADR 0051](decisions/0051-deterministic-runtime-coverage.md).

`ibex debug AUTOMATON.json [TOKEN...]` simulates shifts, reductions, gotos, accept, and error directly from validated Automaton
IR. It never executes actions. When tokens are omitted, supply one terminal name or unique display name per stdin line; a blank
line or EOF finishes the input. Use `--format=json` for `schema/table-simulation-v1.schema.json`, and bound pathological tables
with positive `--max-steps` and `--max-stack`. See [ADR 0052](decisions/0052-safe-automaton-table-simulation.md).

## Extended EBNF and names

Extended mode supports:

- `item?`: `nil` or the item value.
- `item*`: zero or more values as an Array.
- `item+`: one or more values as an Array.
- `separated_list(item, separator)`: zero or more item values; separators are omitted.
- `separated_nonempty_list(item, separator)`: one or more item values.
- `symbol:name`: binds the corresponding RHS value as a local variable in the final action.

Parenthesized groups may contain sequences, alternatives, and nested EBNF, for example `(KEY VALUE)*`, `(A | B)+`, or
`separated_list((KEY VALUE), ',')`. A one-item group has that item's value; a multi-item group has an Array of its item values;
an empty group has `nil`. Named references must be unique in an outer alternative and cannot use `result`, `val`, or `_values`;
references inside a group are rejected because the group is lowered behind one outer value slot. Text, DOT, Mermaid, and HTML
reports render lowered helper nonterminals as their original EBNF expressions instead of exposing generated helper names.

Actions and named references are supported on an outer production alternative, but not inside a parenthesized EBNF group.
Move the action or binding to a separately named ordinary rule and reference that rule from the group.

## Strict diagnostics

Grammar IR retains structured diagnostics for undeclared or unused terminals, unreachable nonterminals, duplicate productions,
unused precedence declarations, explicitly declared terminals used only by unreachable rules, and a start symbol that cannot
derive any terminal sentence. They remain silent by default for compatibility. `--warnings=all` prints them,
`--warnings=all,error` or `--warnings=error` promotes them to command failures, and `--warnings=none` explicitly suppresses them.
An unexpected LALR conflict also gets an advisory `--algorithm=lr1` note when canonical LR(1) removes at least one unresolved
conflict; this note does not change generation or exit status.

## Transactional generation and watch mode

Ruby generation renders all requested files before replacing any target. Existing targets keep their modes, `--executable`
selects an executable parser mode, and generated paths that alias an input, have multiple hard links, or collide by portable
case/Unicode spelling are rejected. Companion outputs publish before the parser.

`--manifest[=FILE]` opts into a version-1 JSON manifest; without `=FILE`, `parser.rb` uses `parser.ibex.json`. The manifest is
published last and records the exact canonical root, fragments, IR input, and message bytes consumed, relevant generation
options, and every other artifact's path, size, and SHA-256 digest. `--check --manifest` compares all requested output bytes and
the manifest without rewriting them. `Ibex::GenerationManifest.validate_file(path)` validates the document and its current
artifact bytes. For coherent concurrent reads, read the manifest, verify every entry, and retry from a newly read manifest if
anything is missing or mismatched.

`--watch` repeatedly applies the same transaction to Ruby file generation. It observes the root, the latest successful include
closure, unresolved include attempts, an optional messages file, and repairable output paths. Failed candidates leave the last
successful generation intact; an unchanged failure is reported once. Source changes during render or publication retry after
debouncing. Watch mode requires a grammar file and cannot be combined with stdin, `--from`, `--check`, or `--check-only`.
`SIGINT` and `SIGTERM` exit with status 130 and 143. Rake tasks are timestamp-based and reject `--watch`.

## State-specific error messages

`ibex errors --update grammar.y` writes `grammar.messages`; use `--update=FILE`, `--algorithm=NAME`, or an IR `--from` option to
select another destination or automaton. The UTF-8 line-oriented format keeps message text separate from generated Ruby:

```text
# ibex-messages v1
state 4
# expected: "(", INT
| An expression must start here.
| Use an integer or an opening parenthesis.
end
```

Blank lines and comments are ignored. Message lines start with `|`; multiple lines are joined with newlines, and `\\`, `\n`,
`\t`, and `\r` are the supported escapes. Re-running `errors --update` retains message bodies for matching state numbers and
moves disappeared states to `removed N` entries for review. State numbers belong to one generated automaton and may change after
grammar, algorithm, option, or generator changes, so always review retained and removed entries after updating.

Pass the reviewed file to Ruby generation with `--messages=grammar.messages`. An active state absent from the current automaton is
an error with an instruction to update; removed entries are ignored. A matching message replaces only the generic syntax-error
sentence, while structured token, location, expected-token, suggestion, source-line, and caret data remain available.

## Analysis and visualizations

`--emit=sets` writes deterministic JSON containing nullable nonterminals and their FIRST and FOLLOW sets. `--dot=FILE` and
`--mermaid=FILE` write automaton graphs. `--html=FILE` writes a self-contained report with state search, conflict highlighting,
and a filter that keeps a selected conflict state and its one-hop neighbors. All three visualizations can be produced while
generating Ruby or when resuming from Automaton IR. `--railroad=FILE` writes a self-contained SVG railroad diagram from normalized
Grammar IR, so it is also available before automaton construction and when resuming from Grammar or Automaton IR.

`ibex explain grammar.y` is the focused conflict view. `--state=N` and `--token=NAME` select their intersection;
`--format=text|json` chooses step-by-step text or the version-1 document described by `schema/explain-v1.schema.json`.
`--algorithm=slr|lalr|lr1` selects construction, `--mode=racc|extended` applies the same frontend mode as generation, and both
counterexample budget options bound its witness search. Search runs only after state and token selection and only for matching
conflicts. Token selectors prefer a canonical grammar name, then an exact unique display name. Unknown or ambiguous selectors
are errors; valid selectors with no matching conflict succeed with an empty result.

## Ruby DSL

The DSL builds the same AST and IR without evaluating grammar text:

```ruby
ast = Ibex::Frontend::DSL.grammar(class_name: "Calculator") do |grammar|
  grammar.token(:NUM)
  grammar.precedence { |levels| levels.left("'+'"); levels.left("'*'") }
  grammar.rule(:expr) do |rule|
    rule.alt(:expr, "'+'", :expr, action: " result = val[0] + val[2] ")
    rule.alt(:NUM)
  end
end

grammar_ir = Ibex::Normalizer.new(ast).normalize
```

The builder also provides `options`, `expect`, `start`, `convert`, `display`, `type`, `user_code`, `ref(as:)`, `optional`,
`star`, `plus`, `separated_list`, and `inline`.
