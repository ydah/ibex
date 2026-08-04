# Runtime ABI evolution

This policy separates durable serialized input, generated parser tables, and
the Ruby runtime API. A version number is a compatibility boundary, not an
indication that every old feature is available in every mode.

<!-- ibex-runtime-abi-contract:start -->
```yaml
contract_version: 1
ir:
  grammar:
    current_writer: 2
    readable: [1, 2]
    migrations: ["1->2"]
    preserve_loaded_version: true
  automaton:
    current_writer: 2
    readable: [1, 2]
    migrations: ["1->2"]
    preserve_loaded_version: true
  lexer:
    current_writer: 1
    readable: [1]
    migrations: []
    standalone: true
    embedded_in_grammar: true
parser_tables:
  current_writer: 6
  readable: [1, 2, 3, 4, 5, 6]
  cst_readable: [6]
  fail_before_input: true
versions:
  generator: "0.2.0"
  runtime: "0.2.0"
  runtime_dependency: "~> 0.2.0"
runtime_paths:
  - ibex.gemspec
  - ibex-runtime.gemspec
  - lib/ibex/runtime.rb
  - lib/ibex/runtime/**/*
  - lib/ibex/tables.rb
  - lib/ibex/tables/**/*
  - sig/ibex/runtime.rbs
  - sig/ibex/runtime/**/*
  - sig/ibex/tables/**/*
  - lib/ibex/codegen/action*.rb
  - lib/ibex/codegen/generated_action_abi.rb
  - lib/ibex/codegen/rbs.rb
  - lib/ibex/codegen/ruby*.rb
  - lib/ibex/codegen/cst_metadata.rb
  - lib/ibex/frontend/generated_parser.rb
  - lib/ibex/ir.rb
  - lib/ibex/ir/**/*
  - sig/ibex/ir.rbs
  - sig/ibex/ir/**/*
  - schema/grammar-ir-v*.schema.json
  - schema/automaton-ir-v*.schema.json
  - schema/lexer-ir-v*.schema.json
  - schema/cst-v*.json
  - test/matrix.yml
assessment:
  states: [compatible, breaking, not_applicable]
  surfaces: [parser_table, grammar_ir, automaton_ir, lexer_ir, runtime_api, embedded_runtime, cst, test_matrix, none]
  abi_choices: [current_contract, new_table_format, new_ir_version, new_runtime_major, sidecar, none]
  regeneration: [required, not_required, not_applicable]
  required_fields: [state, surfaces, abi_choice, regeneration, evidence]
```
<!-- ibex-runtime-abi-contract:end -->

The fenced record above is validated against the constants, schemas, gemspecs,
test declaration, and pull-request policy in this repository. Edit it only as
part of the implementation change that moves the corresponding boundary.

## IR read, write, migration, and freeze policy

| Contract | Current writer | Current readers | Migration | Freeze |
| --- | ---: | --- | --- | --- |
| Grammar IR | v2 | v1, v2 | v1 to v2 only; downgrade is refused | v1 required fields, meanings, ordering, identity, and validation behavior are frozen |
| Automaton IR | v2 | v1, v2 | v1 to v2 only; its embedded Grammar IR is upgraded and its digest is recalculated | published v1 and v2 schemas stay closed |
| Lexer IR | v1 | v1 | none | the closed v1 schema changes only through a new version |

Loading and dumping a Grammar or Automaton IR v1 value preserves its v1 shape.
`Ibex::IR::Migration.to_version` is the only supported upgrade path: it records
unavailable v1 metadata instead of inventing values and is idempotent for v2.
New normalized grammars and new automata use v2. New automata embed Grammar IR
v2. Downgrades and unknown versions are rejected.

Lexer IR v1 is independently versioned. It can be validated and serialized as
a standalone `ibex_ir: lexer` document, and Grammar IR can carry the same
versioned document in its optional `lexer` field. There is no Lexer IR
migration today. Changing lexer rule meaning or its required shape therefore
requires Lexer IR v2; changing only parser construction does not.

The JSON schemas under `schema/` are the published closed shapes. An optional
field may be added to a future version, but an existing closed schema is not
made open to avoid assigning new meaning to an old version.

## Parser-table formats

The generator emits format v6. The current runtime recognizes formats v1
through v6, with these constraints:

| Format | Non-CST runtime contract | CST contract | Current writer |
| ---: | --- | --- | --- |
| v1 | historical two-argument or application action | unsupported | no |
| v2 | adds marked five-argument location action | unsupported | no |
| v3 | adds marked six-argument composed action and validates generated markers | unsupported | no |
| v4 | adds marked one-Array values action | unsupported | no |
| v5 | adds marked safe positional action | unsupported | no |
| v6 | retains the preceding action contracts | structured CST metadata is accepted | yes |

