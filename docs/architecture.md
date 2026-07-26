# Architecture and IR schemas

Ibex keeps syntax, grammar meaning, automaton construction, and output concerns behind two versioned immutable contracts.

```text
.y root/fragments -> Lexer/CST -> self-hosted LR Parser -> canonical Resolver ─┐
Ruby DSL ───────────────────────────────────────────────────────┴─> Grammar AST -> Normalizer -> Grammar IR
                                                    |
                                               set analysis
                                                    |
                                      SLR/LALR/LR1 Builder -> Automaton IR
                                                                    |
                       Ruby/RBS/action-shadow generators / report / DOT / Mermaid / HTML / counterexamples
```

Frontend changes stop at the Normalizer. Algorithm strategies consume Grammar IR and produce identical Automaton IR shapes.
Outputs consume Automaton IR and never call builder internals. The CLI only connects stages and supports JSON resumption.

The text frontend's canonical syntax is `lib/ibex/frontend/grammar.y`. Ibex generates and commits
`lib/ibex/frontend/generated_parser.rb`; the public `Frontend::Parser` always delegates to that class. Lexer `Token` objects remain
the semantic values passed through `TokenAdapter`, preserving their `Location` in AST nodes and diagnostics. The explicitly named
handwritten `BootstrapParser` is excluded from normal loading and exists only to break the regeneration cycle. See
[ADR 0015](decisions/0015-self-hosted-grammar-frontend.md) for the update procedure and boundary.

The lexer also retains an immutable lexical CST without changing the semantic token stream. `Frontend::Parser#parse_document`
returns a `SourceDocument` whose source, token-indexed segments, and AST come from that single lexer/parser pass.
`SourceSpan` uses half-open zero-based byte offsets and one-based Unicode-scalar line/column positions. Actions and user-code
bodies remain opaque segments; whitespace, line breaks, both comment forms, user-code markers, and EOF remain individually traversable.
`render`, byte slicing, and byte/line/column conversion provide the common source contract for formatter, documentation, include,
and language-server layers. `RuleDocumentation` correlates immediately preceding `##` comment-only lines with semantic rule
locations and copy-enriches generated Root/Fragment nodes; occupied opaque-segment lines are never scanned as comments. See
[ADR 0040](decisions/0040-lossless-frontend-source-document.md) and [ADR
0043](decisions/0043-lossless-rule-documentation.md).

`Frontend::Formatter` classifies the document's existing semantic tokens, replaces only whitespace/newline trivia, and protects
token, comment, action, heredoc, marker, and user-code bytes. It reparses the rendered root or fragment in the same frontend mode
and compares ASTs with an explicit work stack after removing location fields. The CLI's stdout, batch check, and transactional
in-place surfaces are therefore downstream consumers of `SourceDocument`, not an alternate grammar parser. Existing newline
segment spellings and blank-line counts survive required line boundaries; new boundaries use the first newline even when it is
inside opaque text. Batch stages and hard-link backups live beside each resolved target. Alias rejection, reverse rollback, and
all-directory synchronization preserve full file modes and relative or absolute symlink identities. Backups are synchronized
before installation; a failed restore preserves its backup, while post-commit cleanup problems are status-0 warnings. See [ADR
0047](decisions/0047-semantics-preserving-grammar-formatting.md).

`Frontend::SourceLoader` is the shared disk/overlay read boundary. Resolver's default loader retains canonical filesystem
behavior; LSP injects open buffers, including safe new files, while the resolver continues to enforce realpath containment,
symlink escape rejection, cycle identity, and diamond deduplication. `LSP::DocumentStore` layers monotonic open versions,
root/include closures, reverse dependencies, and disk restoration over that loader. `PositionCodec` is the only UTF-16 adapter
over frontend byte/scalar spans. `SymbolIndex` derives navigation and guarded rename edits from parsed nodes and lossless tokens,
never from opaque Ruby or textual scanning. Content-Length transport, lifecycle handling, and request handlers remain separate
from workspace semantics; see [ADR 0048](decisions/0048-overlay-workspaces-and-lsp.md).

