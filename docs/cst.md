# Red/Green concrete syntax trees

<!-- stable:batch-cst:v1 -->

`pragma cst` generates a lossless, error-tolerant syntax tree alongside the
ordinary semantic result. Regenerate the parser with the current generator to
receive parser-table format v6 and this API. Batch parsing, typed views,
editing, diffing, and `ibex_cst` serialization are Stable for v1; syntax-only
incremental sessions are Experimental.

```text
class Calculator
pragma cst
token NUM PLUS
lexer
  skip /[[:space:]]+/
  NUM /[0-9]+/ { lexeme.to_i }
  PLUS '+'
end
rule
start: expression
expression: NUM PLUS NUM @node Addition(left, operator, right)
end
```

## Parsing and tree shape

`parse_with_syntax` runs semantic actions normally and returns both results:

```ruby
result = Calculator.new.parse_with_syntax("1 + 2", file: "input.txt")
value = result.value
root = result.syntax_root
diagnostics = result.diagnostics
```

This is a trusted application runtime path. Parser production actions and
generated lexer actions execute, and loading the generated Ruby file may run
`header`, `inner`, or `footer` code. `parse_with_syntax` is not a sandbox.

`parse`, `do_parse`, and `yyparse` keep their semantic return values.
`parser.syntax_root` exposes the most recent syntax root. Every successful root
has this physical shape:

```text
source_file
├── selected start-symbol node
└── $eof
```

The immutable Green layer stores kind ids, source bytes, trivia, flags, widths,
and children without parents or absolute positions. It is Ractor-shareable.
The Red `SyntaxNode`/`SyntaxToken` layer adds lazy parent, child-index, offset,
span, and location navigation for one occurrence. Equal Green values can
therefore appear at several positions without sharing Red coordinates.

`root.to_source` reconstructs the consumed bytes exactly. Early `yyaccept`
marks `root.incomplete_input?` and reconstructs the consumed prefix.

## Trivia and coordinates

Select trivia ownership while generating:

- `leading` owns skipped text on the following token;
- `balanced` owns text through the first newline on the preceding token and
  the remainder on the following token;
- `drop` omits trivia.

Pass the policy explicitly when needed:

```sh
ibex --cst-trivia=leading grammar.y
ibex --cst-trivia=balanced grammar.y
ibex --cst-trivia=drop grammar.y
```

`attach` is accepted as an alias for `leading`. EOF owns final leading trivia.
`drop` trees deliberately reject span, location, and incremental APIs because
their offsets cannot describe the original source.

Spans are zero-based, half-open byte ranges. `SourceText#position` and
`#location` convert them to one-based Unicode-scalar lines and columns while
preserving byte offsets.

## Typed syntax views

An `@node` annotation generates a view in `Parser::Syntax` without changing the
physical tree:

```ruby
addition = Calculator::Syntax::Addition.cast(
  result.syntax_root.children.fetch(0).children.fetch(0)
)
addition.left
addition.operator
addition.right
```

Accessors use normalized physical RHS slots. Lowered repetitions add element
enumerators; separated lists also expose separators. These views are distinct
from generated `Parser::AST` Data values: syntax views retain punctuation and
trivia, while AST values are semantic-action results.

## Errors and repair

Lexical failure, yacc recovery, panic discard, and bounded repair all produce a
tree. Inspect `diagnostics`, `contains_error?`, error nodes, missing tokens, and
Green flags. Inserted tokens are zero-width `missing_token` values. Discarded
input remains under error nodes or `skipped_tokens` trivia. An unrecoverable
parse uses `synthetic_root`.

## Persistent editing and diffing

Editing returns a new Red root and path-copies only changed ancestors:

```ruby
old_root = result.syntax_root
first = old_root.first_token
new_root = first.with_text("10")
edits = Ibex::Runtime::CST::Diff.text_edits(old_root, new_root)
new_source = old_root.source_text.apply(edits)
```

Nodes support `replace_with`, `with_child`, `insert_child`, and `remove_child`.
Tokens support `replace_with`, `with_text`, `with_leading`, and
`with_trailing`. `SyntaxRewriter` performs bottom-up kind dispatch;
`SyntaxEditor` applies several occurrence-addressed replacements in one pass.
`SyntaxAnnotation` marks one occurrence and excludes annotated Green values
from interning.

## Incremental syntax sessions

Incremental parsing is Experimental and deliberately syntax-only:

```ruby
source = Ibex::Runtime::CST::SourceText.new("1 + 2", file: "input.txt")
session = Calculator.incremental_session(source)
result = session.edit([
  Ibex::Runtime::CST::TextEdit.new(
    start: 4,
    delete_length: 1,
    insert_text: "3"
  )
])
```

