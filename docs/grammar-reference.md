# Grammar reference

Ibex's default `racc` mode accepts the compatible grammar described here. `--mode=extended` or an explicit grammar-file
`pragma extended` adds the marked syntax; extensions are never inferred from a production.

## File structure

```text
class Namespace::Parser < OptionalSuperclass
  pragma extended       # optional; must precede ordinary declarations
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

## Declarations

- `pragma extended` enables extended syntax for this grammar even when the CLI uses its default or explicit `--mode=racc`.
  It must immediately follow the class header, before every ordinary declaration. Unknown, duplicate, and misplaced pragmas
  are positioned errors. The pragma is consumed by the frontend and is not stored in AST or Grammar IR output.

- `token NAME ...` declares terminals for typo diagnostics. It is optional. Uppercase names and quoted strings are terminals;
  lowercase names are nonterminals unless they are `error`.
- A `prechigh ... preclow` block lists precedence from high to low; `preclow ... prechigh` lists it from low to high. Each level
  begins with `left`, `right`, or `nonassoc` followed by one or more terminals.
- `options no_result_var` makes an action's final expression its value. `omit_action_call` is enabled by default;
  `no_omit_action_call` disables it.
- `expect N` suppresses the warning when exactly N unresolved shift/reduce conflicts remain. Conflicts resolved by precedence are
  retained in Automaton IR but are not counted.
- `start name` overrides the first rule as the start symbol.
- `convert ... end` changes external token objects. The second column is a quoted string containing Ruby source, not the value
  itself: `NUM ':number'` uses `:number`, while `NUM '"number"'` uses the String `"number"`.
- Extended mode accepts `display SYMBOL "human name"` to give a terminal or nonterminal a human-facing label without changing
  its identity. Runtime errors, `expected_tokens`, and text, graph, and HTML reports prefer that label.
- Extended mode accepts `type SYMBOL "RBS type"` to describe the symbol's semantic value. Display labels and type spellings
  must be non-empty quoted values on the declaration line. Type spellings are copied as opaque RBS and should be checked with
  normal RBS validation.

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

Actions are opaque Ruby between balanced braces. `val` contains RHS values, `result` begins as `val[0]`, and `_values` is a copy
of the surrounding value stack. With `no_result_var`, the action's evaluated value is used directly. A middle action becomes an
empty helper production and consumes one value position in the enclosing RHS.

Action and `inner` backtraces use the original grammar filename and line by default. `--line-convert-all` applies the same mapping
to `header` and `footer`; `-l` keeps all backtraces on generated-file lines.

The action scanner handles nested braces, quoted/backtick strings and interpolation, `%q/%Q/%w/%W/%i/%I/%x/%r/%s`, regular
expressions, comments, character literals, and unquoted, single-quoted, double-quoted, or backtick heredocs. Indented, squiggly,
interpolated, and multiple heredocs on one opener line are supported. See [lexer coverage](lexer-coverage.md).

## Runtime errors

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it and return to allow an `error`
production to recover. Unknown external token objects receive a temporary negative internal id, remain printable through
`token_to_str`, and always invoke `on_error` before recovery is attempted.

Three optional observer methods default to no-ops. `on_shift(token_id, value, state)` follows each ordinary input-token shift;
`on_reduce(production_id, values, result)` follows a completed semantic action and goto; and
`on_error_recover(token_id, value, value_stack)` follows a successful synthetic `error` shift while retaining the original
unexpected-token context. Hook return values are ignored and exceptions propagate. See
[ADR 0013](decisions/0013-runtime-observation-hooks.md) for exact ordering and snapshot semantics.

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
An unexpected LALR conflict also gets an advisory `--algorithm=lr1` note when canonical LR(1) removes at least one unresolved
conflict; this note does not change generation or exit status.

## State-specific error messages

`ibex errors --update grammar.y` writes `grammar.messages`; use `--update=FILE`, `--algorithm=NAME`, or an IR `--from` option to
select another destination or automaton. The UTF-8 line-oriented format keeps message text separate from generated Ruby:

```text
# ibex-messages v1
state 4
# expected: "(", INT
| An expression must start here.
| Use an integer or an opening parenthesis.
end
```

Blank lines and comments are ignored. Message lines start with `|`; multiple lines are joined with newlines, and `\\`, `\n`,
`\t`, and `\r` are the supported escapes. Re-running `errors --update` retains message bodies for matching state numbers and
moves disappeared states to `removed N` entries for review. State numbers belong to one generated automaton and may change after
grammar, algorithm, option, or generator changes, so always review retained and removed entries after updating.

Pass the reviewed file to Ruby generation with `--messages=grammar.messages`. An active state absent from the current automaton is
an error with an instruction to update; removed entries are ignored. A matching message replaces only the generic syntax-error
sentence, while structured token, location, expected-token, suggestion, source-line, and caret data remain available.

## Analysis and visualizations

`--emit=sets` writes deterministic JSON containing nullable nonterminals and their FIRST and FOLLOW sets. `--dot=FILE` and
`--mermaid=FILE` write automaton graphs. `--html=FILE` writes a self-contained report with state search, conflict highlighting,
and a filter that keeps a selected conflict state and its one-hop neighbors. All three visualizations can be produced while
generating Ruby or when resuming from Automaton IR. `--railroad=FILE` writes a self-contained SVG railroad diagram from normalized
Grammar IR, so it is also available before automaton construction and when resuming from Grammar or Automaton IR.

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
