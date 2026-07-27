# CST Red/Green migration

Regenerating a `pragma cst` parser with parser-table format v6 opts it into the
Red/Green CST. Existing generated parsers using formats v1 through v5 continue
to run through the legacy CST implementation and emit one deprecation warning
per parser instance beginning in 0.2.

Regenerate with the same command used for the grammar, for example:

```sh
ibex grammar.y -o parser.rb
```

The legacy result classes remain supported through the 0.3 series and are
first eligible for removal in 0.4, subject to the autocorrect prerequisite in
the [stability policy](stability.md).

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

These are the only incompatible shapes found by the legacy characterization
suite. `deconstruct` continues to return syntax children and
`deconstruct_keys` retains the compatibility keys. Typed field keys are added
from `@node` slot metadata.

## Legacy public API inventory

The P0 inventory below records every public member of the legacy values and
where the pre-migration tests used it. Formats v1–v5 retain these classes
unchanged; the right column is the format-v6 replacement.

| Legacy value and members | Characterized use | Format-v6 replacement |
| --- | --- | --- |
| `CST::Trivia#text`, `#location`, `#to_h` | leading/trailing trivia assertions | `GreenTrivia#text` and `#kind`; obtain absolute location from the owning Red token |
| `CST::Token#symbol`, `#value`, `#location`, `#leading_trivia` | terminal names, lexer action values, positions, skipped text | `SyntaxToken#kind_name`/`#symbol`, `#text`, `#location`, and `#green.leading`; semantic lexer values stay in the normal action/value path |
| `CST::Token#kind`, `#children`, `#deconstruct`, `#deconstruct_keys`, `#to_h` | error classification and pattern matching | integer `#kind`, `#error?`/`#missing?`, empty `#deconstruct`, and Red `#deconstruct_keys` |
| `CST::Missing` | bounded-repair insertion checks | `SyntaxToken#missing?`, `GreenToken#expected_kind`, and `CONTAINS_MISSING` |
| `CST::Error#reason` | lexical, syntax, delete, and discard checks | `SyntaxToken#error?`, `SyntaxNode#error?`, diagnostics, and Green error/skipped flags |
| `CST::Node#symbol`, `#production_id`, `#children`, `#location`, `#trailing_trivia` | root/reduction shape, source position, final trivia | `SyntaxNode#symbol`, syntax kinds/slot metadata, `#children`, `#location`; EOF leading trivia is the canonical file-tail owner |
| `CST::Node#each`, `#deconstruct`, `#deconstruct_keys`, `#to_h`, `#with_trailing_trivia` | enumeration, pattern matching, final-trivia attachment | Red navigation/pattern matching and persistent `with_leading`/`with_trailing` token edits |

The inventory is executable in
`test/codegen/cst_characterization_test.rb`: it fixes the old root, final
trivia, semantic token/action overlay, pattern keys, `Error`, `Missing`, and
recovery shapes. The new pure-syntax behavior is tested alongside it. The
semantic-value removals in the table are the C1 change; the `source_file` root
is C2.

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

Format v6 additionally provides typed `Parser::Syntax` views, persistent
path-copy editing, annotations, structural text diffing, `ibex_cst` v1
serialization, and syntax-only incremental sessions. These APIs have no
equivalent on the legacy mixed semantic/syntax tree. See the
[CST guide](cst.md) for examples and the incremental action contract.