The initial parse and every edit suppress parser production actions.
`SyntaxResult` therefore has `syntax_root`, `diagnostics`, and `reused_ratio`,
but no semantic value. Generated lexer actions still run because they define
token emission and lexer-state changes. Run a normal parse separately when a
semantic value or side effect is required.

Consequently, `parse_syntax` and `incremental_session` are syntax-only but not
"no user code" APIs. Loading the generated class may execute user sections,
and lexer actions may perform arbitrary Ruby side effects. Treat the generated
class as trusted application code. A future nonexecuting syntax profile would
require a declarative built-in-only lexer and no `header`, `inner`, or `footer`
sections; the current API does not provide that profile.

Sessions require `SourceText`, a generated lexer, format-v6 CST metadata, and
non-`drop` trivia. Handwritten token sources and push input are unsupported.
Parser actions that alone switch lexer state are also unavailable because the
syntax-only contract forbids executing them.

The default Stage B path relexes soundly from the beginning, validates old
token boundaries/states, and directly reuses only subtrees whose LR state,
follow token, flags, width, and damage range are safe. Pass `blender: false` to
retain the Stage A full LR drive. `ResourceLimits` bounds decomposition and
memo bytes; a bound failure deterministically falls back to the fresh token
stream. Observe `cst_built`, `cst_reuse`, and `cst_fallback` runtime events for
metrics.

## Serialization

`ibex_cst` schema v1 is independent from Grammar IR:

```ruby
tables = Calculator.parser_tables
json = Ibex::Runtime::CST::Serialize.dump(
  session.result.syntax_root,
  grammar_digest: tables.fetch(:grammar_digest),
  table_format: tables.fetch(:format_version),
  state_count: tables.fetch(:state_count),
  production_count: tables.fetch(:production_count),
  memo: session.parse_memo
)
loaded = Ibex::Runtime::CST::Serialize.load(
  json,
  grammar_digest: tables.fetch(:grammar_digest),
  state_count: tables.fetch(:state_count),
  production_count: tables.fetch(:production_count)
)
```

Valid UTF-8 bytes use JSON strings; other bytes use canonical Base64 objects.
Loading rebuilds widths, aggregate flags, and descendant counts. A grammar
digest mismatch raises `ValidationError`. State or production count mismatch
silently discards only the optional parse memo. Annotations are session-local
and cannot be serialized.

## Invariants and test coverage

The Red/Green contract is continuously exercised by the following repository
tests:

| Invariant | Automated evidence |
| --- | --- |
| I1 consumed-input fidelity | `test/runtime/cst_fidelity_property_test.rb` is PT1 over random grammars and valid, lexical-error, recovery, repair, and early-accept inputs; `test/fixtures/cst/runtime-paths-v1.json` fixes every error/trivia path, including long unmatched remainders and repair deletion. |
| I2 Green purity | `test/runtime/cst_green_test.rb` checks derived-only immutable state and Ractor shareability; `test/codegen/cst_characterization_test.rb` keeps semantic values outside syntax children. |
| I3 lazy Red navigation | `test/runtime/cst_red_test.rb` checks occurrence-local memoization, offsets, parents, cursors, and deterministic traversal. |
| I4 determinism | PT3 in `test/runtime/cst_green_test.rb` compares cache-on/off structure, source, and dump; PT6 in `test/runtime/cst_serialize_test.rb` checks byte-stable dump/load/dump; generated Ruby and RBS have golden tests. |
| I5 unchanged action contract | `test/codegen/cst_contract_test.rb` compares CST/no-CST `parse`, `do_parse`, `yyparse`, hooks, observer order, and non-CST table shape; characterization and obsolete-CST-table rejection regressions remain active. |
| I6 sharing boundary | PT5 in `test/runtime/cst_green_test.rb` checks Green shareability and concurrent Ractor reads; editing and parser-table tests keep Red/session state occurrence-owned. |
| I7 versioned contracts | `test/runtime/cst_serialize_test.rb`, `test/runtime/table_format_test.rb`, and `test/packaging/schema_files_test.rb` cover schema validation, memo compatibility, old table readers, and schema packaging. |
| I8 type soundness | CI regenerates the `sig/` tree, runs Steep and RBS validation, and rejects a type-statistics regression. |

`test/runtime/cst_incremental_property_test.rb` is the large PT2 authority. Its
fixed seed generates four grammar shapes and executes 20,000 random edits
through Stage A plus 20,000 through Stage B, comparing fresh syntax sessions in
Green structure, bytes, flags, diagnostics, and memo cardinality after every
edit. `test/runtime/cst_incremental_test.rb` adds focused stateful-lexer,
fallback, sharing, minimal-diff, action-suppression, no-value, and unsupported
configuration cases.

See [the migration guide](cst-migration.md) for removed tree-shape changes and
[the stability policy](stability.md) for support levels.
