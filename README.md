# Ibex

[![Gem](https://badge.fury.io/rb/ibex.svg)](https://rubygems.org/gems/ibex)
[![CI](https://github.com/ydah/ibex/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/ibex/actions/workflows/main.yml)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-4ade80)](https://ydah.github.io/ibex/)
[![License](https://img.shields.io/badge/license-MIT-4ade80.svg)](LICENSE.txt)

Ibex is a Pure Ruby LR parser generator. It reads racc-compatible grammar
files, generates parsers with the familiar `do_parse` / `yyparse` API, and
requires no native extension.

The shortest path is the [Getting Started guide](https://ydah.github.io/ibex/getting-started/):
install the gem, try the calculator grammar, and then choose the compatible or
extended contract you need. You can also [inspect a grammar in the browser](https://ydah.github.io/ibex/playground/)
without uploading its source.

## Release status

Ibex is pre-1.0. The v1.0 publication decision is on hold pending an
independent review of the published error-experience evidence; feature
development continues. The default compatible mode and its current IR
contracts are the conservative adoption baseline. See the [release status](https://ydah.github.io/ibex/project/status/)
and [stability policy](docs/stability.md) for the human-readable boundaries.

## Install

Add the generator to an application or tool project:

```sh
gem install ibex
# or, in a Gemfile:
bundle add ibex
```

Applications that only run generated parsers can depend on the smaller runtime:

```sh
bundle add ibex-runtime
```

## First parser

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
ibex -o calculator.rb calculator.y
ruby calculator.rb
# 14
```

The generated parser uses compact immutable tables and depends on
`ibex-runtime`. Use `-E` when a single self-contained generated file is more
convenient. Use `--check` in CI to detect stale generated output.

## Choose a contract

| Surface | Use it for | Maturity |
| --- | --- | --- |
| Compatible mode | Existing racc grammars and conservative migrations | Stable baseline |
| Extended mode | EBNF, imports, generated lexers, trees, types, and tooling | Preview; explicit opt-in |
| Browser playground and incremental CST sessions | Local analysis and evaluation | Preview/Experimental; bounded |

The default frontend remains unchanged unless a grammar opts into
`pragma extended` or the command line uses `--mode=extended`. Read the
[grammar reference](https://ydah.github.io/ibex/docs/grammar-reference/),
[racc migration guide](https://ydah.github.io/ibex/docs/racc-migration/), and
[maturity audit](https://ydah.github.io/ibex/docs/maturity/) before adopting a
Preview or Experimental surface.

## Trust boundary

Static frontend, formatting, documentation, LSP, IR, verification, and
browser analysis treat grammar actions and user sections as opaque source.
Generated parsers and semantic parses execute application Ruby and are not
sandboxes. The playground runs in a local Web Worker, does not upload grammar
source, and never executes parser actions or user-code sections. Its limits and
non-goals are documented in the [playground guide](https://ydah.github.io/ibex/playground/).

## Where to go next

- [Documentation hub](https://ydah.github.io/ibex/docs/) — task-oriented entry points.
- [Grammar gallery](https://ydah.github.io/ibex/gallery/) — executable examples with declared tests.
- [API reference](https://ydah.github.io/ibex/api/) — generated Ruby API documentation.
- [Configuration model](https://ydah.github.io/ibex/docs/configuration-model/) — grammar-owned and invocation-owned settings.
- [Project status and evidence](https://ydah.github.io/ibex/project/) — release, roadmap, and bounded claims.
- [Contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md) — community workflow.

## Development

Clone the repository only when you need to contribute or run the complete
quality suite:

```sh
git clone https://github.com/ydah/ibex.git
cd ibex
bundle install
bundle exec rake
npm ci
npm run test:site
```

The [development guide](https://ydah.github.io/ibex/docs/development/) lists
the focused frontend, type, evidence, browser, and workflow checks.

## Decisions and evidence

The public reference also indexes the [direct IELR decision](docs/direct-ielr-decision.md),
[direct multi-entry decision](docs/direct-multi-entry-decision.md),
[verifier trust boundary](docs/verifier-trust-boundary.md), and the
[error-experience review status](docs/error-ux-review-status-v1.json). These
records scope claims to their evidence and revision; they do not change the
compatible installation path above.

Ibex is available under the [MIT License](LICENSE.txt).
