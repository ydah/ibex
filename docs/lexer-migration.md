---
title: Lexer migration
description: Move a handwritten lexer or adopt the explicit generated lexer contract.
---

# Migrating a handwritten lexer

The generated lexer uses the same `next_token` contract as a handwritten pull
lexer, so migration can stay inside the grammar file.

Given a handwritten scanner:

```ruby
def next_token
  @scanner.skip(/\s+/)
  return false if @scanner.eos?
  return [:NUMBER, Integer(text, 10)] if (text = @scanner.scan(/\d+/))
  return [punctuation, nil] if (punctuation = @scanner.scan(/[()+]/))
end
```

declare the equivalent rules:

```text
pragma extended
token NUMBER
lexer
  skip /\s+/
  NUMBER /\d+/ { |text| Integer(text, 10) }
  on /[()+]/ { |text| emit text, nil }
end
```

Then remove the source/scanner initialization and call generated
`parse(source, file: ...)`. Existing semantic actions, token names, values,
parser hooks, and location consumers do not change. A custom `parse` wrapper
may retain an application-specific default filename:

```ruby
def parse(source, file: "(expression)") = super
```

Map scanner modes to `state NAME do ... end`, transitions to `push_state` and
`pop_state`, and parser-controlled modes to `self.lexer_state = :NAME`.
Patterns are tried only in the active state.

Before deleting a handwritten lexer, compare its token triples with
`parser.lex(source).next_token`, especially at newlines and multibyte text.
Generated locations expose grapheme and byte columns plus half-open byte
offsets. String, IO, and Fiber sources share the same output even when chunks
split a token.

The generator rejects empty matches and invalid regex syntax. Its
`lexer_redos` lint only detects common risky nested quantifiers; it cannot make
arbitrary Ruby regular expressions safe. Review patterns and bound untrusted
input.
