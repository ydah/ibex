# Migrating from racc

Ibex targets grammar-file compatibility, generated parser public API compatibility, and the main racc CLI options. It does not
copy racc's internal table arrays, internal method names, native runtime, or generated source layout.

## Typical migration

1. Run `ibex migrate-check grammar.y` and resolve any errors. Use `--format=json` for CI.
2. Generate a reviewable parity harness with `ibex migrate-harness -o migration_harness.rb grammar.y`, add explicit token
   cases, and run it inside an isolation boundary appropriate for the grammar code.
3. Run `ibex -o parser.rb grammar.y` in place of `racc -o parser.rb grammar.y`.
4. Change the generated-file runtime dependency from deployment packaging only; application calls to `do_parse`, `yyparse`,
   `next_token`, `on_error`, `token_to_str`, `yyerror`, `yyerrok`, and `yyaccept` remain the same.
5. Use `-E` if the generated parser must be a single file with no installed Ibex gem.
6. Keep the default `--mode=racc` until intentionally adopting EBNF or names. Extended grammars can make that choice locally by
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
| `--action-source[=FILE]` | Ibex extension; emit a non-executable Steep shadow of semantic methods |
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
For static action checking, combine `--rbs --action-source`; configure the generated `.rbs` and `.actions.rb` in the
application's Steep target, and run Steep separately. The shadow is check-only input and must not replace or be required by the
runtime parser.

`migrate-check` never executes semantic actions or `header`/`inner`/`footer` code. `migrate-harness` also only writes source. The
generated harness is the explicit execution step: after reviewed cases are added, it invokes both generators and executes both
generated parsers in bounded child processes. This is not a sandbox; use a container or VM for untrusted grammar code. See
[ADR 0056](decisions/0056-static-racc-migration-and-generated-harness.md).

## Compatibility baseline

The compatibility claims above were checked on 2026-07-22 against racc 1.8.1 using only its public documentation, `racc --help`,
and black-box execution. Ibex does not inspect racc implementation files or generated source. Self-authored probes compare
observable results for arithmetic precedence, empty rules, string tokens, `convert`, `no_result_var`, inline actions,
dangling-else `expect`, error recovery, source-line conversion, and a generated 500-production grammar.

Precedence-resolved conflicts remain visible in Automaton IR but are excluded from the CLI conflict count and `expect`. Error
recovery probes compare result values and the public `on_error` arguments. These tests skip when the `racc` executable is absent.

Application-defined parser initializers do not have to call `super`; the runtime completes its isolated session state on first
use while retaining application-owned instance variables. During parsing, the historical `@vstack` and `@racc_vstack` names
both refer to the live semantic-value stack for read compatibility. They are internal aliases: applications may inspect them
while tokenizing but must not mutate, replace, or retain them across parser sessions.

## Known differences

- Generated source and internal table representations are intentionally different.
- `.output` report formatting is independent and contains additional resolved-conflict and witness data.
- An undeclared invalid token was observed to enter racc's `error` production without `on_error`. Ibex intentionally reports the
  unknown lookahead through `on_error` first, then recovers if the callback returns. Declared invalid tokens match in the
  black-box recovery probe.
- `require "racc/parser"` replacement and previously generated racc parser table compatibility are out of scope.