CLI file generation renders every requested output into an immutable `ArtifactSet` before entering `GenerationTransaction`.
The transaction records the exact root, fragment, IR, and message bytes read through `GenerationInput`, rejects portable target
collisions and input aliases, takes stable sidecar locks, stages and synchronizes every file, and can restore hard-link backups
in reverse publication order. Ordinary companions publish first, the parser second, and an opt-in generation manifest last.
That manifest is the coherence marker: readers verify its listed paths, sizes, and SHA-256 digests and retry from a newly read
manifest on a mismatch. It is not a claim that several filesystem renames occur atomically. `--watch` feeds the same transaction
only candidates whose complete canonical source closure and failed include attempts remain unchanged across rendering and
publication. Portable polling, bounded debounce, failure deduplication, and cancellable nonblocking locks keep the last successful
generation usable while a source is invalid; see [ADR 0049](decisions/0049-transactional-generation-and-watch-mode.md).

Extended grammar paths cross an explicit `Frontend::Resolver` boundary. Roots retain class, start, options, and user code;
fragments contain composable declarations and rules. Canonical realpaths define DFS order, diamond deduplication, cycle identity,
and the Rake dependency closure. Canonical dirname ancestry keeps every resolved target below the root grammar directory after
symlink resolution, including when that directory is a filesystem or drive root. The source-only Parser never follows an
include. A `Resolution` recursively freezes its owned AST and defensive provenance copies while retaining rule identity for
include-chain lookup. Rake resolves this closure at task definition and refuses invalid graphs before timestamp checks can reuse
a stale output; see [ADR 0042](decisions/0042-canonical-grammar-fragment-includes.md).

Extended parameterized definitions remain structural AST templates rather than grammar symbols. The Normalizer validates the
complete template graph, interns an impossible `$parameter_N` helper for each canonical call, records that helper in a memo
before expanding its body, and substitutes formals through nested EBNF and calls. Resumable alternative, item, and EBNF
continuations on an explicit depth-first worklist preserve ordinary lowering order and active-depth semantics without consuming
the Ruby call stack. Same-argument recursion therefore closes over the memo, while configurable specialization and active-depth
limits bound argument-growing recursion. Template actions,
precedence, metadata, documentation, locations, and definition include chains flow into the specialized productions; see
[ADR 0044](decisions/0044-parameterized-user-rules.md).

Inline definitions are lowered temporarily, then a bounded deterministic post-pass substitutes marked alternatives through
ordinary, parameterized, and EBNF productions before diagnostics and LR construction. It removes every marked symbol and
production, remaps the dense symbol/production ids, and retains eliminated semantic reductions as a versioned post-order
action plan. The plan addresses flattened physical values followed by earlier logical results, records a nullable semantic
`result_type` on every newly emitted step, reconstructs surrounding stack
prefixes and semantic spans, and remains executable after IR serialization. Cycle validation covers paths through ordinary
rules and templates; the default 10,000-production cartesian budget is configurable. See
[ADR 0045](decisions/0045-bounded-inline-rule-expansion.md).

The strict generated frontend remains the grammar authority during batch diagnostics. A diagnostic parse retries it after
suppressing only a whole declaration, whole rule, or outer alternative at balanced delimiters. Each retry must remove a new
original token and both attempts and emitted diagnostics are bounded. Lexical and syntax phases collect independently before a
global source-order limit is applied, so an earlier syntax error cannot be hidden by a later lexical error. Machine-readable
diagnostics retain source spans, defensive locations, and stable codes. A repaired AST is marked partial by `ParseResult`, and
is not attached to the unchanged source document. After a successful root parse, the CLI reports the first resolver grammar
failure through the same diagnostic schema, while actual resolution I/O failures remain invocation errors. The CLI exposes this
analysis only through `ibex diagnose`; see [ADR 0041](decisions/0041-bounded-frontend-diagnostics.md).

