# Runtime ABI evolution

This policy separates durable serialized input, generated parser tables, and
the Ruby runtime API. The current format is the only supported Grammar and
Automaton IR boundary; the numeric field is a wire discriminator, not a promise
to read old files.

<!-- ibex-runtime-abi-contract:start -->
```yaml
contract_version: 1
ir:
  grammar:
    current_writer: 1
    readable: [1]
    migrations: []
    preserve_loaded_version: false
  automaton:
    current_writer: 1
    readable: [1]
    migrations: []
    preserve_loaded_version: false
  lexer:
    current_writer: 1
    readable: [1]
    migrations: []
    standalone: true
    embedded_in_grammar: true
parser_tables:
  current_writer: 6
  readable: [6]
  cst_readable: [6]
  fail_before_input: true
versions:
  generator: "0.3.0"
  runtime: "0.3.0"
  runtime_dependency: "~> 0.3.0"
runtime_paths:
  - .github/pull_request_template.md
  - .github/workflows/main.yml
  - Rakefile
  - docs/runtime-abi-evolution.md
  - docs/test-interactions.md
  - tool/quality/runtime_abi.rb
  - tool/quality/runtime_abi/**/*
  - test/quality/runtime_abi*_test.rb
  - test/support/runtime_abi_test_project.rb
  - test/fixtures/runtime_abi/**/*
  - ibex.gemspec
  - ibex-runtime.gemspec
  - lib/ibex/version.rb
  - lib/ibex/runtime.rb
  - lib/ibex/runtime/**/*
  - lib/ibex/runtime/version.rb
  - lib/ibex/tables.rb
  - lib/ibex/tables/**/*
  - sig/ibex/tables.rbs
  - sig/ibex/runtime.rbs
  - sig/ibex/runtime/**/*
  - sig/ibex/tables/**/*
  - lib/ibex/codegen.rb
  - lib/ibex/codegen/**/*
  - sig/ibex/codegen.rbs
  - sig/ibex/codegen/**/*
  - lib/ibex/frontend/generated_parser.rb
  - lib/ibex/ir.rb
  - lib/ibex/ir/**/*
  - sig/ibex/ir.rbs
  - sig/ibex/ir/**/*
  - schema/grammar-ir.schema.json
  - schema/grammar-ir-foundation.schema.json
  - schema/grammar-ir-extensions.schema.json
  - schema/automaton-ir.schema.json
  - schema/automaton-ir-definitions.schema.json
  - schema/lexer-ir-v*.schema.json
  - schema/cst-v*.json
  - test/matrix.yml
  - test/support/matrix_contract.rb
  - test/support/matrix_runner.rb
  - test/tooling/matrix_runner_test.rb
  - tool/quality/golden.rb
  - test/golden/**/*
assessment:
  states: [compatible, breaking, not_applicable]
  surfaces: [parser_table, grammar_ir, automaton_ir, lexer_ir, runtime_api, embedded_runtime, generation_metadata, cst, test_matrix, policy, none]
  abi_choices: [current_contract, new_table_format, new_ir_version, new_runtime_major, sidecar, none]
  regeneration: [required, not_required, not_applicable]
  required_fields: [state, surfaces, abi_choice, regeneration, rationale, affected_interactions, evidence, tests, verification]
```
<!-- ibex-runtime-abi-contract:end -->

The fenced record above is validated against the constants, schemas, gemspecs,
test declaration, and pull-request policy in this repository. Edit it only as
part of the implementation change that moves the corresponding boundary.

## IR read, write, migration, and freeze policy

| Contract | Current writer | Current reader | Migration | Freeze |
| --- | ---: | --- | --- | --- |
| Grammar IR | current format | current format only | none | the current schema is closed; older documents are rejected |
| Automaton IR | current format | current format only | none | the current schema is closed; older documents are rejected |
| Lexer IR | schema 1 | schema 1 | none | the closed schema changes only through a new schema |

The generator and runtime intentionally share one Grammar and Automaton IR
format. Older documents are rejected before construction; there is no in-process
IR migration command or compatibility reader. The current Grammar IR carries a
required root `parser_contract` whose individual fields
are either explicit with source locations or explicitly unspecified. Automaton
IR embeds the current Grammar IR, includes that contract in `grammar_digest`,
and records `entry_construction` as `shared` or `isolated`. Unknown versions and
construction values are rejected.

