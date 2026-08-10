# Grammar reference

<!-- stable:compatible-parser:v2 -->

Ibex's `default` mode accepts the compatible grammar described here. `--mode=extended` or an explicit grammar-file
`pragma extended` adds the marked syntax; extensions are never inferred from a production.

## File structure

```text
class Namespace::Parser < OptionalSuperclass
  pragma extended       # optional; must precede ordinary declarations
  pragma cst            # optional automatic concrete-tree mode
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

Extended roots may import explicit fragment files:

```text
fragment
  token SHARED
  import "nested/expressions.y"
rule
  shared_rule: SHARED
end
```

Fragments own no class, superclass, pragma, options, expected-conflict count, start symbol, or user-code blocks. Their `rule`
section may be empty. Token, precedence, conversion, display, and type declarations are merged with their original locations.
`import "relative/path.y"` appears in the declaration section of a root or fragment and requires extended mode. The older
`include` spelling remains a compatible alias. Paths are
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

`ibex fmt [--mode=default|extended] grammar.y` formats to stdout. `fmt --check FILE...` reports all invalid or noncanonical files,
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

## Generated parser execution boundary

Static frontend, formatting, LSP, documentation, IR, and analysis operations
treat parser actions, generated lexer actions, and user-code sections as opaque
data and do not execute them. Every semantic parse executes parser production
actions. Generated lexer actions additionally execute for `parse(source)`,
generated-lexer `lex(source).do_parse`, and generated-lexer
`parse_with_syntax(source)`. A handwritten `next_token` used by `do_parse` or
no-argument `parse_with_syntax` does not invoke generated lexer actions, nor do
the caller-fed `yyparse` and `push` / `finish` APIs.

Loading the generated file may execute `header`, `inner`, and `footer` code on
all of these paths. Generated runtime execution is trusted application code,
not a sandbox.

Generated `parse_syntax` and `incremental_session` are syntax-only: they
suppress parser production actions but still execute generated lexer actions.
They may also inherit side effects from loading user sections. A future
nonexecuting syntax profile would require a declarative built-in-only lexer and
no user-code sections; the current generated parser API is not that profile.

## Declarations

- `pragma extended` enables extended syntax for this grammar even when the CLI uses its default or explicit `--mode=default`.
  It must immediately follow the class header, before every ordinary declaration. Unknown, duplicate, and misplaced pragmas
  are positioned errors. The frontend records the effective mode on the root AST, and Grammar IR v2 records extended mode
  additively so downstream generators preserve its runtime behavior.
- `pragma cst` enables extended syntax and builds a pure-syntax Red/Green tree
  in parallel with the ordinary semantic value stack. Distinct pragmas may be
  combined in the class header; repeating either one is an error. Grammar IR
  v2 stores the optional `cst: true` setting.
- `import "relative/path.y"` inserts one explicit fragment through the canonical resolver. `include` is an accepted
  compatibility spelling. Imports are available only in extended mode. Parsing source text alone performs no filesystem
  access; path-based callers use `Frontend::Resolver` to resolve the import graph.
- `## text` is a lossless line comment rather than a parser declaration. A consecutive block immediately above a rule supplies
  its documentation as described above.
- `token NAME ...` declares terminals for typo diagnostics. It is optional. Uppercase names and quoted strings are terminals;
  lowercase names are nonterminals unless they are `error`. In extended mode, `token PLUS "+"` declares `PLUS` and assigns
  `"+"` as its display name; the dedicated `display` declaration remains available.
- A `prechigh ... preclow` block lists precedence from high to low; `preclow ... prechigh` lists it from low to high. Each level
  begins with `left`, `right`, or `nonassoc` followed by one or more terminals. Extended `%precedence` assigns a level without
  associativity; an equal-level shift/reduce choice therefore remains an unresolved, counted default shift.
- `options no_result_var` makes an action's final expression its value. `omit_action_call` is enabled by default;
  `no_omit_action_call` disables it.
- `expect N` suppresses the warning when exactly N unresolved shift/reduce conflicts remain. Conflicts resolved by precedence are
  retained in Automaton IR but are not counted.
- Extended `%expect-rr N` records the expected reduce/reduce count. Under `--warnings=error`, generation succeeds only when
  both declared counts match.