The RBS generator emits the generated class namespace, superclass, parser-table constants, `.parser_tables` contract, and
private reduction and composed-fragment signatures. Declared symbol types refine the RHS tuple and LHS result independently,
with `untyped` used at undeclared boundaries; composed inputs resolve either a physical symbol type or an earlier plan step's
`result_type`. Reduction methods also receive a location tuple, surrounding location stack, and optional
`Runtime::LocationSpan`; the runtime maintains that stack in parallel with semantic values for every driver and recovery path.
Default source mapping compiles opaque action methods with `class_eval` when the generated class loads. The opt-in action-shadow
generator makes those exact method bodies visible to Steep without runtime loading: runtime and shadow output share one method
source builder, while the shadow omits parser infrastructure and every user-code section. Ibex only generates this source;
executing Steep remains an application/CI boundary. See [ADR
0046](decisions/0046-static-action-shadow-source.md). The
gem also ships a one-to-one rbs-inline-generated signature tree under `sig/` for every Ruby source in `lib/`, including the
self-hosted parser. CI regenerates into an empty temporary directory, compares the complete trees, validates the RBS environment,
and runs Steep against the entire library. Token/location records, grammar AST nodes, parser classifier and bootstrap state, the
Ruby DSL, IR records, and automaton actions use concrete domain types. Generated-parser reduction values, dynamic parser-table
cells, decoded JSON values, and user methods embedded as opaque Ruby source remain `untyped`; applications can reopen the generated
class in their own RBS files to declare embedded methods.

## Grammar IR versions 1 and 2

Top-level fields:

| Field | Meaning |
|---|---|
| `ibex_ir`, `schema_version` | `"grammar"`, `1` |
| `class_name`, `superclass` | Generated Ruby class contract |
| `start`, `expect`, `options` | Start name, unresolved S/R expectation, result/action flags |
| `symbols` | Interned terminals and nonterminals; `$eof` id 0 and `error` id 1 |
| `productions` | Numeric LHS/RHS ids, action, precedence override, source origin |
| `user_code`, `conversions`, `warnings` | Concatenated code, external token expressions, structured diagnostics |
| `user_code_chunks` | Optional opaque chunks with first-code-line locations for compatible source mapping |

Warning records use the additive type vocabulary `undeclared_terminal`, `unused_terminal`, `unused_precedence`,
`unreachable_terminal`, `unreachable_nonterminal`, `duplicate_production`, and `empty_language`, and retain source locations.
Schema-v1 readers must ignore warning types they do not recognize. The CLI applies display/error policy at the boundary;
normalization and IR serialization do not discard diagnostics. See
[ADR 0021](decisions/0021-diagnostic-outputs-and-warning-vocabulary.md).

A symbol has `id`, `name`, `kind`, `reserved`, optional `prec {associativity, level}`, `loc`, `display_name`, and
`semantic_type`. The last two fields are omitted when undeclared, so older schema-v1 documents remain byte-stable and loadable.
A production has `id`, `lhs`, `rhs`, optional `action`, optional `prec_override`, and `origin`. Synthetic EBNF origins include
an additive, deterministic `expression` label used by text, DOT, and HTML presentation while numeric symbol identities remain
unchanged. An action has opaque `code`, `loc`, `named_refs [{name,index}]`, and `context_length`; middle-action helpers use the
last field to view preceding stack values.

IR objects and nested collections are frozen. JSON keys have deterministic order, so dump/load/dump is byte-stable. The additive
`user_code_chunks` field remains optional in version 1 so older JSON stays loadable.

New normalized grammars use version 2. It keeps every version-1 semantic field and adds explicit nullable metadata:

