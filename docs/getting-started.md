---
title: Getting started
description: Install Ibex, generate a first parser, and choose a grammar mode.
---

# Getting started

Ibex turns a racc-compatible grammar into a Pure Ruby LR parser. This guide
gets from an installed gem to a working parser before explaining the optional
extended surface.

## Install the generator

```sh
gem install ibex
```

For an application that only runs generated parsers, install `ibex-runtime`
instead. A project can add either dependency with `bundle add ibex` or
`bundle add ibex-runtime`.

## Generate a calculator

Create `calculator.y` with a class, token declaration, rules, and a small
handwritten pull lexer:

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

Generate and run it:

```sh
ibex -o calculator.rb calculator.y
ruby calculator.rb
# 14
```

Run `ibex --check -o calculator.rb calculator.y` in CI. It compares the
reproducible output without rewriting the committed file.

## Choose a mode

The default mode is the conservative racc migration surface. Add
`pragma extended` immediately after the class header, or pass
`--mode=extended`, when the grammar needs EBNF groups, imports, generated
lexers, typed trees, or other opt-in features. The [grammar reference](grammar-reference.md)
lists the exact syntax and the [maturity audit](policy/maturity.md) records support
level per API.

## Next steps

- [Migrate an existing racc grammar](guides/racc-migration.md).
- [Configure grammar-owned and invocation-owned settings](concepts/configuration-model.md).
- [Inspect a grammar locally in the Playground](https://ydah.github.io/ibex/playground/).
- [Read the runtime and grammar reference](grammar-reference.md).
