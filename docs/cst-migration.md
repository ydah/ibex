# CST Red/Green migration

The runtime supports only the current format-v6 Red/Green representation for
`pragma cst`. CST parser tables from formats v1 through v5, boolean
`cst: true` tables without structured metadata, and all v1-v5 non-CST tables
fail before the first token is read and instruct the application to regenerate.

Regenerate with the same command used for the grammar, for example:

```sh
ibex grammar.y -o parser.rb
```

Upgrade the generator and runtime together, regenerate the parser, and update
consumers to the current APIs below. The removed `CST::Trivia`, `CST::Token`,
`CST::Missing`, `CST::Error`, and `CST::Node` constants are not defined.

## Parsing

Use `parse_with_syntax` when both the semantic result and syntax are needed:

```ruby
result = parser.parse_with_syntax(source, file: "input.txt")
value = result.value
root = result.syntax_root
diagnostics = result.diagnostics
```

`parse`, `do_parse`, and `yyparse` keep returning the semantic result. After a
CST parse, `syntax_root` exposes the most recently built Red root.

## Changed tree shape

The new root is always `source_file`:

```text
source_file
├── selected start-symbol node
└── $eof
```

The EOF token owns final trivia. Code that previously treated the returned CST
as the start node should use `result.syntax_root.children.fetch(0)`.

The legacy implementation exposed semantic values inside an actionless
parent. For example, an action-bearing `term` could appear as a `CST::Token`
whose symbol was `"term"` and whose value was the action result. Format v6
always exposes the physical `term` syntax node in that position. Read the
semantic result from `result.value`; syntax children never contain semantic
values.

These are the primary incompatible shapes found by the migration
characterization suite. `deconstruct` continues to return syntax children and
`deconstruct_keys` retains the compatibility keys. Typed field keys are added
from `@node` slot metadata.

## Removed public API mapping

The inventory below records the removed values and their format-v6
replacements.

| Removed value and members | Previous use | Format-v6 replacement |
| --- | --- | --- |
| `CST::Trivia#text`, `#location`, `#to_h` | leading/trailing trivia assertions | `GreenTrivia#text` and `#kind`; obtain absolute location from the owning Red token |
| `CST::Token#symbol`, `#value`, `#location`, `#leading_trivia` | terminal names, lexer action values, positions, skipped text | `SyntaxToken#kind_name`/`#symbol`, `#location`, and `#leading_trivia`; compatibility `#value` returns the same source bytes as `#text`, while semantic lexer values stay in the normal action/value path |
| `CST::Token#kind`, `#children`, `#deconstruct`, `#deconstruct_keys`, `#to_h` | error classification and pattern matching | integer `#kind`, `#error?`/`#missing?`, empty `#children`/`#deconstruct`, and compatibility pattern/hash keys |
| `CST::Missing` | bounded-repair insertion checks | `SyntaxToken#missing?`, `GreenToken#expected_kind`, and `CONTAINS_MISSING` |
| `CST::Error#reason` | lexical, syntax, delete, and discard checks | `SyntaxToken#error?`, `SyntaxNode#error?`, diagnostics, and Green error/skipped flags |
| `CST::Node#symbol`, `#production_id`, `#children`, `#location`, `#trailing_trivia` | root/reduction shape, source position, final trivia | `SyntaxNode#symbol`, `#children`, `#location`, and compatibility `#trailing_trivia`; `#production_id` is the `-1` sentinel because kinds/slot metadata replace occurrence-local production identity |
| `CST::Node#each`, `#deconstruct`, `#deconstruct_keys`, `#to_h`, `#with_trailing_trivia` | enumeration, pattern matching, final-trivia attachment | Red `Enumerable`/pattern/hash methods; persistent trivia changes use the owning token's `with_leading`/`with_trailing` |

Current pure-syntax shape and compatibility accessors are executable in
`test/codegen/cst_characterization_test.rb`. Rejection of obsolete CST table
shapes is covered by `test/runtime/table_format_test.rb` and
`test/codegen/cst_runtime_integration_test.rb`. The semantic-value removal is
the C1 change; the `source_file` root is C2.

## Trivia

`--cst-trivia=attach` remains accepted and means `leading`.

- `leading`: skipped lexer text belongs to the next token.
- `balanced`: text through the first newline belongs to the preceding token,
  with the remainder leading the next token.
- `drop`: trivia is omitted; source-coordinate and incremental APIs raise
  because offsets no longer correspond to the original source.

Use `to_source` for a binary-exact reconstruction. On early `yyaccept`,
`incomplete_input?` is true and `to_source` is the consumed prefix.

## Errors and repair

Lexical failures, yacc recovery, panic discards, and bounded repair return a
syntax result rather than changing the semantic action contract. Inspect
`diagnostics`, `contains_error?`, `each_error`, missing tokens, and Green flags
for skipped input. Unrecoverable input is retained under `synthetic_root`.

## New capabilities

Format v6 provides typed `Parser::Syntax` views, persistent
path-copy editing, annotations, structural text diffing, `ibex_cst` v1
serialization, and syntax-only incremental sessions. These APIs have no
equivalent on the removed mixed semantic/syntax tree. Batch CST, views,
editing, and serialization are Stable; incremental sessions remain
Experimental. See the [CST guide](cst.md) for examples and the incremental
action contract.