An extended root `parser ... end` declaration now writes explicit
`parser.algorithm` and `parser.entries` members into the current contract. The
declaration is generator input only: it selects existing construction paths and
does not add a runtime lookup, generated parser method, action ABI field, or
parser-table datum. Parser-table format v6 therefore remains the sole writer,
and declaration-free grammar, generated Ruby, and table golden bytes remain
unchanged.

Resuming from the current Grammar IR resolves explicit contract values through the same
typed configuration algebra as CLI values; a matching CLI value is accepted and
a conflicting canonical-generation value fails at the recorded declaration
location. Explicit analysis or grammar-test algorithm selection is reported as
noncanonical and never reclassified as canonical generation. Resuming from a constructed Automaton IR rejects
construction flags because they cannot rebuild the embedded tables. Its manifest
keeps the grammar contract, embedded construction facts, and effective codegen
configuration separate. These schema additions do not change parser-table
format v6 or the runtime action ABI.

Lexer IR schema 1 is independently versioned. It can be validated and serialized as
a standalone `ibex_ir: lexer` document, and Grammar IR can carry the same
versioned document in its optional `lexer` field. There is no Lexer IR
migration today. Changing lexer rule meaning or its required shape therefore
requires Lexer IR v2; changing only parser construction does not.

The JSON schemas under `schema/` are the published closed shapes. An optional
field may be added to a future version, but an existing closed schema is not
made open to avoid assigning new meaning to an old version.

## Parser-table formats

The generator emits format v6, and the runtime recognizes only that current
format. Older generated tables fail before input so the runtime does not carry
historical action-ABI branches indefinitely:

| Format | Non-CST runtime contract | CST contract | Current writer |
| ---: | --- | --- | --- |
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
caller-supplied push token. Current generated action marker combinations are
checked at that boundary. The error directs the application to regenerate.
Validation cannot undo side effects the caller performed while constructing an
argument before calling the runtime.

Regeneration is required when:

- a parser has no table-format version or uses a version the installed runtime
  does not list;
- any CST-aware parser predates structured format-v6 CST metadata;
- generated action markers do not satisfy their current calling contract;
- an embedded parser must receive runtime fixes or a newer runtime ABI; or
- a release note for a new format explicitly retires an older reader.

Non-CST v1-v5 tables are outside the pre-v1 runtime compatibility obligation
and require regeneration. Applications that need to keep an old generated
artifact can pin the matching pre-v1 runtime package instead of making the
current reader retain every historical table branch.

## Generator and runtime versions

| Generated artifact | Runtime used | Status |
| --- | --- | --- |
| Ibex 0.3.0 non-embedded output (table v6) | `ibex-runtime` 0.3.0 | supported and covered by packaging/runtime tests |
| Ibex 0.3.0 non-embedded output | a future version admitted by `~> 0.3.0` | dependency resolution permits it; compatibility is an obligation of that future release, not current execution evidence |
| Ibex 0.3.0 embedded output | runtime sources copied by Ibex 0.3.0 | self-contained and covered by packaging/runtime tests |
| Ibex 0.2.0 non-embedded output (table v6) | `ibex-runtime` 0.2.0 | supported and covered by packaging/runtime tests |
| Ibex 0.2.0 non-embedded output | a future version admitted by `~> 0.2.0` | dependency resolution permits it; compatibility is an obligation of that future release, not current execution evidence |
| Ibex 0.2.0 embedded output | runtime sources copied by Ibex 0.2.0 | self-contained and covered by packaging/runtime tests |
| old non-CST or CST table v1-v5 | `ibex-runtime` 0.3.0 | rejected before input; regenerate or pin the matching pre-v1 runtime |
| table v7 or later | `ibex-runtime` 0.3.0 | rejected before input; upgrade the runtime or regenerate to a supported format |

`ibex` 0.3.0 declares `ibex-runtime ~> 0.3.0`; in RubyGems terms that admits
runtime releases from 0.3.0 up to, but not including, 0.4.0. The previous
0.2.0 line remains a historical compatibility boundary. The table format is
still the executable compatibility check. A package requirement alone does not
prove that an unpublished runtime can execute a generated parser.

Normal generated output requires `ibex/runtime`. Embedded output concatenates
the runtime files named by `Runtime::EmbeddedSource` in dependency order. Thus
both modes use the same repository sources at generation time. Embedded output
does not consult an installed runtime and does not acquire later security,
correctness, or performance fixes: the application that chooses embedding owns
regeneration and redeployment. Loading embedded and installed copies into one
process is not a supported upgrade mechanism.

