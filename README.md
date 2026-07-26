# Ibex

[![Gem Version](https://badge.fury.io/rb/ibex.svg)](https://badge.fury.io/rb/ibex) [![CI](https://github.com/ydah/ibex/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/ibex/actions/workflows/main.yml)

Ibex is a Pure Ruby LR parser generator. It accepts racc-compatible grammar files, generates parsers with the familiar
`do_parse` / `yyparse` API, and requires no C or Java extension. Its staged Grammar IR and Automaton IR can also drive extended
EBNF syntax, diagnostics, visualizations, and alternate LR construction algorithms.

Try a grammar in the [browser playground](https://ydah.github.io/ibex/playground/) or browse the
[API reference](https://ydah.github.io/ibex/api/). The playground runs locally in a Web Worker: grammar source is not uploaded,
and semantic action bodies are not executed.

## Requirements and installation

Ibex supports Ruby 3.0 or later and has no runtime gem dependencies. From a source checkout:

```sh
bundle install
bundle exec rake
```

Build and install the local gem when you want the `ibex` executable on your `PATH`:

```sh
gem build ibex.gemspec
gem install ./ibex-0.1.0.gem
```

## Three-minute calculator

Save this as `calculator.y`:

<!-- calculator-grammar:start -->
```text
class Calculator
token NUM
preclow
  left '+'
  left '*'
prechigh
rule
  expr : expr '+' expr { result = val[0] + val[2] }
       | expr '*' expr { result = val[0] * val[2] }
       | NUM { result = val[0] }
end
---- inner
def parse_tokens(tokens)
  @tokens = tokens
  do_parse
end

def next_token
  @tokens.shift
end
---- footer
if $PROGRAM_NAME == __FILE__
  tokens = [[:NUM, 2], ['+', nil], [:NUM, 3], ['*', nil], [:NUM, 4]]
  puts Calculator.new.parse_tokens(tokens)
end
```
<!-- calculator-grammar:end -->

Generate and run it:

```sh
ibex calculator.y
ruby calculator.rb
# 14
```

From a checkout without installing the gem, use `bundle exec ruby -Ilib exe/ibex calculator.y` and
`bundle exec ruby -Ilib calculator.rb` instead.

Ibex generates compact tables by default. Compatibility-safe default reductions shrink profitable states while retaining
explicit error cells, including recovery and undeclared-token behavior. `--table=plain` produces inspectable Hash rows, while
`-E` embeds the runtime into a single dependency-free output file.

## Lexer contract

Ibex does not generate a lexer. A pull parser implements `next_token` and returns `[token, value]` or
`[token, value, location]`; `false` or `nil` marks EOF.

`Ibex::Location.new(line:, column:, ...)` is the immutable built-in range type; applications may continue to pass hashes or
their own location objects. `location.join(other)` and `Ibex::Location.join(locations)` compute covering ranges when every
location belongs to the same file.

Generated actions can read the location parallel to `val[0]`, `val[1]`, and so on as `@1`, `@2`, and so on; `@$` is the
immutable span of the current reduction. Empty and middle actions use a zero-width span at the current lookahead. Location-less
tokens remain supported and produce `nil` entries. The equivalent public helpers are `loc(1)`, `loc(:name)`, and `result_loc`;
they are available only while an action is running.

Bare grammar tokens normally use Ruby symbols (`:NUM`), and quoted grammar tokens use strings (`'+'`). A yielding source can call
`yyparse(receiver, method_name)` where the receiver method yields the same two- or three-element token arrays, including the
optional location.

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it to use yacc-style `error` recovery.
Semantic actions can call `yyerror`, `yyerrok`, or `yyaccept`. `expected_tokens_exact` reports lookaheads that remain valid after
simulating required reductions without running semantic actions. In extended mode `expected_tokens` uses that exact LAC result;
racc-compatible mode retains its historical current-state behavior.
`push(token, value, location)` / `finish(location:)` provide caller-driven streaming. The default `ParseError` exposes token,
expected-token, state, location, and spelling-suggestion attributes and renders source lines with a caret when available.
Parser subclasses can also override `on_shift(token_id, value, state)`,
`on_reduce(production_id, values, result)`, and `on_error_recover(token_id, value, value_stack)` as no-op-by-default observers.
Location-aware companions add the relevant token/reduction locations without changing those signatures, and
`on_discard(token_id, value, location, reason)` observes application tokens removed by yacc recovery. Ordinary shifts and the
synthetic recovery-token shift use separate hooks; observer return values never replace semantic values. Assign
`trace_value_printer` to a callable to append deliberately formatted semantic values to `yydebug`; values remain hidden by
default. Extended grammars can instead declare symbol-specific formatters such as
`%printer NUM { "number=#{value}" }`; these also run only while `yydebug` is enabled.

Tooling can register an ordered runtime observer with `parser.observe { |event| ... }` and remove it with
`parser.unobserve(subscription)`. The versioned immutable events cover parser start, committed shifts and reductions, syntax and
semantic errors, recovery/discard, acceptance, and rejection without exposing parser stacks or application object identities.
`Ibex::Runtime::EventJSONLTracer.attach(parser, io:)` writes this schema-v1 stream and returns a detachable handle; serialization
and output errors propagate so incomplete traces are visible. The older `Runtime::JSONLTracer` retains its original hook-shaped,
failure-contained byte contract. See [ADR 0050](docs/decisions/0050-stable-immutable-runtime-events.md) and
[`schema/runtime-event-v1.schema.json`](schema/runtime-event-v1.schema.json).

Automatic insertion, deletion, and replacement repair is explicit and bounded:

```ruby
parser.repair_policy = Ibex::Runtime::RepairPolicy.new(
  max_cost: 3,
  max_configurations: 5_000,
  max_lookahead: 8
)
```

Search interprets tables without executing semantic actions, then replays the selected edit through normal parser actions.
`on_error` and `on_repair` run once for a selected incident; exhaustion falls through to existing yacc recovery without a second
error callback. Push parsing can return `:need_more` while it buffers enough evidence. No policy preserves the original read,
allocation, exception, and recovery path. See [ADR
0053](docs/decisions/0053-bounded-minimum-cost-runtime-repair.md).

Collect deterministic state and production coverage from one or more complete event streams without loading generated parsers:

```sh
ibex coverage collect test-events.jsonl -o shard-1.json
ibex coverage merge shard-1.json shard-2.json -o coverage.json
ibex coverage check coverage.json --min-states=80 --min-productions=90
```

Collection rejects truncated sessions and unavailable or mixed parser metadata. Merge requires identical full grammar digests,
table formats, and state/production totals. Thresholds use distinct visited IDs; reports also retain deterministic visit counts.
See [ADR 0051](docs/decisions/0051-deterministic-runtime-coverage.md) and
[`schema/runtime-coverage-v1.schema.json`](schema/runtime-coverage-v1.schema.json).

Inspect parser-table behavior without loading generated Ruby or executing semantic actions:

```sh
ibex --emit=automaton-ir grammar.y > automaton.json
ibex debug automaton.json NUMBER PLUS NUMBER
ibex debug automaton.json --format=json --max-steps=100000
```

With no token arguments, `debug` reads one terminal spelling per stdin line and finishes on a blank line or EOF. Every step shows
the state, lookahead, explicit/default/implicit action source, reduction and goto details, and stack-depth transition. Explicit
error masks take precedence over default reductions. See [ADR
0052](docs/decisions/0052-safe-automaton-table-simulation.md) and
[`schema/table-simulation-v1.schema.json`](schema/table-simulation-v1.schema.json).

## Extended mode

`--mode=extended` enables optional, repeated, and separated values, named references, parameterized rule templates, and inline
rules. A
grammar can make the same choice locally with `pragma extended` immediately after its `class` header:

```text
class ExtendedParser
pragma extended
rule
  arguments : separated_list(NUM, ',') { result = val[0] }
  sum       : NUM:left '+' NUM:right { result = left + right }
  maybe     : NUM?
  many      : NUM*
  some      : NUM+
  pairs     : (KEY VALUE)*
  list(X)   : X:item { result = [item] }
            | list(X) ',' X { result = val[0] + [val[2]] }
  %inline signed(X): '-' X { result = -val[1] }
  numbers   : list(NUM)
  negative  : signed(NUM)
end
```

Extended declarations can add human-readable diagnostics and generated action types:

```text
token PLUS "+"
display NUM "number"
type NUM "Integer"
type expr "AST::Expression"
%expect-rr 0
%param context "ParserContext"
%param lexer
%printer NUM { "number=#{value}" }
```

An extended grammar may expose several parser entry points:

```text
start program expression
```

The generated parser provides `parse_program` and `parse_expression`; `do_parse` keeps using the first declaration for
compatibility. By default the entries share an automaton and conflict reports identify the entries that can reach each conflict.
`--entry-isolation` builds independent state sets when avoiding cross-entry LALR merges is more important than table size.

Precedence blocks also accept `%precedence TOKEN` for precedence without associativity, and productions may use `%empty` as
their sole RHS item. `%param` adds a required keyword to the generated constructor, stores it in the matching instance variable,
and exposes it as a local in semantic actions; an optional quoted RBS type is reflected in `--rbs` and action-shadow checking.
`--warnings=error` promotes mismatched `expect` and `%expect-rr` declarations to generation errors.

The value conventions are `nil` or a value for `?`, and arrays for `*`, `+`, `separated_list`, and
`separated_nonempty_list`. Parenthesized sequences and alternatives can be nested; multi-item groups produce an Array value.
Text, DOT, and HTML automaton reports label lowered helper symbols with these source-level EBNF expressions.

Parameterized definitions do not become standalone productions. A call such as `list(NUM)` is specialized once per structural
argument list and reused by direct or mutual recursion. The callee and `(` must be adjacent: `ITEM (A | B)` remains an ordinary
symbol followed by a group. Calls can be nested and can carry the same named-reference and suffix syntax as symbols. Normalizer
defaults to at most 1,000 specializations; library callers can lower or raise the positive-Integer
`max_parameter_specializations:` limit. Argument-changing recursive instantiation is rejected by
structural cycle detection rather than by a depth boundary.

`%inline` definitions are structurally substituted before LR construction and do not remain as grammar symbols or
productions. Plain and parameterized inline rules may be nested, repeated, and combined with EBNF. Their actions, named values,
semantic locations, and precedence remain observable through a serialized composition plan. Recursive paths involving an
inline rule are rejected. Cartesian expansion defaults to at most 10,000 materialized productions; library callers can set a
positive-Integer `max_inline_expansions:` on `Ibex::Normalizer`.

## Lossless frontend source

Tools that need exact grammar text can parse once and keep the semantic AST beside comments, whitespace, and opaque Ruby:

```ruby
parser = Ibex::Frontend::Parser.new(File.binread("grammar.y"), file: "grammar.y")
document = parser.parse_document

document.ast       # the same AST returned by parser.parse
document.cst       # immutable token/trivia segments
document.render    # byte-for-byte original source
document.slice(document.tokens.first.span)
```

Segment spans are half-open zero-based byte ranges with one-based line and Unicode-scalar columns. CRLF is one line break;
accepted input bytes must be valid UTF-8. Actions, every supported heredoc form, and user-code bodies are retained as opaque text,
while user-code markers and repeated blocks remain separate. `Token#to_h` remains unchanged; documented rules add the nullable
AST and reserved Grammar IR v2 fields described below.

Format a root grammar or an explicit fragment through the same lossless frontend:

```sh
ibex fmt grammar.y
ibex fmt --check grammar.y grammar/expression.y
ibex fmt --write --mode=extended grammar.y grammar/expression.y
printf 'class P rule value:TOKEN end' | ibex fmt --stdin-filename=pipe.y -
```

The formatter changes only whitespace and newline trivia. Token spelling, comments, Ruby actions and heredocs, user-code bodies,
and their order remain byte-for-byte intact. Existing CRLF/LF choices and blank lines are retained at required line boundaries.
New boundaries use the first newline anywhere in the source, including opaque Ruby. The result is reparsed in the same mode and
an iterative, stack-safe comparison rejects it unless its location-free semantic AST equals the original; formatting is
idempotent. `--check` visits every file and exits 1 for parse failures or differences. `--write` rejects aliased targets, stages
the whole batch in target directories, synchronizes hard-link backups before installation, and rolls every file back if a
rename or directory synchronization fails. A failed restore preserves and reports its backup; cleanup trouble after a committed
batch is a status-0 warning. Full modes and relative or absolute symlink targets are preserved. See [ADR
0047](docs/decisions/0047-semantics-preserving-grammar-formatting.md).

## Language server

Run the dependency-free LSP 3.17 server over stdio:

```sh
ibex lsp --stdio
```

It publishes bounded diagnostics for open roots and their disk or unsaved fragment closure, and provides definition,
references, guarded cross-file rename, and grammar-aware hover. Only local file URIs within initialized workspace roots are
accepted. UTF-16 editor positions are converted to the frontend's byte/scalar spans without executing actions, heredocs, or
user code. See [editor setup](docs/editor-setup.md) and [ADR
0048](docs/decisions/0048-overlay-workspaces-and-lsp.md).

## Grammar fragments

Extended mode can compose grammars without giving included files root ownership:

```text
# grammar.y
class Parser
include "grammar/expression.y"
rule
start: expression
end

# grammar/expression.y
fragment
token NUMBER
rule
expression: NUMBER
end
```

Use `--mode=extended` or place `pragma extended` after the root class header. Fragments cannot define a class, superclass, start,
options, expected conflicts, pragma, or user-code blocks. Resolution is depth-first and diamond-deduplicated by canonical
realpath. Includes must remain inside the root grammar directory after symlink resolution; absolute paths, parent traversal,
globs, NUL, missing paths, and directories are rejected.

CLI grammar commands resolve fragments automatically. Programmatic filesystem use is explicit:

```ruby
resolution = Ibex::Frontend::Resolver.new("grammar.y", mode: :extended).resolve
grammar_ir = Ibex::Normalizer.new(resolution, mode: :extended).normalize
resolution.files # canonical DFS dependency closure
```

`Parser#parse` and `Parser#parse_fragment` only parse supplied source and never follow paths. Resolved Grammar IR version 2 stores
the canonical source root, original production locations, and include chains; version-1 output retains its existing shape.
`Resolution` recursively freezes its resolved AST and defensively copied provenance. `ibex diagnose` reports the first
cross-file resolution or fragment syntax failure through its normal text/JSON diagnostic stream; actual filesystem read failures
remain invocation errors on stderr. Rake tasks resolve and validate the complete include graph while the task is defined, so an
invalid graph fails even when an older generated target is newer than the root grammar.

## Rule documentation

Consecutive `##` comments on the immediately preceding lines document a rule:

```text
rule
## Parses an expression.
## Preserves source order.
expression: NUMBER | expression '+' NUMBER
end
```

Indentation before `##` is allowed. A blank line, ordinary `#` comment, block comment, token, or opaque Ruby action breaks the
attachment. Ibex strips `##` and one optional following space while preserving internal lines. Repeated definitions may reuse
the same text; a different later description is a positioned error. Included fragment documentation is retained in resolved
Grammar IR version 2, while version-1 output continues to omit documentation fields.

Render standalone documentation to stdout or atomically to a file:

```sh
ibex doc grammar.y
ibex doc --format=html -o grammar.html grammar.y
ibex doc --format=railroad --mode=extended -o grammar.svg grammar.y
```

Markdown, self-contained accessible HTML, and railroad SVG escape grammar-controlled text. Existing `--railroad=FILE` output
also displays wrapped rule documentation.

For bounded multi-error analysis, use `Parser#parse_with_diagnostics(max_diagnostics: 20)`. Lexical and syntax analysis each
collect at most that limit before the result selects the globally earliest records in source order. Its immutable result has
machine-coded diagnostics and, when recovery reaches EOF, an explicitly partial AST containing later valid constructs. A result
with diagnostics is never successful, and its original source document deliberately keeps `document.ast == nil`.

```sh
ibex diagnose grammar.y
ibex diagnose --format=json --max-diagnostics=10 grammar.y
```

The command exits successfully only for an error-free grammar. Its versioned JSON contract is
`schema/frontend-diagnostics-v1.schema.json`; diagnostic analysis does not generate or execute a parser.

## Pipeline and diagnostics

```sh
ibex diagnose --format=json grammar.y
ibex doc --format=html -o grammar.html grammar.y
ibex fmt --check grammar.y grammar/expression.y
ibex --emit=grammar-ir grammar.y > grammar.json
ibex --from=grammar-ir --emit=automaton-ir grammar.json > automaton.json
ibex --from=automaton-ir -o parser.rb automaton.json
ibex -v --dot=states.dot --mermaid=states.mmd --html=states.html --railroad=grammar.svg grammar.y
ibex --algorithm=lr1 grammar.y
ibex --counterexamples --counterexample-max-tokens=64 --counterexample-max-configurations=100000 grammar.y
ibex explain --state=7 --token=ELSE --format=json grammar.y
ibex --rbs -o parser.rb grammar.y
ibex --rbs --action-source -o parser.rb grammar.y
ibex --manifest -o parser.rb grammar.y
ibex --watch --manifest -o parser.rb grammar.y
ibex --warnings=all,error -C grammar.y
ibex errors --update grammar.y
ibex --messages=grammar.messages grammar.y
ibex --check --rbs grammar.y
ibex samples --count=10 --seed=42 grammar.y
ibex validate-ir grammar.json
ibex compare before.json after.json
ibex migrate-check --format=json grammar.y
ibex migrate-harness -o migration_harness.rb grammar.y
```

Supported construction algorithms are `slr`, `lalr` (default), `ielr`, and canonical `lr1`. LALR and SLR use direct lookahead
propagation over LR(0) states; the representative grammar retains 250 construction states instead of 1,294 canonical states
while producing byte-identical Automaton IR. IELR splits inadequate LALR merges while conservatively retaining compatible ones.
Reports retain precedence-resolved conflicts and distinguish unifying counterexamples from nonunifying reachability witnesses.
Counterexample searches default to
32 tokens and 50,000 explored configurations; `--counterexample-max-tokens=N` and
`--counterexample-max-configurations=N` set positive per-run budgets and request a report.

`ibex explain [--state=N] [--token=NAME] [--format=text|json] [--algorithm=slr|lalr|ielr|lr1]
[--mode=racc|extended] grammar.y` presents only the selected conflicts and their competing derivations. State and token
selectors can be combined, and witness search runs only for matching conflicts. A token canonical grammar name takes priority;
otherwise an exact, unambiguous `display` name is accepted. Valid selectors with no matching conflict produce a successful empty
view. `--mode=extended` enables extended syntax for grammars without a `pragma extended` declaration. The JSON analysis document
is versioned by `schema/explain-v1.schema.json`; diagnostics remain on stderr. The two counterexample budget options are also
accepted by this subcommand.

`--rbs` writes a signature beside the generated parser; `--rbs=FILE` selects another path. `--action-source[=FILE]` additionally
writes a static-check-only Ruby shadow containing the real private semantic-action methods. Its default path replaces the parser
extension with `.actions.rb` (`parser.rb` becomes `parser.actions.rb`). The shadow deliberately contains no runtime require,
parser tables, generated driver, superclass, or `header`/`inner`/`footer` code and must never be loaded or executed. Ibex does
not invoke Steep: add the generated RBS and shadow to an application Steep target and run `steep check` explicitly in application
CI. `--check --rbs --action-source` verifies all three requested generated files without rewriting them. Application methods
supplied as opaque `---- inner` code can be declared by reopening the generated class in an application RBS file.

Parser generation renders every requested output before changing any target, then stages, synchronizes, and publishes companion
files, the parser, and finally an opt-in manifest. `--manifest[=FILE]` writes version-1 JSON beside the parser by default with
canonical input digests, generation options, and output paths, sizes, and SHA-256 digests. `--check --manifest` verifies the
would-be files without rewriting them. A reader that needs a coherent multi-file generation should read the manifest, verify
every listed artifact, and restart from a newly read manifest after any missing file or mismatch.

`--watch` regenerates Ruby file outputs after the root grammar, an included fragment, a failed include path, a message file, or
a repairable output changes. It keeps the last successful generation after an error, suppresses duplicate unchanged errors, and
exits with status 130/143 for `SIGINT`/`SIGTERM`. It cannot be combined with stdin, `--from`, `--check`, or `--check-only`, and
`Ibex::RakeTask` deliberately rejects it. See [ADR
0049](docs/decisions/0049-transactional-generation-and-watch-mode.md) for the publication and reader contracts.

`--warnings=all` prints unused terminals and precedence declarations, unreachable terminals and nonterminals, duplicate
productions, undeclared terminals, and empty-language diagnostics. Add `error` (`--warnings=all,error`, or simply
`--warnings=error`) to make any such diagnostic fail the command.
Action exceptions and `inner` methods point back to their `.y` lines by default. `--line-convert-all` extends that mapping to
`header` and `footer`; `-l` disables every source-line conversion. User-code chunk locations survive Grammar/Automaton IR JSON
round trips, so resumed generation has the same backtraces as direct generation.

`Ibex::Runtime::JSONLTracer.attach(parser, io:)` streams committed shifts, reductions, and recoveries without replacing existing
hooks. `require "ibex/rake_task"` provides timestamp-aware parser generation for Rakefiles. Set
`task.action_source = true` for the default shadow path or assign an explicit String path; the shadow becomes a timestamp-aware
file prerequisite of the parser target. Versioned JSON Schemas are shipped in
`schema/`, and `examples/` contains calculator, JSON, INI, and tiny-language parsers backed only by the standard library.
The static `migrate-check` reports racc-mode syntax, normalization, superclass, and runtime-coupling hazards without executing
grammar code. `migrate-harness` emits a reviewable, empty-by-default child-process differential harness; running it is an
explicit application-code execution boundary.
New pipeline output is Grammar/Automaton IR version 2; version-1 documents remain valid and byte-stable. Upgrade either document
kind with `ibex migrate-ir INPUT --to=2` or write atomically with `-o FILE`. The version-2 contract reserves nullable source,
documentation, expansion, and composed-action metadata; see [ADR 0039](docs/decisions/0039-versioned-ir-v2-migration.md).

## Documentation

- [Grammar reference](docs/grammar-reference.md)
- [racc migration guide](docs/racc-migration.md)
- [Architecture and IR schemas](docs/architecture.md)

## Development

Run all unit, integration, documentation, and optional local racc black-box tests with `bundle exec rake test`; run style checks
with `bundle exec rake lint`. The default `bundle exec rake` runs both. Compatibility tests skip automatically when the `racc`
command is unavailable.

Ibex's grammar frontend is self-hosted. Edit `lib/ibex/frontend/grammar.y`, then regenerate and verify the committed parser with:

```sh
bundle exec rake frontend:generate
bundle exec rake frontend:check
bundle exec ruby -Itest test/frontend/self_host_test.rb
```

Normal library and CLI execution use the generated parser. The handwritten `BootstrapParser` is loaded only by this regeneration
workflow, whose direct dependency graph also works when the generated file is absent. Byte-comparison and AST/error parity tests
prevent generated-source drift.

Fixed-seed property tests exercise SLR, LALR, IELR, and LR(1) pipeline invariants, while versioned Grammar and Automaton IR fixtures
guard byte-stable version-1 reads, version-2 output, and deterministic migration. Intentional fixture updates are documented in
`test/fixtures/ir/README.md`. The
self-authored representative grammar records versioned `ibex_benchmark` artifacts without a timing or memory pass/fail threshold:

```sh
benchmark/pipeline.rb --iterations 1 --runtime-iterations 10 --seed 12345 --output tmp/benchmark-current.json
bundle exec ruby benchmark/verify.rb benchmark/results/v2/2026-07-25-07e46b082245-ruby-4.0.0-arm64-darwin24.json
benchmark/examples.rb --generation-iterations 5 --runtime-iterations 100
```

The current v2 artifact includes stage and runtime observations, peak RSS when the host exposes it, construction strategy and
intermediate/final state counts, plain/compact table sizes, generated bytes, and deterministic digests. Its contract is shipped
as `schema/benchmark-v2.schema.json`; append-only v1 history retains its original canonical-state field. The command prints a
readable report and writes JSON to the requested path; see
[the benchmark guide](benchmark/README.md) for baseline, CI retention, and append-only history policy.

Compact row-displacement tables have a bounded mutation gate. Its dependency set is isolated from supported application Rubies:

```sh
BUNDLE_GEMFILE=gemfiles/mutation.Gemfile bundle install
bundle exec rake quality:mutation
```

The task selects only `Ibex::Tables::Compact#initialize`, runs two workers, and enables the Minitest coverage mapping only for
that process.

Signatures for every Ruby source under `lib/` are generated from rbs-inline annotations and checked with Steep, including the
self-hosted generated parser. To regenerate the committed signature tree and reproduce its validation locally:

```sh
BUNDLE_GEMFILE=gemfiles/Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/Gemfile ruby -e '
  sources = Dir.glob("lib/**/*.rb").sort
  exec("bundle", "exec", "rbs-inline", "--opt-out", "--base=lib", "--output=sig", *sources)
'
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec rbs -r digest -r json -r optparse -r tempfile -I sig validate
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec steep check
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec steep stats
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec ruby tool/type_stats.rb --write
```

CI performs generation in a clean temporary directory and compares the complete trees, so missing source signatures and stale
signature files both fail the build.
<!-- type-stats:start -->
The current whole-library `steep stats` result is 14,296 typed calls and 1,926 untyped calls out of 16,222 (88.1% typed).
The generated signature tree contains 1,994 explicit `untyped` occurrences across 77 files.
<!-- type-stats:end -->

Those boundaries are concentrated in generated-parser reduction values, heterogeneous JSON decoding/serialization, runtime
semantic values and parser-table cells, and embedded user Ruby. Token/location records, the complete grammar AST, parser
classifier state, IR, the public Ruby DSL, bootstrap parser state, analysis, automaton construction, code generators, table
construction, and CLI options use concrete domain types. The committed self-hosted parser remains in the Steep target; no library
directory or generated source is excluded.

Ibex is available under the [MIT License](LICENSE.txt).