- Extended roots accept one `parser ... end` block before `rule`. `algorithm`
  accepts exactly `slr`, `lalr`, `ielr`, or `lr1`; `entries` accepts exactly
  `shared` or `isolated`. Keys may appear in either order, but duplicate blocks,
  duplicate keys, unknown keys or values, and `algorithm auto` are positioned
  errors. `entries isolated` requires at least two declared start symbols.
  Fragments cannot own parser-wide construction. During canonical generation a
  matching `--algorithm` or `--entry-isolation` is accepted and a conflicting
  request is rejected. Analysis and `ibex test` may explicitly choose another
  algorithm and report the declared and selected values as noncanonical.
- `start name` overrides the first rule as the start symbol. Extended mode accepts an ordered list such as
  `start program expression`. The first name remains the primary entry for `do_parse`; generated parsers also expose
  `parse_program` and `parse_expression`. Shared construction attributes each conflict to its reachable entries and marks a
  conflict as composite when it exists only after their LALR states are merged. `--entry-isolation` builds disjoint state sets
  for every entry and can remove such composite conflicts at the cost of a larger table.
- `Parser#expected_tokens_exact` simulates reductions and gotos on a private stack to report only viable lookaheads. Extended
  grammars use this LAC result for `expected_tokens`; compatible grammars keep the historical current-state result.
- `convert ... end` changes external token objects. The second column is a quoted string containing Ruby source, not the value
  itself: `NUM ':number'` uses `:number`, while `NUM '"number"'` uses the String `"number"`.
- Extended mode accepts `display SYMBOL "human name"` to give a terminal or nonterminal a human-facing label without changing
  its identity. Runtime errors, `expected_tokens`, and text, graph, and HTML reports prefer that label.
- Extended mode accepts `type SYMBOL "RBS type"` to describe the symbol's semantic value. Display labels and type spellings
  must be non-empty quoted values on the declaration line. Type spellings are copied as opaque RBS and should be checked with
  normal RBS validation. A type declared for an eliminated `%inline` rule is retained on its composition-plan result; a display
  label for an eliminated inline rule is rejected because no runtime or diagnostic symbol remains to consume it.
- Extended roots accept one `%recover sync: TOKEN ...` declaration. Every name must be a unique declared terminal other than
  `error`. When explicit yacc recovery cannot shift `error`, the runtime discards through the first listed synchronization
  token it encounters, pops to a state that accepts it, and then processes that retained token normally.
- Extended roots accept repeated `%on_error_reduce NAME ...` declarations for nonterminals. Names on one line share a priority;
  each later declaration has higher priority. A uniquely highest-priority completed production fills only table cells that
  would otherwise be errors, so explicit shifts, reductions, accepts, and conflict decisions remain authoritative.
- Extended roots accept ordered `%test accept "source"` and `%test reject "source"` declarations. Sources must use
  double-quoted Ruby literals and exact duplicate expectation/source pairs are rejected. Grammar IR v2 retains their decoded
  source and location; ordinary generated parser tables do not.

## Generated lexer (extended mode)

```text
lexer
  skip /\s+/
  NUMBER /\d+/ { |text| Integer(text, 10) }
  state STRING do
    on '"' { pop_state; emit :STRING_END }
    CHUNK /[^"\\]+/
  end
  on '"' { push_state :STRING; emit :STRING_BEGIN }
end
```

Each state tries its rules at the current position with an internal `\A` anchor.
The longest lexeme wins; declaration order breaks equal-length ties. A named
rule emits its declared terminal and uses the lexeme as its value. Its optional
action may return a converted value or call `emit TOKEN, value`. `skip` consumes
without emitting; `on` must call `emit` or `skip`.

`state NAME do ... end` creates an exclusive state. Lexer actions call
`push_state` and `pop_state`; parser actions use the public `lexer_state`
reader/writer when grammar context changes tokenization. `INITIAL` is reserved,
states are flat and unique, named rules must reference declared terminals, and
patterns that match the empty string are rejected.

Generated `parse(source, file: "(input)")` accepts String, IO, or Fiber input.
IO/Fiber chunks can end inside tokens. Locations use one-based grapheme
`column`/`grapheme_column`, explicit byte columns, and half-open
`start_byte`/`end_byte` offsets. Unicode property escapes use Ruby Regexp
semantics.

