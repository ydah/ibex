# Ibex

[![Gem Version](https://badge.fury.io/rb/ibex.svg)](https://badge.fury.io/rb/ibex)
[![CI](https://github.com/ydah/ibex/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/ibex/actions/workflows/main.yml)

Ibex is a Pure Ruby LR parser generator. It reads racc-compatible grammar
files, generates parsers with the familiar `do_parse` / `yyparse` API, and
requires no C or Java extension.

> [!IMPORTANT]
> Ibex is pre-1.0. The current v1.0 decision is
> [**HOLD**](docs/release-readiness.md) because the published error UX evidence
> still needs independent review. Compatibility, scale, and public performance
> baseline evidence pass. Cold generation and new-instance runtime still trail
> Racc's Ruby backend, but absolute parity is diagnostic rather than a v1.0
> release gate. Compatible mode is the stable baseline; opt-in features have
> the maturity levels documented in the [stability policy](docs/stability.md).

- Try grammar analysis in the
  [browser playground](https://ydah.github.io/ibex/playground/).
- Start with the [grammar reference](docs/grammar-reference.md).
- Build lossless and incremental tooling with the
  [Red/Green CST guide](docs/cst.md).
- Migrate an existing parser with the
  [racc migration guide](docs/racc-migration.md).
- Analyze an external Bison grammar with the
  [Bison import guide](docs/bison-import.md).
- Browse the [API reference](https://ydah.github.io/ibex/api/).

The playground runs in a local Web Worker. It does not upload grammar source
or execute semantic action bodies.

## At a glance

| Concern | Ibex default |
| --- | --- |
| Grammar input | racc-compatible `.y` source |
| Construction | Direct LALR(1) |
| Generated tables | Compact, immutable Ruby data |
| Parser API | Pull parsing with `do_parse` / `yyparse` |
| Generated dependency | The separately versioned `ibex-runtime` gem |
| Ruby support | Ruby 3.0 or later |
| Extensions | Disabled unless `pragma extended` or `--mode=extended` is used |
| Concrete syntax | Stable format-v6 Red/Green CST with `pragma cst` |
| Semantic actions | Opaque during generation and analysis; executed only by a running parser |

The generator and runtime are deliberately separate:

```text
grammar.y + lexer contract
          |
          v
        ibex  -----> parser.rb --------> ibex-runtime
          |
          +--------> optional RBS, IR, reports, diagrams, and docs
```

Use `-E` when a generated parser must embed the runtime instead of depending
on `ibex-runtime`.

## Quick start from a checkout

Clone the repository and install its locked development dependencies:

```sh
git clone https://github.com/ydah/ibex.git
cd ibex
bundle install
```

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

Generate and run the parser without installing local gems:

```sh
bundle exec ruby -Ilib exe/ibex calculator.y
bundle exec ruby -Ilib calculator.rb
# 14
```

With the local gems installed, the equivalent commands are:

```sh
ibex calculator.y
ruby calculator.rb
```

Ibex writes `calculator.rb`, uses compact tables, and generates a parser that
requires `ibex-runtime`. Use `-o PATH` to choose the output, `--table=plain`
for inspectable Hash rows, `--check` to compare without rewriting, or `-E` to
embed the runtime.

## Generated parser contract

### Tokens and lexers

A handwritten pull lexer implements `next_token` and returns:

```ruby
[token, value]
[token, value, location]
```

`false` or `nil` marks EOF. Bare grammar tokens use Ruby symbols such as
`:NUM`; quoted terminals use strings such as `'+'`. Locations are
application-owned objects and remain optional.

Existing lexers can use the [lexer migration guide](docs/lexer-migration.md).
Extended grammars may instead generate a streaming lexer from declarative
regular-expression rules.

### Semantic actions and locations

Actions read RHS values through `val`. `@1`, `@2`, and so on address parallel
semantic locations, while `@$` is the span of the current reduction. Action
source remains opaque Ruby: Ibex preserves its source mapping but does not
parse, type-check, or sandbox it.

### Parse lifecycles and errors

Generated parsers support:

- `do_parse` and yielding `yyparse` for racc-compatible pull parsing;
- `push(token, value, location)` and `finish(location:)` for caller-driven
  streaming;
- structured `Ibex::ParseError` values containing the token, expected tokens,
  state, location, and spelling suggestions;
- yacc-style recovery through `on_error`, `yyerror`, `yyerrok`, and
  `yyaccept`; and
- immutable, shareable generated tables.

Use one parser instance per concurrent parse. Isolated runtime sessions and
resource budgets are opt-in when application code needs explicit execution
boundaries.

## Choose a grammar mode

| Mode | Use it for | Contract |
| --- | --- | --- |
| `default` | Existing racc grammars and conservative migrations | Compatible syntax and runtime behavior |
| `extended` | New grammars that need composition or generated tooling | Preview, explicitly enabled |

Enable extended syntax with `pragma extended` in the grammar or
`--mode=extended` on the command line:

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

Extended mode includes nested EBNF groups, named references, parameterized and
inline rules, multiple entry points, canonical fragment imports, generated
lexers, CST or typed `Data` AST generation, declarative recovery, semantic
types, and grammar-declared tests. These features do not silently change the
default compatible frontend. Maturity is assigned per API: format-v6 batch
Red/Green CST is Stable, while the wider extended grammar surface remains
Preview and incremental CST sessions remain Experimental.

## Choose a construction algorithm

| Option | When to use it |
| --- | --- |
| `--algorithm=lalr` | Default direct LALR(1) construction |
| `--algorithm=slr` | Grammars whose FOLLOW-set reductions are sufficient |
| `--algorithm=ielr` | Preview backend for conflicts introduced by LALR state merging |
| `--algorithm=lr1` | Canonical LR(1) analysis when the larger automaton is acceptable |

`--suggest-ielr` checks whether IELR removes an unexpected LALR conflict and
prints an advisory note when it does.
That note does not change the selected algorithm or exit status.

Conflict freedom is not the same as a proof of unambiguity. `ibex check
--ambiguity` searches for a concrete sentence with two interpretations, but
the token and configuration budgets make every result explicitly bounded.

## Integrate generation into a build

Treat grammar source as the input and generated Ruby as a reproducible build
artifact:

```sh
ibex --warnings=error -o lib/calculator.rb grammar/calculator.y
ibex --warnings=error --check -o lib/calculator.rb grammar/calculator.y
```

The first command writes the parser. The second is suitable for CI and fails
when the committed output is stale without modifying it.

Rake projects can declare the dependency directly:

```ruby
require "ibex/rake_task"

Ibex::RakeTask.new("lib/calculator.rb") do |task|
  task.grammar = "grammar/calculator.y"
  task.options = ["--warnings=error"]
end
```

The task follows the grammar's fragment dependency closure. Multi-output
generation can additionally publish a manifest containing input identities,
output paths, sizes, and SHA-256 digests. Generation renders all requested
outputs before publishing them; `--watch` retains the last successful output
when a later edit is invalid.

Applications that only execute generated parsers need `ibex-runtime`, not the
generator. To build and install both current local gems:

```sh
gem build ibex-runtime.gemspec
gem build ibex.gemspec
gem install ./ibex-runtime-0.1.0.gem
gem install ./ibex-0.1.0.gem
```

## Diagnose, verify, and inspect

| Goal | Command |
| --- | --- |
| Promote grammar warnings to errors | `ibex --warnings=error -C grammar.y` |
| Collect structured frontend diagnostics | `ibex diagnose --format=json grammar.y` |
| Explain one conflict | `ibex explain --state=7 --token=ELSE grammar.y` |
| Search for a concrete ambiguity | `ibex check --ambiguity --algorithm=lr1 grammar.y` |
| Run grammar-declared tests | `ibex test --coverage=100 grammar.y` |
| Check canonical formatting | `ibex fmt --check grammar.y` |
| Render grammar documentation | `ibex doc --format=html -o grammar.html grammar.y` |
| Emit Automaton IR | `ibex --emit=automaton-ir grammar.y > automaton.json` |
| Independently verify Automaton IR | `ibex verify --strict automaton.json` |
| Search two grammars for a bounded difference | `ibex equiv old.y new.y` |
| Propose independently checked conflict repairs | `ibex fix --messages=grammar.messages grammar.y` |
| Classify grammar and automaton changes | `ibex diff old.y new.y` |
| Measure deterministic grammar structure | `ibex metrics grammar.y` |
| Import Bison structure for analysis | `ibex import bison parser.y -o parser.analysis.y` |
| Explain a selected Bison conflict | `ibex explain --state=N parser.y` |
| Simulate table behavior without actions | `ibex debug automaton.json NUMBER PLUS NUMBER` |
| Generate bounded terminal sentences | `ibex samples --strategy=coverage grammar.y` |
| Differential-fuzz all LR algorithms | `ibex fuzz --coverage-guided grammar.y` |

| Minimize an externally reproducible failure | `ibex reduce --command='./fails' tokens.json` |
| Check a racc migration | `ibex migrate-check grammar.y` |
| Start the language server | `ibex lsp --stdio` |

Built-in CLI diagnostics support `--lang=en|ja` and `IBEX_LANG`. Unknown or
partially translated locales fall back to English without emitting another
warning. These built-in message IDs are separate from the user-owned `E00xx`
syntax-error catalog.

Grammar IR, Automaton IR, generated table formats, diagnostic JSON, runtime
events, coverage, and manifests are versioned contracts. Reports can also be
rendered as text, DOT, Mermaid, HTML, railroad SVG, samples, or conflict
counterexamples.

## Safety boundaries and non-goals

- Frontend parsing, diagnosis, formatting, documentation, LSP, static
  migration checks, IR validation, independent verification, table
  simulation, sentence generation, and differential fuzzing do not execute
  semantic actions or user-code sections.
- Generated parsers, grammar-declared tests, and explicit migration harnesses
  do execute application Ruby. They are not sandboxes.
- Fragment imports are confined to the declared source root and reject
  traversal, cycles, and symlink escapes.
- Counterexample, ambiguity, sample, repair, and runtime-budget searches are
  bounded. Exhausting a budget is distinct from finding no witness within it.
- Bison import is analysis-only. C actions remain opaque, Ruby generation is
  refused, and repair is refused when unsupported directives make the
  recovered production graph incomplete.
- Ibex generates deterministic LR parsers. It does not provide GLR or
  generalized ambiguity handling. Incremental CST sessions are syntax-only
  and experimental.
- racc compatibility is a migration surface, not a claim that every generated
  parser is a byte-for-byte or adapter-free replacement.
- Preview and experimental features may have weaker compatibility guarantees
  than the default mode.

## Documentation by task

| When you need to... | Start here |
| --- | --- |
| Write a grammar or use the runtime | [Grammar reference](docs/grammar-reference.md) |
| Build, edit, serialize, or incrementally update syntax trees | [Red/Green CST guide](docs/cst.md) and [migration guide](docs/cst-migration.md) |
| Learn from executable grammars | [Examples](examples/README.md) |
| Migrate from racc | [racc migration guide](docs/racc-migration.md) |
| Analyze Bison grammar structure | [Bison import guide](docs/bison-import.md) |
| Adapt a handwritten lexer | [Lexer migration guide](docs/lexer-migration.md) |
| Configure an editor or LSP client | [Editor setup](docs/editor-setup.md) |
| Understand the pipeline, IR, algorithms, or tables | [Architecture](docs/architecture.md) |
| Check API maturity and deprecation rules | [Stability policy](docs/stability.md) |
| Evaluate readiness, performance, or error UX | [Release readiness](docs/release-readiness.md), [benchmarks](benchmark/README.md), and [error UX](docs/error-ux.md) |
| Contribute or run every quality gate | [Development guide](docs/development.md) |
| Review implementation decisions | [Architecture decision records](docs/decisions/README.md) |

The published documentation separates the
[compatibility contract](https://ydah.github.io/ibex/compatibility/),
[opt-in extensions](https://ydah.github.io/ibex/extensions/), and
[experimental surfaces](https://ydah.github.io/ibex/experimental/). The
[grammar gallery](https://ydah.github.io/ibex/gallery/) contains executable
examples whose declared tests reach complete production coverage.

## Development

The [development guide](docs/development.md) contains frontend regeneration,
RBS/Steep validation, grammar coverage, browser checks, mutation analysis, and
workflow lint commands. The default local gate is:

```sh
bundle install
bundle exec rake
```

<!-- type-stats:start -->
The current whole-library `steep stats` result is 23,468 typed calls and 2,945 untyped calls out of 26,413 (88.9% typed).
The generated signature tree contains 2,237 explicit `untyped` occurrences across 117 files.
<!-- type-stats:end -->

Performance measurements are evidence, not portable scores or CI timing
thresholds. Follow the [benchmark guide](benchmark/README.md) to reproduce and
compare results under the same environment and configuration.

Ibex is available under the [MIT License](LICENSE.txt).
