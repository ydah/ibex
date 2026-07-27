# Ibex

[![Gem Version](https://badge.fury.io/rb/ibex.svg)](https://badge.fury.io/rb/ibex)
[![CI](https://github.com/ydah/ibex/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/ibex/actions/workflows/main.yml)

Ibex is a Pure Ruby LR parser generator. It accepts racc-compatible grammar
files, generates parsers with the familiar `do_parse` / `yyparse` API, and
requires no C or Java extension.

Beyond compatibility mode, Ibex provides opt-in EBNF syntax, generated lexers,
CST and typed AST generation, structured diagnostics, conflict analysis,
versioned Grammar/Automaton IR, and SLR, LALR, IELR, and canonical LR(1)
construction.

- Try it in the [browser playground](https://ydah.github.io/ibex/playground/).
- Browse the [API reference](https://ydah.github.io/ibex/api/).
- Read the [grammar reference](docs/grammar-reference.md).
- Migrate an existing parser with the [racc migration guide](docs/racc-migration.md).

The playground runs locally in a Web Worker. Grammar source is not uploaded,
and semantic action bodies are not executed.

## Requirements and installation

Ibex supports Ruby 3.0 or later. Generated parsers normally depend on the
separately versioned `ibex-runtime` package, whose runtime has no third-party
gem dependencies.

From a source checkout:

```sh
bundle install
bundle exec rake
```

Build and install the local gems to put `ibex` on your `PATH`:

```sh
gem build ibex.gemspec
gem build ibex-runtime.gemspec
gem install ./ibex-runtime-0.1.0.gem
gem install ./ibex-0.1.0.gem
```

Applications that only execute generated parsers may install `ibex-runtime`
without the generator. Pass `-E` when generating a dependency-free parser with
the runtime embedded.

## Quick start

Save this grammar as `calculator.y`:

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

Generate and run the parser:

```sh
ibex calculator.y
ruby calculator.rb
# 14
```

From a checkout without installing the gems:

```sh
bundle exec ruby -Ilib exe/ibex calculator.y
bundle exec ruby -Ilib calculator.rb
```

Ibex generates compact parser tables by default. Use `--table=plain` for
inspectable Hash rows, `--check` to compare generated output without rewriting
it, and `-E` to embed the runtime.

## Grammar and runtime basics

A handwritten pull lexer implements `next_token` and returns `[token, value]`
or `[token, value, location]`; `false` or `nil` marks EOF. Bare grammar tokens
use Ruby symbols such as `:NUM`, while quoted terminals use strings such as
`'+'`.

Generated parsers support:

- `do_parse` and yielding `yyparse` for racc-compatible pull parsing;
- `push(token, value, location)` and `finish(location:)` for caller-driven
  streaming;
- structured `Ibex::ParseError` values with token, expected-token, state,
  location, and spelling-suggestion data;
- yacc-style `error` recovery through `on_error`, `yyerror`, `yyerrok`, and
  `yyaccept`; and
- immutable, shareable generated tables. Use a separate parser instance for
  each concurrent parse.

Semantic actions read RHS values through `val` and may read parallel locations
as `@1`, `@2`, and so on. `@$` is the span of the current reduction.

See the [grammar reference](docs/grammar-reference.md) for the complete lexer,
semantic action, location, recovery, hook, tracing, repair, and resource-limit
contracts. Existing handwritten lexers can follow the
[lexer migration guide](docs/lexer-migration.md).

## Extended grammars

Enable extended syntax with `--mode=extended` or `pragma extended`:

```text
class ExtendedParser
pragma extended
token NUM KEY VALUE
rule
  arguments : separated_list(NUM, ',')
  sum       : NUM:left '+' NUM:right { result = left + right }
  maybe     : NUM?
  many      : NUM*
  groups    : (KEY VALUE)+
  list(X)   : X | list(X) ',' X
  %inline signed(X): '-' X { result = -val[1] }
  negative  : signed(NUM)
end
```

Extended mode includes nested EBNF groups, named references, parameterized
rules, inline rules, multiple entry points, strict warnings, grammar fragments,
declarative error recovery, generated action types, and grammar-declared
tests.

It can also generate a lexer beside the parser:

```text
pragma extended
token NUMBER WORD
lexer
  skip /\s+/
  NUMBER /\d+/ { |text| Integer(text, 10) }
  WORD /\p{L}+/
end
```

Generated lexers use longest match and declaration order for ties. Their
`parse` method accepts String, IO, or Fiber input, including chunks that split
tokens. Lexical states are explicit and generated locations include grapheme,
byte-column, and byte-offset data.

Action-free grammars may opt into immutable concrete syntax trees with
`pragma cst`. Alternatives annotated with `@node` instead generate typed
`Data` AST nodes plus exhaustive visitor and listener APIs. These features and
their generated RBS contracts are documented in the
[grammar reference](docs/grammar-reference.md).

## Command overview

| Goal | Command |
| --- | --- |
| Generate a parser | `ibex -o parser.rb grammar.y` |
| Check generated files | `ibex --check -o parser.rb grammar.y` |
| Promote warnings to errors | `ibex --warnings=error -C grammar.y` |
| Diagnose grammar errors | `ibex diagnose --format=json grammar.y` |
| Format without changing semantics | `ibex fmt --check grammar.y` |
| Run grammar-declared tests | `ibex test --coverage=100 grammar.y` |
| Render grammar documentation | `ibex doc --format=html -o grammar.html grammar.y` |
| Search for concrete ambiguity | `ibex check --ambiguity --algorithm=lr1 grammar.y` |
| Explain a selected conflict | `ibex explain --state=7 --token=ELSE grammar.y` |
| Emit Grammar IR | `ibex --emit=grammar-ir grammar.y > grammar.json` |
| Emit Automaton IR | `ibex --emit=automaton-ir grammar.y > automaton.json` |
| Inspect table behavior safely | `ibex debug automaton.json NUMBER PLUS NUMBER` |
| Start the language server | `ibex lsp --stdio` |
| Check a racc migration | `ibex migrate-check grammar.y` |

Ambiguity and counterexample searches are explicitly bounded. Exhausting a
search budget is reported separately from finding a witness or finding none
within the configured bounds.

Generation can additionally emit RBS, a static-check-only semantic-action
shadow, a transactional output manifest, DOT/Mermaid/HTML automata, railroad
diagrams, samples, and conflict counterexamples. `--watch` regenerates from
the root grammar and its fragment dependency closure while retaining the last
successful output after an error.

The full option and output contracts live in the
[grammar reference](docs/grammar-reference.md). The
[architecture guide](docs/architecture.md) documents the staged IR pipeline,
construction algorithms, clean-room boundary, and runtime table contract.

## Tooling and observability

Ibex tooling analyzes grammar text and versioned IR without executing semantic
actions or user-code sections:

- the lossless frontend retains comments, whitespace, heredocs, and opaque
  Ruby while rendering the original source byte-for-byte;
- `diagnose`, `fmt`, documentation, LSP, migration checks, and table simulation
  operate across the same parser and resolver boundaries;
- grammar fragments resolve within the root directory with cycle, traversal,
  and symlink-escape protection; and
- transactional generation renders every requested output before publishing
  the parser and optional manifest.

Runtime observers expose immutable parser events without exposing parser
stacks or application object identities. JSONL tracing and deterministic
coverage commands support complete event streams, and optional bounded repair
and resource limits remain disabled unless explicitly configured.

## Documentation

| Topic | Document |
| --- | --- |
| Grammar syntax, CLI, and runtime contracts | [Grammar reference](docs/grammar-reference.md) |
| Migration from racc | [racc migration guide](docs/racc-migration.md) |
| Handwritten lexer migration | [Lexer migration guide](docs/lexer-migration.md) |
| Editor and LSP setup | [Editor setup](docs/editor-setup.md) |
| Pipeline, IR, algorithms, and tables | [Architecture](docs/architecture.md) |
| Stability and deprecation | [Stability policy](docs/stability.md) |
| Current v1.0 decision and evidence | [Release readiness](docs/release-readiness.md) |
| Reproducible error UX evidence | [Error UX](docs/error-ux.md) |
| Executable example grammars | [Examples](examples/README.md) |
| Reproducible performance evidence | [Benchmark guide](benchmark/README.md) |
| Contributor workflow and quality gates | [Development guide](docs/development.md) |
| Implementation design history | [Architecture decision records](docs/decisions/README.md) |

The published documentation separates the
[compatibility contract](https://ydah.github.io/ibex/compatibility/),
[opt-in extensions](https://ydah.github.io/ibex/extensions/), and
[experimental surfaces](https://ydah.github.io/ibex/experimental/). The
[grammar gallery](https://ydah.github.io/ibex/gallery/) contains executable
examples whose declared tests reach 100% production coverage in CI.

## Project status

The current v1.0 readiness decision is **HOLD**. The
[release-readiness report](docs/release-readiness.md) records public-gem
migration evidence, reproducible performance comparisons, scale evidence,
error UX results, and remaining blockers. The
[stability policy](docs/stability.md) identifies stable, preview, and
experimental surfaces independently of that release decision.

## Development

See the [development guide](docs/development.md) for the complete contributor
workflow and quality-gate boundaries.

Run the default test and style suite:

```sh
bundle install
bundle exec rake
```

Frontend regeneration, RBS/Steep validation, grammar coverage, site checks,
mutation analysis, and workflow lint commands live in the development guide.

<!-- type-stats:start -->
The current whole-library `steep stats` result is 17,219 typed calls and 2,266 untyped calls out of 19,485 (88.4% typed).
The generated signature tree contains 2,357 explicit `untyped` occurrences across 87 files.
<!-- type-stats:end -->

Performance measurements are observations rather than CI timing thresholds.
Use the [benchmark guide](benchmark/README.md) to reproduce, validate, and
compare artifacts under the same environment and configuration.

Ibex is available under the [MIT License](LICENSE.txt).