Regex execution remains subject to Ruby Regexp complexity. The static lint
flags common nested-quantifier shapes as `lexer_redos`; `--warnings=all,error`
promotes the warning to an error. This heuristic is not a proof of safety.
Applications must still bound untrusted input and review patterns. See the
[lexer migration guide](lexer-migration.md) and [ADR 0014](decisions/0014-versioned-generated-lexer.md).

## Concrete syntax trees

With `pragma cst`, every shift and reduction builds immutable pure-syntax
Green values on a stack parallel to semantic values. Semantic actions execute
unchanged and never enter syntax children. `parse`, `do_parse`, and `yyparse`
return the semantic result; generated lexers additionally expose
`parse_with_syntax(source, file:)`, whose result provides `value`,
`syntax_root`, and `diagnostics`. The root is always
`source_file(start-symbol, $eof)`. Lazy `CST::SyntaxNode` and
`CST::SyntaxToken` wrappers provide parents, offsets, spans, locations,
pattern matching, and typed `@node` fields.

Generated lexers accept `--cst-trivia=leading|balanced|drop`; `attach` is an
alias for `leading`. Leading ownership places skipped text on the following
token. Balanced ownership places text through the first newline on the
preceding token and the remainder on the next token. EOF owns final trivia.
Drop omits trivia and deliberately disables coordinate and incremental APIs.

Lexical failures, yacc recovery, panic discards, and bounded repair retain
consumed input in error nodes, skipped trivia, or zero-width missing tokens.
Inspect `diagnostics`, `contains_error?`, `each_error`, and token
`missing?`/`error?`; an unrecoverable parse is rooted under
`synthetic_root`. Application exceptions still propagate. Only current
format-v6 structured CST tables are executable; older CST tables fail before
token consumption and must be regenerated. See the
[CST guide](cst.md) and [migration guide](cst-migration.md).

## Generated AST nodes and traversal

An extended, action-free alternative may end with an explicit node shape:

```text
rule
  expression: expression PLUS expression @node Addition(left, operator, right)
            | NUMBER                     @node Number(value)
end
```

Fields map positionally to normalized RHS values. Their count must match, each
must be a unique non-keyword Ruby local identifier, and a node name must be a
Ruby constant identifier. Reusing a node name is allowed only with the same
ordered fields. `@node` cannot be combined with a trailing or middle semantic
action; write the explicit action instead when construction is not positional.

The generated parser defines the classes under its `AST` module. Ruby 3.2 and
later use `Data`; Ruby 3.0 and 3.1 use an immutable keyword-Struct compatibility
implementation with the same readers, `deconstruct`, and `deconstruct_keys`.
Generated RBS types each field from its grammar symbol and infers a fully
annotated nonterminal as the union of its node classes.

`AST::Visitor#visit` dispatches to `visit_<node>` and recursively visits fields
by default. `AST::Listener#walk` calls `enter_<node>`, walks fields, and calls
`exit_<node>`. The generated RBS enumerates every hook, so a consumer can
subclass either base under Steep without maintaining a parallel node list.

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

Extended grammars can write `%empty` as the sole RHS item to document an empty alternative. An implicit empty alternative stays
compatible but produces `implicit_empty` under extended warning analysis.

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

`Ibex::Location` is an immutable one-based source range with optional half-open byte offsets. Instance `join` and class
`Ibex::Location.join` return a covering range and reject mixed files. Lexer-owned hashes and objects remain valid. Inside an
action, `loc(1)` and `loc(:name)` are callable equivalents of numbered and named RHS locations, while `result_loc` returns the
current synthesized span. Calls outside an action, unknown names, and out-of-range positions fail explicitly. Parsers that use
only two-element tokens and no location-sensitive action or observer do not allocate a parallel location stack.

Action and `inner` backtraces use the original grammar filename and line by default. `--line-convert-all` applies the same mapping
to `header` and `footer`; `-l` keeps all backtraces on generated-file lines.

### Constructor parameters (extended mode)

`%param name` adds a required keyword argument to the generated parser constructor. A quoted RBS type is optional:

```text
%param context "ParserContext"
%param lexer
```

`Parser.new(context: ..., lexer: ...)` stores the objects as `@context` and `@lexer`. Semantic actions receive locals with the
same names, so the context is available without global state; lexer methods in the `inner` section use the instance variables.
The generated RBS declares typed instance variables and constructor keywords, using `untyped` when no type is supplied.
Parameters are root-only, unique Ruby local identifiers, and cannot be Ruby keywords. The generated initializer is prepended,
so a custom superclass initializer may receive any remaining keyword arguments.

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
helper and production order while avoiding dependence on the Ruby stack. The default is
1,000 distinct specializations; programmatic callers can configure the positive-Integer
`max_parameter_specializations:`. Argument-changing recursive instantiation is rejected by structural cycle detection rather
than an arbitrary depth boundary. Specialized productions retain template actions,
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

