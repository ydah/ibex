# Ibex

[![Gem Version](https://badge.fury.io/rb/ibex.svg)](https://badge.fury.io/rb/ibex) [![CI](https://github.com/ydah/ibex/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/ibex/actions/workflows/main.yml)

Ibex is a Pure Ruby LR parser generator. It accepts racc-compatible grammar files, generates parsers with the familiar
`do_parse` / `yyparse` API, and requires no C or Java extension. Its staged Grammar IR and Automaton IR can also drive extended
EBNF syntax, diagnostics, visualizations, and alternate LR construction algorithms.

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

Generated actions can read the location parallel to `val[0]`, `val[1]`, and so on as `@1`, `@2`, and so on; `@$` is the
immutable span of the current reduction. Empty and middle actions use a zero-width span at the current lookahead. Location-less
tokens remain supported and produce `nil` entries.

Bare grammar tokens normally use Ruby symbols (`:NUM`), and quoted grammar tokens use strings (`'+'`). A yielding source can call
`yyparse(receiver, method_name)` where the receiver method yields the same two- or three-element token arrays, including the
optional location.

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it to use yacc-style `error` recovery.
Semantic actions can call `yyerror`, `yyerrok`, or `yyaccept`, and `expected_tokens` reports valid lookaheads in the current state.
`push(token, value, location)` / `finish(location:)` provide caller-driven streaming. The default `ParseError` exposes token,
expected-token, state, location, and spelling-suggestion attributes and renders source lines with a caret when available.
Parser subclasses can also override `on_shift(token_id, value, state)`,
`on_reduce(production_id, values, result)`, and `on_error_recover(token_id, value, value_stack)` as no-op-by-default observers.
Ordinary shifts and the synthetic recovery-token shift use separate hooks; observer return values never replace semantic values.

## Extended mode

`--mode=extended` enables optional, repeated, and separated values plus named references. A grammar can make the same choice
locally with `pragma extended` immediately after its `class` header:

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
end
```

Extended declarations can add human-readable diagnostics and generated action types:

```text
display NUM "number"
type NUM "Integer"
type expr "AST::Expression"
```

The value conventions are `nil` or a value for `?`, and arrays for `*`, `+`, `separated_list`, and
`separated_nonempty_list`. Parenthesized sequences and alternatives can be nested; multi-item groups produce an Array value.
Text, DOT, and HTML automaton reports label lowered helper symbols with these source-level EBNF expressions.

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
while user-code markers and repeated blocks remain separate. `Token#to_h`, AST output, and normalized IR are unchanged.

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
ibex --emit=grammar-ir grammar.y > grammar.json
ibex --from=grammar-ir --emit=automaton-ir grammar.json > automaton.json
ibex --from=automaton-ir -o parser.rb automaton.json
ibex -v --dot=states.dot --mermaid=states.mmd --html=states.html --railroad=grammar.svg grammar.y
ibex --algorithm=lr1 grammar.y
ibex --counterexamples --counterexample-max-tokens=64 --counterexample-max-configurations=100000 grammar.y
ibex explain --state=7 --token=ELSE --format=json grammar.y
ibex --rbs -o parser.rb grammar.y
ibex --warnings=all,error -C grammar.y
ibex errors --update grammar.y
ibex --messages=grammar.messages grammar.y
ibex --check --rbs grammar.y
ibex samples --count=10 --seed=42 grammar.y
ibex validate-ir grammar.json
ibex compare before.json after.json
```

Supported construction algorithms are `slr`, `lalr` (default), and canonical `lr1`. Reports retain precedence-resolved
conflicts and distinguish unifying counterexamples from nonunifying reachability witnesses. Counterexample searches default to
32 tokens and 50,000 explored configurations; `--counterexample-max-tokens=N` and
`--counterexample-max-configurations=N` set positive per-run budgets and request a report.

`ibex explain [--state=N] [--token=NAME] [--format=text|json] [--algorithm=slr|lalr|lr1]
[--mode=racc|extended] grammar.y` presents only the selected conflicts and their competing derivations. State and token
selectors can be combined, and witness search runs only for matching conflicts. A token canonical grammar name takes priority;
otherwise an exact, unambiguous `display` name is accepted. Valid selectors with no matching conflict produce a successful empty
view. `--mode=extended` enables extended syntax for grammars without a `pragma extended` declaration. The JSON analysis document
is versioned by `schema/explain-v1.schema.json`; diagnostics remain on stderr. The two counterexample budget options are also
accepted by this subcommand.

`--rbs` writes a signature beside the generated parser; `--rbs=FILE` selects another path. Application methods supplied as
opaque `---- inner` code can be declared by reopening the generated class in an application RBS file.

`--warnings=all` prints unused terminals and precedence declarations, unreachable terminals and nonterminals, duplicate
productions, undeclared terminals, and empty-language diagnostics. Add `error` (`--warnings=all,error`, or simply
`--warnings=error`) to make any such diagnostic fail the command.
Action exceptions and `inner` methods point back to their `.y` lines by default. `--line-convert-all` extends that mapping to
`header` and `footer`; `-l` disables every source-line conversion. User-code chunk locations survive Grammar/Automaton IR JSON
round trips, so resumed generation has the same backtraces as direct generation.

`Ibex::Runtime::JSONLTracer.attach(parser, io:)` streams committed shifts, reductions, and recoveries without replacing existing
hooks. `require "ibex/rake_task"` provides timestamp-aware parser generation for Rakefiles. Versioned JSON Schemas are shipped in
`schema/`, and `examples/` contains calculator, JSON, INI, and tiny-language parsers backed only by the standard library.
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
git diff --exit-code -- lib/ibex/frontend/generated_parser.rb
bundle exec ruby -Itest test/frontend/self_host_test.rb
```

Normal library and CLI execution use the generated parser. The handwritten `BootstrapParser` is loaded only by this regeneration
workflow, whose direct dependency graph also works when the generated file is absent. Byte-comparison and AST/error parity tests
prevent generated-source drift.

Fixed-seed property tests exercise SLR, LALR, and LR(1) pipeline invariants, while versioned Grammar and Automaton IR fixtures
guard byte-stable version-1 reads, version-2 output, and deterministic migration. Intentional fixture updates are documented in
`test/fixtures/ir/README.md`. The
self-authored representative grammar records versioned `ibex_benchmark` artifacts without a timing or memory pass/fail threshold:

```sh
benchmark/pipeline.rb --iterations 1 --runtime-iterations 10 --seed 12345 --output tmp/benchmark-current.json
bundle exec ruby benchmark/verify.rb benchmark/results/v1/2026-07-25-c55ff20e58e6-ruby-4.0.0-arm64-darwin24.json
benchmark/examples.rb --generation-iterations 5 --runtime-iterations 100
```

The artifact includes stage and runtime observations, peak RSS when the host exposes it, canonical and final state counts,
plain/compact table sizes, generated bytes, and deterministic digests. Its contract is shipped as
`schema/benchmark-v1.schema.json`. The command prints a readable report and writes JSON to the requested path; see
[the benchmark guide](benchmark/README.md) for baseline, CI retention, and append-only history policy.

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
The current whole-library `steep stats` result is 6,885 typed calls and 804 untyped calls out of 7,689 (89.5% typed).
The generated signature tree contains 889 explicit `untyped` occurrences across 27 files.
<!-- type-stats:end -->

Those boundaries are concentrated in generated-parser reduction values, heterogeneous JSON decoding/serialization, runtime
semantic values and parser-table cells, and embedded user Ruby. Token/location records, the complete grammar AST, parser
classifier state, IR, the public Ruby DSL, bootstrap parser state, analysis, automaton construction, code generators, table
construction, and CLI options use concrete domain types. The committed self-hosted parser remains in the Steep target; no library
directory or generated source is excluded.

Ibex is available under the [MIT License](LICENSE.txt).