Plain and compact tables are encodings of the same lookup contract, not
separate ABI versions. A change to compression is format-preserving only when
every known and unknown token retains the same shift, reduce, accept, or error
result. Required table shape, action calling convention, marker meaning, or
runtime lookup meaning requires a new parser-table format.

Every pull, `yyparse`, push, finish, and syntax entry starts a parser session by
validating its table object. A missing or unsupported `format_version`, an
invalid generated action marker combination, or a legacy/boolean CST shape is
rejected before the runtime asks a pull lexer for a token or consumes a
caller-supplied push token. Format-v3-and-newer generated action marker
combinations are checked at that boundary. The error directs the application to regenerate.
Validation cannot undo side effects the caller performed while constructing an
argument before calling the runtime.

Regeneration is required when:

- a parser has no table-format version or uses a version the installed runtime
  does not list;
- any CST-aware parser predates structured format-v6 CST metadata;
- format-v3-and-newer generated action markers do not satisfy their versioned
  calling contract;
- an embedded parser must receive runtime fixes or a newer runtime ABI; or
- a release note for a new format explicitly retires an older reader.

A valid non-CST v1-v5 table does not require regeneration merely because v6 is
the current writer. Regeneration is nevertheless the supported way to adopt
new generated code and runtime behavior.

## Generator and runtime versions

| Generated artifact | Runtime used | Status |
| --- | --- | --- |
| Ibex 0.2.0 non-embedded output (table v6) | `ibex-runtime` 0.2.0 | supported and covered by packaging/runtime tests |
| Ibex 0.2.0 non-embedded output | a future version admitted by `~> 0.2.0` | dependency resolution permits it; compatibility is an obligation of that future release, not current execution evidence |
| Ibex 0.2.0 embedded output | runtime sources copied by Ibex 0.2.0 | self-contained and covered by packaging/runtime tests |
| old non-CST table v1-v5 | `ibex-runtime` 0.2.0 | accepted by the current reader tests |
| old CST table v1-v5 or a boolean CST marker | `ibex-runtime` 0.2.0 | rejected before input; regenerate |
| table v7 or later | `ibex-runtime` 0.2.0 | rejected before input; upgrade the runtime or regenerate to a supported format |

`ibex` 0.2.0 declares `ibex-runtime ~> 0.2.0`; in RubyGems terms that admits
runtime releases from 0.2.0 up to, but not including, 0.3.0. The table format is
still the executable compatibility check. A package requirement alone does not
prove that an unpublished runtime can execute a generated parser.

Normal generated output requires `ibex/runtime`. Embedded output concatenates
the runtime files named by `Runtime::EmbeddedSource` in dependency order. Thus
both modes use the same repository sources at generation time. Embedded output
does not consult an installed runtime and does not acquire later security,
correctness, or performance fixes: the application that chooses embedding owns
regeneration and redeployment. Loading embedded and installed copies into one
process is not a supported upgrade mechanism.

## Sidecar, IR version, or table-format version

Choose the boundary by its consumer:

- Use a sidecar for optional generation, review, or editor metadata that the
  parser does not need to accept input and whose absence preserves behavior.
- Use a new Grammar, Automaton, or Lexer IR version when persisted generator
  input changes shape or meaning, even if generated runtime tables do not.
- Use a new parser-table format when runtime execution needs a required field,
  new action convention, or changed table meaning before or during parsing.
- Use both IR and table versions when the persisted construction contract and
  the runtime execution contract both change.

An optional table field is not automatically safe: if its absence selects new
behavior or changes execution, it belongs behind a new format. Conversely,
large diagnostics that never affect execution should not inflate every parser
table merely to avoid a sidecar.

## Pull-request ABI assessment

The pull-request template contains a delimited YAML assessment. CI parses only
that block and requires the exact declared fields when a changed path matches
`runtime_paths` above. Free-form prose outside the block is not evidence.

`compatible` means the change keeps a current contract or adds a sidecar.
`breaking` selects a new table format, IR version, or runtime major version. A
new table format requires regeneration. An IR-only or Ruby-runtime-API break
must still make an explicit `required`/`not_required` regeneration decision;
application migration can be required even when parser regeneration is not.
`not_applicable` is accepted only when no declared runtime-facing path changed.
Evidence entries are repository paths reviewed with the change. The validator
checks structure and path existence, while reviewers remain responsible for
judging the stated surface, compatibility reasoning, and adequacy of tests.

Run `bundle exec rake quality:runtime_abi` locally. Pull-request CI also derives
the changed path list from the event's exact base and head SHAs without GitHub
API writes or elevated permissions.