With `%recover sync:`, a returned `on_error` first permits ordinary yacc `error`-token recovery. Only when no stack state can
shift `error` does panic-mode synchronization begin. Discarded application tokens call `on_discard` with reason `recovery`;
the selected synchronization token is not discarded. `on_error_recover` and the `recover` event fire once after a stack state
that accepts the synchronization token is found. EOF before a usable synchronization point rejects the parse.

Optional observer methods default to no-ops. `on_shift(token_id, value, state)` follows each ordinary input-token shift;
`on_reduce(production_id, values, result)` follows a completed semantic action and goto; and
`on_error_recover(token_id, value, value_stack)` follows a successful synthetic `error` shift while retaining the original
unexpected-token context. Their `on_shift_location`, `on_reduce_location`, and `on_error_recover_location` companions add
locations while preserving the original hook signatures. `on_discard(token_id, value, location, reason)` reports an
application token removed by yacc recovery. Hook return values are ignored and exceptions propagate. `trace_value_printer=`
opts a parser into value rendering in `yydebug`; without it, traces never expose semantic values. Extended grammars may define
symbol-specific `%printer SYMBOL { Ruby expression }` formatters. Their `value` local has the symbol's declared semantic type,
and declared `%param` locals are also available. A programmatic printer overrides generated symbol formatters. Neither form is
called unless `yydebug` is true, and formatter failures are rendered by exception class without inspecting the value. See
[ADR 0010](decisions/0010-committed-runtime-observation.md) for the observation boundary.

For external tooling, `observe { |event| ... }` registers an ordered observer and returns an opaque subscription accepted by
`unobserve`. Events are immutable, sequence-numbered per parse session, and cover `start`, `shift`, `reduce`, `error`, `recover`,
`discard`, `accept`, and `reject`. Semantic values and locations are bounded JSON summaries rather than live objects.
`Ibex::Runtime::EventJSONLTracer.attach(parser, io:)` writes the versioned schema at
`schema/runtime-event-v1.schema.json`; write and serialization failures propagate. See
[ADR 0010](decisions/0010-committed-runtime-observation.md).

Every parser instance owns immutable `Runtime::ResourceLimits`. The defaults allow a 10,000-entry LR state stack and 100
recovery entries per parse. Pass `resource_limits:` to the generated parser constructor or replace it while the instance is
idle. Stack shifts/gotos and recovery entries that exceed their budget raise `Ibex::ResourceLimitError` with structured
resource, limit, observed value, state, and location data. Concurrent parses share immutable generated tables but must use
distinct parser instances.

Assign an immutable `Ibex::Runtime::RepairPolicy` before parsing to opt into bounded insertion, deletion, and replacement search.
The default costs are 1/1/2 with maximum cost 3, 5,000 configurations/table actions, eight lookahead records, three successful
shifts, and a 256-state simulated stack. `on_repair(plan)` observes the selected immutable edits after the one `on_error` call and
before normal action replay. Insertions carry nil values, replacements retain the original value/location, and search failure
continues into yacc recovery without reporting the incident twice. Push parsing may return `:need_more` while retaining the
unexpected token. Semantic `yyerror` is not automatically repaired. See [ADR
0012](decisions/0012-bounded-nonexecuting-analysis.md).
The gallery JSON [error UX evidence](error-ux.md) records the SP-4 baseline:
8 of 10 selected plans were assessed useful, so the bounded single-plan feature
continues as an explicit experimental option.

The versioned stream can be converted to grammar-test coverage with `ibex coverage collect EVENTS.jsonl`, combined across
processes with `coverage merge`, and gated with `coverage check --min-states=PERCENT --min-productions=PERCENT`. State coverage
counts the initial state plus committed shift, reduce-goto, and recovery destinations; production coverage counts committed
reductions. Complete sessions and generated-parser metadata are required. Reports follow
`schema/runtime-coverage-v1.schema.json`; see [ADR 0010](decisions/0010-committed-runtime-observation.md).