| Record | Version-2 metadata |
|---|---|
| grammar | `source_provenance {file, root, byte_span {start,end}}` and optional `migration` loss record |
| symbol | `doc` |
| production | `doc` and `expansion {parameter, inline, include_chain}` |
| action | `composition {strategy, fragments, plan {version, physical, steps}}`; new steps include nullable `result_type` |

The source-only text frontend supplies the source filename and leaves unknown metadata null. A resolved grammar also supplies its
canonical source root and each production's include chain while preserving its original-file origin. Lossless rule comments
populate symbol and user-production documentation, including through fragment resolution; synthetic EBNF helpers remain
undocumented. Parameterized specializations populate `expansion.parameter` with the template name and canonical structural
arguments while retaining the definition's include chain. Version-1 upgrades mark every unrecoverable metadata family in
`migration.unavailable` instead of guessing.
For compatibility with version-2 documents produced before ADR 0046, the input schema also accepts an absent composition-step
`result_type`; generators treat it as `untyped`.
`Serialize.load` and `Validator.validate` accept both versions; a loaded version-1 object dumps with the original version-1
shape. `IR::Migration.to_version` upgrades version 1 to 2 and is idempotent at version 2. The CLI exposes this as
`ibex migrate-ir INPUT --to=2 [-o FILE]`; file output uses an atomic same-directory rename and refuses to alias the input.

`Codegen::Documentation` renders normalized user rules and alternatives as escaped Markdown, self-contained accessible HTML, or
railroad SVG. The railroad renderer includes visible wrapped rule descriptions in its section-height calculation and exposes the
full escaped text through SVG descriptions. `ibex doc` resolves the same canonical include graph and writes to stdout or an
atomic file without generating or executing application parser code.

## Automaton IR versions 1 and 2

Top-level fields are `ibex_ir: "automaton"`, `schema_version`, `algorithm`, `grammar_digest`, embedded `grammar`, `states`, and
`conflict_summary`. Embedding Grammar IR makes automaton JSON sufficient for code generation after `--from=automaton-ir`.

Each state contains:

- merged items `{production, dot, lookaheads}`;
- named `transitions`;
- resolved terminal `actions` and nonterminal `gotos`;
- an optional reduce `default_action`, selected only when explicit error masks preserve every terminal lookup and reduce the
  total encoded ACTION entries;
- every conflict, including precedence-resolved conflicts and the resolution reason.

`conflict_summary.sr` counts unresolved default-shift conflicts for `expect`; `resolved_sr` counts retained precedence or
associativity decisions; `rr` counts reduce/reduce cells.

New automata use version 2 and always embed Grammar IR version 2. Migration recalculates `grammar_digest` from the upgraded
canonical grammar. Version-1 automata remain loadable, validatable, and byte-stable. Published Draft 2020-12 contracts for both
versions live under `schema/`; see [ADR 0039](decisions/0039-versioned-ir-v2-migration.md).

`--emit=sets` is a deterministic analysis view rather than another IR: it emits lexically sorted nullable nonterminals and
FIRST/FOLLOW maps for nonterminals. DOT, Mermaid, and the self-contained searchable HTML report are deterministic presentation
views over Automaton IR.

## Construction algorithms and counterexamples

The builder uses canonical LR(1) item sets as its common starting point. The `lr1` strategy retains those states, `lalr` merges
states with equal LR(0) cores, and `slr` applies FOLLOW sets to completed items in LR(0) states. All strategies use the same
conflict resolver and produce the same Automaton IR shape. After a build, the builder exposes a frozen diagnostic `metrics`
value containing only canonical-intermediate and final state counts. It is deliberately outside Automaton IR because it describes
the chosen construction strategy rather than the resulting parser.

`Ibex::LALR::Counterexample` consumes only Automaton IR. For each conflict it explores parser-stack configurations, forces the
competing actions, and searches for a common accepting suffix. A successful result contains both complete derivation trees and is
marked `unifying: true`. Search defaults to 32 tokens and 50,000 configurations; the Ruby and CLI APIs can set both positive
budgets. If no common sentence is found within them, the result is explicitly marked nonunifying and contains the deterministic
shortest reachability witness instead of claiming ambiguity.