### Syntax-session ABI classification

Adding `SyntaxSession` and its syntax-only repair proposal keeps parser-table
format v6 unchanged and adds methods and immutable result types to the current Ruby runtime API. Existing
non-embedded generated source remains byte-identical and acquires the API from
a compatible runtime-package upgrade. Embedded generated source copies runtime
implementation bytes, so its bytes change and regeneration plus redeployment
is required to acquire the API or later session correctness fixes. Existing
embedded parsers that are not regenerated retain their previous parsing
behavior but do not gain the new façade.

The repository contract can represent that combined assessment without
claiming a table-format bump. The conservative `regeneration: required` value
applies to the affected embedded artifacts; the rationale records why the
non-embedded path only needs a runtime upgrade:

```yaml
state: compatible
surfaces: [runtime_api, embedded_runtime, cst]
abi_choice: current_contract
regeneration: required
rationale: Table v6 is unchanged and the runtime API is additive; embedded output bytes change and must be regenerated to acquire SyntaxSession.
affected_interactions: [incremental_cst, syntax_session, embedded_runtime]
evidence: [lib/ibex/runtime/cst/incremental/relexer.rb, lib/ibex/runtime/cst/incremental/session.rb, lib/ibex/runtime/syntax_session.rb, lib/ibex/runtime/parser.rb, lib/ibex/runtime/embedded_source.rb, test/runtime/syntax_session_test.rb, test/packaging/runtime_gem_test.rb]
tests: [test/runtime/cst_incremental_test.rb, test/runtime/syntax_session_test.rb, test/packaging/runtime_gem_test.rb]
verification: [bundle exec rake quality:runtime_abi, bundle exec ruby -Itest test/runtime/cst_incremental_test.rb, bundle exec ruby -Itest test/runtime/syntax_session_test.rb, bundle exec ruby -Itest test/packaging/runtime_gem_test.rb]
```

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
Every changed runtime-facing path must appear in `evidence`; additional evidence
must be a changed path or an existing regression test. `affected_interactions`
uses ids from the test-interaction contract, and every listed interaction owns
at least one path in `tests`. `verification` accepts only reviewed repository
commands and must run the ABI gate plus the owned tests (or the full suite).
The validator checks these relationships, while reviewers remain responsible
for judging the rationale and whether all affected surfaces were identified.
The deterministic rationale screen checks only structure: the value must be a
non-empty string containing a Unicode letter, and it must not equal the exact
repository-owned template sentinel after whitespace normalization. It does not
classify general placeholders, identifiers, repetition, entropy, or semantic
substance. Japanese, Arabic, and other writing systems are accepted. Reviewers
must decide whether the rationale actually explains compatibility and whether
TODO-like text is acceptable in context.

The structured choice table is closed:

| `abi_choice` | Required state | Required surface | Regeneration |
| --- | --- | --- | --- |
| `current_contract` | `compatible` | one or more concrete surfaces | `required` or `not_required` must be decided |
| `sidecar` | `compatible` | exactly `generation_metadata` | `not_required` |
| `new_table_format` | `breaking` | includes `parser_table` | `required` |
| `new_ir_version` | `breaking` | includes `grammar_ir`, `automaton_ir`, or `lexer_ir` | `required` or `not_required` must be decided |
| `new_runtime_major` | `breaking` | includes `runtime_api` or `embedded_runtime` | `required` or `not_required` must be decided |
| `none` | only a non-runtime change | `none` | `not_applicable` |

Runtime-facing changes cannot use `none` or `not_applicable`. A rationale must
replace the exact template sentinel and contain a Unicode letter; required human
review decides whether it is substantive. Verification commands are parsed as
arguments, not executed by the validator; shell composition, arbitrary
commands, unowned test files, and evidence-only README links are rejected.

Run the contract-only `bundle exec rake quality:runtime_abi` locally.
Pull-request CI uses a minimal dedicated job to invoke the separate
`quality:runtime_abi_pr` entry with its event path and name explicitly. That PR
gate derives the changed path list from
the event's exact base and head SHAs without GitHub API writes or elevated
permissions. It parses `runtime_paths` from the exact
trusted base revision and unions those paths with the head policy, so a pull
request cannot exempt its own changes merely by shrinking the head contract.
Only the first explicit addition of this contract can use the fixed bootstrap
path set. Repository rules must still require this check and review changes to
the workflow and validator: code running solely from an untrusted head cannot
defend against deletion or malicious replacement of the gate that launches it.