`ibex debug AUTOMATON.json [TOKEN...]` simulates shifts, reductions, gotos, accept, and error directly from validated Automaton
IR. It never executes actions. When tokens are omitted, supply one terminal name or unique display name per stdin line; a blank
line or EOF finishes the input. Use `--format=json` for `schema/table-simulation-v1.schema.json`, and bound pathological tables
with positive `--max-steps` and `--max-stack`. See [ADR 0012](decisions/0012-bounded-nonexecuting-analysis.md).

## Grammar-declared tests

`ibex test [--mode=MODE] [--algorithm=NAME] [--entry-isolation] [--timeout=SECONDS] grammar.y` executes every `%test` in source
order. The generated parser class must be constructible without arguments and define `parse(source)`. Each case uses a fresh
instance. A normal return counts as acceptance, `Ibex::Runtime::ParseError` counts as rejection, and lexer/application
exceptions are test errors rather than syntax rejections. Empty suites and grammars with required `%param` declarations fail
explicitly.

The complete suite runs in an isolated Ruby child process with a ten-second default timeout. Generated footer guards remain
false because a separate runner loads the parser file. Output is TAP-like and the command exits nonzero on any mismatch,
exception, timeout, or invalid child result. This is process isolation for reliable tooling, not a sandbox for untrusted code.

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
An unexpected LALR conflict also gets an advisory `--algorithm=ielr` note when IELR removes at least one unresolved
conflict; this note does not change generation or exit status.

`ibex check --ambiguity grammar.y` searches every parser conflict for a complete sentence accepted through two interpretations.
`--max-tokens` and `--max-configurations` bound the search per conflict; `--algorithm=lr1` excludes conflicts introduced only by
LALR merging. Exit status 1 means a concrete ambiguity was found, 2 means a configuration budget was exhausted, and 0 means no
ambiguity was found within the declared bounds. The last result is not a general proof of unambiguity. `--format=json` emits
the versioned check result and explored counts.

When an empty helper created for a middle action participates in a conflict, Automaton IR, text reports, HTML, and
`ibex explain` retain the action's source location as `midrule_origins`. This makes the otherwise synthetic reduction traceable
to the grammar expression that introduced it.

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

The version-1 `options` object is the existing open map for additive generation evidence. It now always records the effective
`cst_trivia` value: an omitted option uses the built-in `leading` default, and the compatibility spelling `attach` is recorded
canonically as `leading`. Adding this entry changes neither the manifest's required root shape nor its schema version.

`--watch` repeatedly applies the same transaction to Ruby file generation. It observes the root, the latest successful include
closure, unresolved include attempts, an optional messages file, and repairable output paths. Failed candidates leave the last
successful generation intact; an unchanged failure is reported once. Source changes during render or publication retry after
debouncing. Watch mode requires a grammar file and cannot be combined with stdin, `--from`, `--check`, or `--check-only`.
`SIGINT` and `SIGTERM` exit with status 130 and 143. Rake tasks are timestamp-based and reject `--watch`.

## Example-keyed error messages

`ibex errors --list grammar.y` prints a deterministic `ibex-messages v2` template without writing a file. Each entry is keyed by
a shortest token sentence that reaches a syntax error, rather than by an unstable automaton state number:

```text
# ibex-messages v2
sentence: NUM '+' ')'
## E0042
# entry: expression
# state: 7
# expected: '(', NUM
| An operand or opening parenthesis is required before ')'.
end
```

The `# state:` and `# expected:` lines are review hints; the sentence and error ID are the durable keys. Message lines start with
`|`; multiple lines are joined with newlines, and `\\`, `\n`, `\t`, and `\r` are the supported escapes. Blank lines and comments
are ignored.

`ibex errors --update grammar.y` atomically writes `grammar.messages`; use `--update=FILE`, `--algorithm=NAME`, or an IR `--from`
option to select another destination or automaton. It keeps IDs and message bodies, and reports three review classes on stdout:
`unreachable` when a saved sentence is no longer an error, `uncovered` for a new error state, and `moved` when a sentence now
reaches a different state. An existing v1 numeric-state file is accepted and migrated on update. Use `--max-tokens=N` and
`--max-configurations=N` to bound the shortest-sentence search; both default to the counterexample search limits.

