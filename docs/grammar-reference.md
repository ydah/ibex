# Grammar reference

Ibex's default `racc` mode accepts the compatible grammar described here. `--mode=extended` adds the explicitly marked syntax;
it is never inferred in compatible mode.

## File structure

```text
class Namespace::Parser < OptionalSuperclass
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

The action scanner handles nested braces, quoted/backtick strings and interpolation, `%q/%Q/%w/%W/%i/%I/%x/%r/%s`, regular
expressions, comments, character literals, and unquoted, single-quoted, double-quoted, or backtick heredocs. Indented, squiggly,
interpolated, and multiple heredocs on one opener line are supported. See [lexer coverage](lexer-coverage.md).

## Runtime errors

The default `on_error(token_id, value, value_stack)` raises `Ibex::ParseError`. Override it and return to allow an `error`
production to recover. Unknown external token objects receive a temporary negative internal id, remain printable through
`token_to_str`, and always invoke `on_error` before recovery is attempted.

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
references inside a group are rejected because the group is lowered behind one outer value slot.

## Strict diagnostics

Grammar IR retains structured diagnostics for undeclared or unused terminals, unreachable nonterminals, duplicate productions,
and a start symbol that cannot derive any terminal sentence. They remain silent by default for compatibility. `--warnings=all`
prints them, `--warnings=all,error` or `--warnings=error` promotes them to command failures, and `--warnings=none` explicitly
suppresses them.

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

The builder also provides `options`, `expect`, `start`, `convert`, `user_code`, `ref(as:)`, `optional`, `star`, `plus`,
`separated_list`, and `inline`.
