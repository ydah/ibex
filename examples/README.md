# Ibex examples

These examples pair an Ibex grammar with a small lexer built from Ruby's
standard-library `StringScanner`. Generate any example from the repository
root, then run the generated file:

```sh
bundle exec ruby -Ilib exe/ibex examples/calculator.y
bundle exec ruby -Ilib examples/calculator.rb "2 + 3 * (4 - 1)"
```

The generated `.rb` file is disposable. The `.y` file is the maintained
source.

## Included grammars

- `calculator.y` evaluates integer arithmetic with parentheses.
- `json.y` parses JSON values into Ruby Hashes, Arrays, Strings, numbers,
  booleans, and `nil`. Its lexer delegates JSON string-unescaping to Ruby's
  standard-library JSON implementation while the Ibex grammar builds every
  JSON value and container.
- `ini.y` parses sections and key/value entries into a nested Hash.
- `tiny_language.y` parses assignments, arithmetic, and `print` statements,
  then executes the resulting small AST.

The JSON, INI, and tiny-language runners read standard input:

```sh
printf '%s\n' '{"name":"Ibex","values":[1,true,null]}' |
  bundle exec ruby -Ilib examples/json.rb
```

## Lexer integration pattern

Ibex deliberately does not generate a lexer. Each parser implements
`next_token`, returning `[token, semantic_value]`; `false` or `nil` marks EOF.
The examples demonstrate two useful `StringScanner` patterns:

1. calculator, JSON, and tiny language scan the source incrementally and
   return one token per `next_token` call;
2. INI tokenizes line-oriented records into a small queue before parsing.

Quoted grammar terminals such as `'+'` are returned as Strings. Declared bare
tokens such as `NUMBER` are returned as Symbols. A production lexer can retain
offset or line information alongside its own semantic values and use that
information in application diagnostics; these examples keep the contract
small enough to read in one file.