Pass the reviewed file to Ruby generation with `--messages=grammar.messages`. Each matching message replaces only the generic
syntax-error sentence. `ParseError#error_id` exposes its stable `E00xx` identifier, and structured token, location,
expected-token, suggestion, source-line, and caret data remain available. A saved active sentence that no longer reaches an
error is rejected with an instruction to run the updater.

## Analysis and visualizations

`ibex samples grammar.y` emits JSON token arrays derived from Grammar IR.
`--strategy=random|coverage` selects random alternatives or least-covered
production paths; `--path-length=1|2`, token, depth, expansion, count, and seed
options make the search finite and reproducible.

`ibex fuzz grammar.y` without `--against` feeds bounded generated sentences and
single-token insert/delete/replace mutations to SLR, LALR, IELR, and LR(1)
table simulators. It does not execute production actions. `--coverage-guided`
selects uncovered production paths. The JSON report records every effective
bound and returns 0 when no difference is found within those bounds, 1 with a
concrete differential witness, and 2 when a budget prevents completion.
`--format=text` renders the same result and bounds for a terminal; JSON remains
the default versioned contract.
`--against=COMMAND` is an explicit unsafe opt-in that sends each token array as
JSON to the supplied subprocess. It executes arbitrary application code with
the invoking user's host permissions and is not a sandbox. The command is
split into an executable and arguments without an implicit shell, but the
selected executable can itself access the filesystem, network, environment,
and other processes. Exit 0 means accepted and exit 1 means rejected. It
requires `--against-runtime=DESCRIPTION`, and the report records that target
runtime, the exact command, and the Ibex host runtime. Each invocation is
bounded by `--against-timeout=SECONDS` (default 10) and
`--against-max-output=N` (default 1,048,576 bytes); either limit exits 2
instead of treating a stuck or noisy target as a language result. These limits
and process-group cleanup bound resources but do not confine side effects. On
process-group platforms, descendants are terminated with the target. A
difference is automatically delta-minimized while preserving its mismatch kind
and outcomes, then written atomically to `test/fuzz/regressions` with its seed
and effective bounds.
`--max-reduction-trials=N` bounds that work, `--regression-dir=DIR` selects
another destination, and `--no-save-regression` disables persistence. An
incomplete minimization remains a concrete difference and records
`complete: false`; it is never described as minimal.

`ibex reduce --command=COMMAND input` is an explicit unsafe opt-in that
repeatedly executes the supplied checker to perform trial-bounded delta
debugging. The checker may run arbitrary application code with the invoking
user's host permissions; it is not sandboxed. As with external fuzzing,
resource limits and process cleanup do not confine filesystem, network,
process, or other side effects.
Input mode is `tokens` (a JSON string array), `lines`, or `bytes`. A nonzero
normal subprocess exit means the failure persists; a signal is an invocation
error rather than evidence. The version-2 report contains the reduced
sequence, trial count, original/final sizes, every effective limit, and whether
the configured trial budget allowed completion. A trial-limited result is
reported as `incomplete`, never as `minimized`. The checker timeout
(default 10 seconds), checker output (default 1,048,576 bytes), and input
(default 10 MiB) are bounded by `--timeout`, `--max-output-bytes`, and
`--max-input-bytes`. Exceeding any configured budget exits 2 with a distinct
reason. Report v1 remains the prior read-only contract.
`--format=text` selects a human-readable report; JSON remains the default.

`ibex verify automaton.json` validates table semantics by independently
deriving the relevant LR item collection from the embedded Grammar IR. Default
checks cover soundness, lookaheads, default reductions and explicit error
masks, reachability/productivity, epsilon termination, and conflict
resolution consistency. Both modes rebuild and compare plain/compact rows;
`--strict` adds complete collection checks and reports row mismatches under
the strict V5 identifier. `--max-states` and `--max-items` bound only the
reference derivation. JSON is the default report format; exit 0 means valid, 1
means a concrete violation, and 2 means the reference budget was exhausted.
Opaque semantic actions are never executed. See the
[verifier trust boundary](verifier-trust-boundary.md) for the exact TCB,
algorithm-specific strength, resource non-goals, and generated-artifact
boundary.

`ibex equiv LEFT RIGHT` accepts grammar source, Grammar IR, or Automaton IR.
It combines normalized structural comparison, deterministic samples generated
in both directions, and a breadth-first product search over the two LR state
stacks. A difference returns 1 with a shortest token witness found within
`--max-tokens` and `--max-configurations`; an incomplete search returns 2.
`--samples`, `--seed`, `--max-actions`, and `--max-stack` expose the remaining
bounds. `--map=old_rule=new_rule` requests reduction-tree comparison for a
declared one-to-one rule correspondence. Without a map, only language
acceptance is compared. A successful bounded search is explicitly not a proof
of equivalence.

