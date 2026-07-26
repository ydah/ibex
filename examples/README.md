# Ibex examples

These examples pair an Ibex grammar with either the declarative lexer DSL or a
small handwritten lexer. Generate any example from the repository
root, then run the generated file:

```sh
bundle exec ruby -Ilib exe/ibex examples/calculator.y
bundle exec ruby -Ilib examples/calculator.rb "2 + 3 * (4 - 1)"
```

The generated `.rb` file is disposable. The `.y` file is the maintained
source.

Each grammar also keeps accept/reject source examples beside its rules. Run all
of them without generating repository files. The task also requires 100%
production coverage from the declared cases:

```sh
bundle exec rake grammar:test
```

## Included grammars

- `calculator.y` evaluates integer arithmetic with parentheses.
- `csv.y` parses rows and quoted fields with a generated lexer.
- `json.y` parses JSON values into Ruby Hashes, Arrays, Strings, numbers,
  booleans, and `nil`. It demonstrates the generated lexer, including conversion
  actions and punctuation emission.
- `ini.y` parses sections and key/value entries into a nested Hash.
- `tiny_language.y` parses assignments, arithmetic, and `print` statements,
  then executes the resulting small AST.

The JSON, INI, and tiny-language runners read standard input:

```sh
printf '%s\n' '{"name":"Ibex","values":[1,true,null]}' |
  bundle exec ruby -Ilib examples/json.rb
```

## Lexer integration patterns

The JSON example declares `lexer ... end`; generated `parse` accepts String,
IO, and Fiber input. Rules are anchored, choose the longest match, and use
declaration order for ties.

Handwritten lexers remain useful when an application already owns tokenization.
They implement `next_token`, returning `[token, semantic_value]`; `false` or
`nil` marks EOF. The remaining examples demonstrate two `StringScanner`
patterns:

1. calculator and tiny language scan the source incrementally and
   return one token per `next_token` call;
2. INI tokenizes line-oriented records into a small queue before parsing.

Quoted grammar terminals such as `'+'` are returned as Strings. Declared bare
tokens such as `NUMBER` are returned as Symbols. A production lexer can retain
offset or line information alongside its own semantic values and use that
information in application diagnostics; these examples keep the contract
small enough to read in one file.
