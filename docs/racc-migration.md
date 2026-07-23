# Migrating from racc

Ibex targets grammar-file compatibility, generated parser public API compatibility, and the main racc CLI options. It does not
copy racc's internal table arrays, internal method names, native runtime, or generated source layout.

## Typical migration

1. Run `ibex -o parser.rb grammar.y` in place of `racc -o parser.rb grammar.y`.
2. Change the generated-file runtime dependency from deployment packaging only; application calls to `do_parse`, `yyparse`,
   `next_token`, `on_error`, `token_to_str`, `yyerror`, `yyerrok`, and `yyaccept` remain the same.
3. Use `-E` if the generated parser must be a single file with no installed Ibex gem.
4. Keep the default `--mode=racc` until intentionally adopting EBNF or names. Extended grammars can make that choice locally by
   placing `pragma extended` immediately after their class header instead of requiring `--mode=extended` at each invocation.

## CLI mapping

| Option | Ibex behavior |
|---|---|
| `-o`, `--output-file` | Select generated parser path |
| `-t`, `--debug`; `-g` | Generate a debug-capable parser; `-g` is accepted as an obsolete alias |
| `-v`, `-O` | Write the independent state report and optional path |
| `-e [RUBY]` | Add a shebang and executable permission |
| `-E`, `--embedded` | Embed the Pure Ruby runtime |
| `-F`, `--frozen` | Accepted; Ibex always emits frozen-string magic comments |
| `--rbs[=FILE]` | Ibex extension; emit a generated parser signature |
| `--warnings=all,error` | Ibex extension; display or promote structured grammar diagnostics |
| `--line-convert-all`, `-l` | Map header/inner/footer too, or disable all source mapping |
| `-a` | Generate methods for implicit actions |
| `--superclass` | Override the grammar superclass |
| `-C`, `-S` | Check only; show pipeline status |
| `-P`, `-D` | Accepted no-ops because they expose generator internals |
| `--version`, `--runtime-version`, `--copyright`, `--help` | Informational output |

Ibex defaults to `<input>.rb`; racc 1.8.1 was observed to default to `<input>.tab.rb`. Use `-o` for portable scripts.
By default, semantic actions and `inner` methods report grammar-file lines while `header` and `footer` retain generated-file
lines. `--line-convert-all` maps every user-code section; `-l` maps none. The mapping is retained through IR JSON resumption.

## Compatibility baseline

The compatibility claims above were checked on 2026-07-22 against racc 1.8.1 using only its public documentation, `racc --help`,
and black-box execution. Ibex does not inspect racc implementation files or generated source. Self-authored probes compare
observable results for arithmetic precedence, empty rules, string tokens, `convert`, `no_result_var`, inline actions,
dangling-else `expect`, error recovery, source-line conversion, and a generated 500-production grammar.

Precedence-resolved conflicts remain visible in Automaton IR but are excluded from the CLI conflict count and `expect`. Error
recovery probes compare result values and the public `on_error` arguments. These tests skip when the `racc` executable is absent.

## Known differences

- Generated source and internal table representations are intentionally different.
- `.output` report formatting is independent and contains additional resolved-conflict and witness data.
- An undeclared invalid token was observed to enter racc's `error` production without `on_error`. Ibex intentionally reports the
  unknown lookahead through `on_error` first, then recovers if the callback returns. Declared invalid tokens match in the
  black-box recovery probe.
- `require "racc/parser"` replacement and previously generated racc parser table compatibility are out of scope.