`ibex diff OLD NEW` accepts the same three input forms and classifies symbols,
rules, conflicts, and normalization warnings into `added`, `removed`, and
`changed`. It also reports before/after/delta counts for states, productions,
warnings, and unresolved conflicts. Conflict identities use token and
production shapes rather than unstable state numbers.

`ibex metrics GRAMMAR` reports normalized rule and alternative counts, average
and maximum branching, epsilon productions, recursive nonterminals, the
longest dependency path after collapsing mutually recursive components, and
deterministic Automaton IR cell/conflict counts. The metric is deliberately
structural; it contains no timing or memory threshold. Both commands default
to their closed version-1 JSON schemas and support `--format=text`.

`ibex fix GRAMMAR` selects an unresolved conflict and searches a finite set of
precedence declarations and overrides, algorithm changes, and `%inline`
rewrites. Rewrites that would move opaque semantic actions, including
recursion reversal and source factoring, are deliberately excluded. A repair
proposal is emitted only if the target disappears, no other conflict fingerprint
increases, the resulting table passes the independent verifier, and bounded
language plus mapped reduction-tree comparison finds no difference. `%expect`
and recovery-quality suggestions are reported separately as non-repair advice;
they never enter the verified proposal or `--apply` path because they do not
eliminate the selected conflict. The JSON
report includes the exact bounds, unified diff, eliminated fingerprint, state
delta, and rejection reasons. `--messages=FILE` measures newly moved,
uncovered, and unreachable message-catalog entries against the original table.
`--apply[=FXNNN]` transactionally applies a source proposal and refuses
symlinks or files with multiple hard links. Candidate, independent-verifier,
or equivalence budget exhaustion exits 2. `--verify-max-states` and
`--verify-max-items` bound the independent collection used for every
candidate. The advice/repair separation and independent-verifier bounds are
reported by the closed `schema/fix-v3.schema.json`; versions 1 and 2 remain
available as prior report contracts. Every successful report states that
bounded search is not a proof of equivalence.

`ibex import bison [--format=source|json] [-o FILE] grammar.y` performs a
one-way, analysis-only conversion. C actions are mechanically reference-mapped
but remain opaque, and Ruby generation is refused. Unsupported directives are
reported at every source position; structural gaps are distinguished from
generator-only controls, and `fix` refuses structurally incomplete imports.
Input bytes, structural tokens, rule groups, and actions have independent
positive budgets. Read-only grammar analysis commands auto-detect two Bison
`%%` section markers. The complete directive, naming, external-corpus, and
CRuby `parse.y` contracts are in the
[Bison import guide](bison-import.md).

All CLI forms accept `--lang=LANG`; `IBEX_LANG` supplies the default. Built-in
diagnostic catalogs ship for `en` and `ja`. Locale suffixes such as
`ja_JP.UTF-8` select their base language, while unavailable translations fall
back to English silently. Stable machine-readable diagnostic codes and report
schemas do not change with the display language. The built-in
`diagnostic.*`, `warning.*`, `conflict.*`, and `note.*` IDs are an internal
translation namespace and never overlap the user-owned `E00xx` message IDs.

`--emit=sets` writes deterministic JSON containing nullable nonterminals and their FIRST and FOLLOW sets. `--dot=FILE` and
`--mermaid=FILE` write automaton graphs. `--html=FILE` writes a self-contained report with state search, conflict highlighting,
and a filter that keeps a selected conflict state and its one-hop neighbors. All three visualizations can be produced while
generating Ruby or when resuming from Automaton IR. `--railroad=FILE` writes a self-contained SVG railroad diagram from normalized
Grammar IR, so it is also available before automaton construction and when resuming from Grammar or Automaton IR.

`ibex explain grammar.y` is the focused conflict view. `--state=N` and `--token=NAME` select their intersection;
`--format=text|json` chooses step-by-step text or the version-1 document described by `schema/explain-v1.schema.json`.
`--algorithm=slr|lalr|ielr|lr1` selects construction, `--mode=default|extended` applies the same frontend mode as generation, and both
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