`Ibex::Codegen::Explain` filters those immutable conflicts by state and canonical token identity before asking
`Counterexample#for_conflict` to search only the selected entries, then renders text or the versioned `explain` JSON analysis
shape. `Counterexample#all` retains its original all-conflict behavior. The view performs no additional parser analysis and does
not extend Grammar or Automaton IR.

The repository's self-authored representative grammar feeds the versioned `ibex_benchmark` v1 document. Its JSON Schema is
shipped beside the IR schemas, while committed environment-specific observations live under `benchmark/results/v1`. Timing and
peak RSS remain non-gating; CI reproduces only deterministic structure and digests. See
[ADR 0038](decisions/0038-versioned-benchmark-evidence.md).

## Runtime table contract

Generated subclasses expose `.parser_tables` with a required `format_version`, external `tokens`, display `token_names`, ACTION
and GOTO tables, per-state default actions, and production `{lhs,length,action}` records. The runtime validates the version before
reading input and rejects missing or unsupported formats with a regeneration instruction. The generator emits v3, while the
runtime accepts v1's two-argument actions, v2/v3 explicitly marked five-argument location actions, and v3 explicitly marked
six-argument composed actions. Inconsistent v3 composition markers fail before input; see
[ADR 0018](decisions/0018-parser-table-format-version.md). Plain tables are arrays of Hash rows. Compact tables use row
displacement with offsets, values, and row-ownership checks; both expose equivalent lookups. Default reductions are restricted
to known token ids, and explicit error masks preserve the pre-optimization result of every declared terminal cell, including
the synthetic `error` terminal. The deterministic size policy is fixed by
[ADR 0014](decisions/0014-compatibility-safe-default-reductions.md).

The runtime maintains state and value stacks, pulls a lookahead only when required, and applies tagged `shift`, `reduce`,
`accept`, and `error` actions. Recovery pops to a state that shifts token id 1, suppresses repeated reports for three successful
shifts, and honors `yyerrok`. No-op `on_shift`, `on_reduce`, and `on_error_recover` extension points observe successfully
committed events without changing parser results; the recovery hook retains the pre-pop error context and is distinct from an
ordinary token shift. Their ordering and payload contract is fixed by [ADR 0013](decisions/0013-runtime-observation-hooks.md).

The separate `Runtime::Parser#observe` API publishes ordered, immutable schema-v1 events for tooling. Its bounded sanitizer
copies only JSON data and never retains application identities or private stacks. With no observer, parse transitions construct
no Event, payload summary, or dispatch snapshot; parser initialization still creates its ownership mutex. Generated tables
contribute grammar digest, table format, state count, and production count to the `start` event. `Runtime::EventJSONLTracer`
exposes the versioned stream; the original hook-based `Runtime::JSONLTracer` remains byte-compatible. The protocol and
exception/threading behavior are fixed by
[ADR 0050](decisions/0050-stable-immutable-runtime-events.md).

`Coverage::Collector` accepts only contiguous, complete runtime-event sessions with generated parser metadata. It counts entries
to the initial, shift, reduce-goto, and recovery states and counts committed reductions by production id. `Coverage::Report`
publishes ascending sparse hit arrays under the versioned runtime-coverage schema. Merge requires identical full grammar digest,
table format, and totals and uses checked addition. The coverage CLI only reads bounded JSON/JSON Lines and never loads generated
Ruby or executes semantic actions; collection, merge, threshold, and atomic-output policy are fixed by
[ADR 0051](decisions/0051-deterministic-runtime-coverage.md).

## Clean-room boundary

Implementation work uses public racc documentation, CLI black-box behavior, and published LR algorithms only. racc implementation
sources and generated source are not inputs to the design. Self-authored compatibility grammars execute both outputs in separate
processes and compare observable results.
