# Ibex

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

Ibex does not generate a lexer. A pull parser implements `next_token` and returns `[token, value]`; `false` or `nil` marks EOF.
Bare grammar tokens normally use Ruby symbols (`:NUM`), and quoted grammar tokens use strings (`'+'`). A push source can call
`yyparse(receiver, method_name)` where the receiver method yields the same pairs.

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it to use yacc-style `error` recovery.
Semantic actions can call `yyerror`, `yyerrok`, or `yyaccept`, and `expected_tokens` reports valid lookaheads in the current state.
Parser subclasses can also override `on_shift(token_id, value, state)`,
`on_reduce(production_id, values, result)`, and `on_error_recover(token_id, value, value_stack)` as no-op-by-default observers.
Ordinary shifts and the synthetic recovery-token shift use separate hooks; observer return values never replace semantic values.

## Extended mode

`--mode=extended` enables optional, repeated, and separated values plus named references:

```text
rule
  arguments : separated_list(NUM, ',') { result = val[0] }
  sum       : NUM:left '+' NUM:right { result = left + right }
  maybe     : NUM?
  many      : NUM*
  some      : NUM+
  pairs     : (KEY VALUE)*
end
```

The value conventions are `nil` or a value for `?`, and arrays for `*`, `+`, `separated_list`, and
`separated_nonempty_list`. Parenthesized sequences and alternatives can be nested; multi-item groups produce an Array value.

## Pipeline and diagnostics

```sh
ibex --emit=grammar-ir grammar.y > grammar.json
ibex --from=grammar-ir --emit=automaton-ir grammar.json > automaton.json
ibex --from=automaton-ir -o parser.rb automaton.json
ibex -v --dot=states.dot --html=states.html grammar.y
ibex --algorithm=lr1 grammar.y
ibex --counterexamples --counterexample-max-tokens=64 --counterexample-max-configurations=100000 grammar.y
ibex --rbs -o parser.rb grammar.y
ibex --warnings=all,error -C grammar.y
```

Supported construction algorithms are `slr`, `lalr` (default), and canonical `lr1`. Reports retain precedence-resolved
conflicts and distinguish unifying counterexamples from nonunifying reachability witnesses. Counterexample searches default to
32 tokens and 50,000 explored configurations; `--counterexample-max-tokens=N` and
`--counterexample-max-configurations=N` set positive per-run budgets and request a report. `--rbs` writes a signature beside the
generated parser; `--rbs=FILE` selects another path. Application methods supplied as opaque `---- inner` code can be declared by
reopening the generated class in an application RBS file.

`--warnings=all` prints unused terminals, unreachable nonterminals, duplicate productions, undeclared terminals, and empty-language
diagnostics. Add `error` (`--warnings=all,error`, or simply `--warnings=error`) to make any such diagnostic fail the command.

## Documentation

- [Grammar reference](docs/grammar-reference.md)
- [racc migration guide](docs/racc-migration.md)
- [Architecture and IR schemas](docs/architecture.md)
- [Compatibility observations](docs/compat-notes.md)
- [Phase 10 extensions](docs/phase10-extensions.md)

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

Signatures for every Ruby source under `lib/` are generated from rbs-inline annotations and checked with Steep, including the
self-hosted generated parser. To regenerate the committed signature tree and reproduce its validation locally:

```sh
BUNDLE_GEMFILE=gemfiles/Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/Gemfile ruby -e '
  sources = Dir.glob("lib/**/*.rb").sort
  exec("bundle", "exec", "rbs-inline", "--opt-out", "--base=lib", "--output=sig", *sources)
'
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec rbs -r digest -r json -r optparse -I sig validate
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec steep check
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec steep stats
```

CI performs generation in a clean temporary directory and compares the complete trees, so missing source signatures and stale
signature files both fail the build. The current whole-library `steep stats` result is 3,631 typed calls and 426 untyped calls out
of 4,057 (89.5% typed). The generated signature tree contains 387 explicit `untyped` occurrences across 16 files. Those boundaries
are concentrated in generated-parser reduction values, heterogeneous JSON decoding/serialization, runtime semantic values and
parser-table cells, and embedded user Ruby. Token/location records, the complete grammar AST, parser classifier state, IR,
the public Ruby DSL, bootstrap parser state, analysis, automaton construction, code generators, table construction, and CLI
options use concrete domain types. The committed self-hosted parser remains in the Steep target; no library directory or generated
source is excluded.

Ibex is available under the [MIT License](LICENSE.txt).
