# Compatibility notes

Compatibility observations are recorded here without consulting racc implementation sources or generated source text.

## Observed CLI (2026-07-22)

Black-box command: `racc --help`, version 1.8.1.

Observed options are `-o/--output-file`, `-t/--debug`, obsolete `-g`, `-v/--verbose`, `-O/--log-file`,
`-e/--executable`, `-E/--embedded`, `-F/--frozen`, `--line-convert-all`, `-l/--no-line-convert`,
`-a/--no-omit-actions`, `--superclass`, `-C/--check-only`, `-S/--output-status`, profiling `-P`, internal `-D`,
`--version`, `--runtime-version`, `--copyright`, and `--help`.

Ibex accepts that option set. `-P` and `-D` are accepted compatibility no-ops because they expose generator internals rather
than parser behavior. Frozen string literals are always emitted, so `-F` is also a no-op. Ibex's default output is `<input>.rb`
rather than racc's observed `<input>.tab.rb`; `-o` is portable between both tools.

## Behavioral probes

Self-authored grammars are compiled independently and the generated files are executed without inspecting them. Current probes
cover arithmetic precedence, empty rules, string tokens, `convert`, `no_result_var`, inline actions, dangling-else `expect`, and
a generated 500-production grammar. Precedence-resolved conflicts remain in Automaton IR diagnostics but are not counted in CLI
warnings or `expect`, matching the observed calculator behavior.

An inline action's own `val[0]` was observed as `nil`; its result occupies one value position visible to the final action. The
grammar reference confirms that `convert` takes a quoted string containing Ruby source: for example `NUM ':number'` emits the
symbol expression, while `NUM '"number"'` emits a Ruby string token.
