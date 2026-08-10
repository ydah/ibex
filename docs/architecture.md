---
title: Architecture
description: Ibex's grammar, IR, parser construction, runtime, and verification boundaries.
---

# Architecture and IR schemas

Ibex keeps syntax, grammar meaning, automaton construction, and output concerns behind two immutable current contracts.

```text
.y root/fragments -> Frontend Lexer/CST -> self-hosted LR Parser -> canonical Resolver ─┐
Ruby DSL ───────────────────────────────────────────────────────┴─> Grammar AST -> Normalizer -> Grammar IR
                                                                               |              |
                                                                               |          Lexer IR v1
                                                    |
                                               set analysis
                                                    |
                                      SLR/LALR/IELR/LR1 Builder -> Automaton IR
                                                                    |
                       Ruby/RBS/action-shadow generators / report / DOT / Mermaid / HTML / counterexamples
```

Frontend changes stop at the Normalizer. Algorithm strategies consume Grammar IR and produce identical Automaton IR shapes.
Outputs consume Automaton IR and never call builder internals. The CLI only connects stages and supports JSON resumption.

## Execution trust boundary

`syntax-only` means that the LR runtime suppresses parser production actions.
It does not mean that no application Ruby executes.

| Execution path | Parser production actions | Generated lexer actions | User `header` / `inner` / `footer` | Trust |
| --- | --- | --- | --- | --- |
| Grammar parse/normalize, format, LSP, reports, conflict/diff/equiv/verify/debug, internal fuzz | No | No | No | Nonexecuting without an external-command option |
| Generated-lexer semantic: `parse`, `lex(...).do_parse`, `parse_with_syntax(source)` | Yes | Yes | May execute when the generated file loads | Trusted application code; not a sandbox |
| Handwritten pull semantic: `do_parse`, no-argument `parse_with_syntax` | Yes | No | May execute when the generated file loads | Trusted application code; not a sandbox |
| Caller-fed semantic: `yyparse`, `push` / `finish` | Yes | No | May execute when the generated file loads | Trusted application code; not a sandbox |
| Generated syntax-only parse | No | Yes | May execute when the generated file loads | Trusted application code; not a sandbox |
| Future safe syntax profile | No | Declarative built-ins only | No | Nonexecuting profile; not currently available |

Static paths operate on source, Grammar IR, Lexer IR, Automaton IR, or parser
tables without requiring the generated application parser. Parser actions,
lexer actions, conversions, and user sections remain opaque data on those
paths. Code generation may emit source that compiles them when the artifact is
loaded, but the generator does not load that artifact.

The static guarantee excludes explicit external-command options.
`ibex fuzz --against=COMMAND` and `ibex reduce --command=COMMAND` spawn the
supplied executable and may run arbitrary application code with host permissions.
Subprocess resource limits and process-group cleanup are not sandboxes and do
not confine side effects.

Semantic runtime entry points execute committed parser production actions.
Generated lexer actions execute only when tokens are pulled through
`GeneratedLexer#next_token`; handwritten `next_token`, `yyparse`, and
`push` / `finish` paths do not invoke that lexer. Syntax-only entry points
suppress parser actions but still use the generated lexer to emit tokens,
convert values, and mutate lexer state. Every generated runtime path crosses
the trusted application boundary because loading the generated Ruby file may
execute arbitrary user sections. Resource budgets and process-isolation
building blocks do not make those paths sandboxes.

A future profile for untrusted syntax work must use data-only parser tables, a
declarative lexer whose operations are restricted to built-ins, no parser
actions, no arbitrary conversions, and no `header`, `inner`, or `footer`
sections. The current generated parser API must not be described as that
profile.

An optional root-only `lexer` declaration normalizes to the independently versioned
Lexer IR and its flat rule list, which are embedded unchanged in the current Grammar IR.
records state, declaration id, pattern source/options, action, and provenance;
`--emit=lexer-ir` exposes the same document. Code generation compiles every
pattern with an internal current-position anchor and emits immutable,
state-indexed rules. Per-parser mutable input, position, emission, and state
stacks live in `Runtime::GeneratedLexer`, never in the tables. See
[ADR 0014](decisions/0014-versioned-generated-lexer.md).

`pragma cst` remains an optional current Grammar IR flag. Regenerated format-v6
tables add deterministic kind and normalized slot metadata. `Runtime::Parser`
builds a pure-syntax Green entry for every shift and reduction on a stack
parallel to the semantic stack, so tree shape no longer depends on semantic
actions. Generated lexer skips become token-owned trivia. Parser failure,
repair, and lexer failure remain explicit and lossless. See
[ADR 0016](decisions/0016-red-green-concrete-syntax.md) and the
[CST guide](cst.md). Batch CST, typed views, editing, and serialization form
the Stable v1 contract. The runtime accepts structured CST metadata only in
the current format and rejects older CST tables before reading input; see
[ADR 0008](decisions/0008-versioned-runtime-package-boundary.md).

## Red/Green CST v2

Green nodes and tokens contain no parents, source objects, absolute positions,
semantic values, or parser states. Their integer kinds, binary text, trivia,
flags, widths, children, and descendant counts are immutable and
Ractor-shareable. A session-owned `NodeCache` interns unannotated values. Lazy
Red wrappers add occurrence-specific parent, index, offset, span, location, and
typed-field navigation. The root is `source_file(start, EOF)`, and
`to_source` is byte exact for the `leading` and `balanced` trivia policies.

Generated `Parser::Syntax::<Name>` classes are typed views over Red nodes using
the same normalized `@node` metadata as Data AST generation. Persistent edits
replace one Green occurrence and copy its ancestor path; rewriters, batched
editors, annotations, and identity-skipping text diffing share that mechanism.
See [ADR 0017](decisions/0017-persistent-syntax-artifacts.md).

`ibex_cst` schema v1 serializes the Green root, kind metadata, compatibility
counts, and optional preorder parser memo independently of Grammar IR.
Validation reconstructs every derived width, flag, and descendant count.
Non-UTF-8 bytes use canonical Base64. See
[ADR 0017](decisions/0017-persistent-syntax-artifacts.md).

Incremental sessions are syntax-only: parser production actions do not run,
but generated lexer actions do. The generated lexer first validates token/state
resynchronization. `Blender`
then offers either a fresh token or an old Green nonterminal to the LR driver.
A subtree is pushed directly through `goto` only when damage, recorded
left-state, follow-token identity, error flags, and positive width satisfy the
conservative reuse proof. Token and parse memos remain preorder/occurrence
state owned by one session; resource exhaustion falls back to the fresh token
stream. See [ADR 0018](decisions/0018-conservative-incremental-syntax-reuse.md).

`Runtime::SyntaxSession` is a thin generated-language service boundary over
that same engine. Current generated classes expose only
`:trusted_application_code`, and callers must explicitly acknowledge that
profile because lexer actions still execute. Immutable operation snapshots add
expected-token and reuse/fallback evidence plus cooperative cancellation and
service bounds. The façade belongs to `ibex-runtime`; it defines neither LSP
nor workspace semantics. Its additive `repair` operation projects bounded
syntax repairs into byte edits and fresh syntax results without exposing
semantic values or invoking application repair callbacks. See
[ADR 0019](decisions/0019-runtime-syntax-session-boundary.md).

Alternative-level `@node` declarations are preserved in the current Grammar IR
production metadata. Runtime Ruby, static action-shadow Ruby, and generated
RBS all derive Data node classes and Visitor/Listener hooks from that same
metadata; action source is never inspected to infer a shape. Symbol semantic
types and fully annotated nonterminals supply field types.

The text frontend's canonical syntax is `lib/ibex/frontend/grammar.y`. Ibex generates and commits
`lib/ibex/frontend/generated_parser.rb`; the public `Frontend::Parser` always delegates to that class. Lexer `Token` objects remain
the semantic values passed through `TokenAdapter`, preserving their `Location` in AST nodes and diagnostics. The explicitly named
handwritten `BootstrapParser` is excluded from normal loading and exists only to break the regeneration cycle. See
[ADR 0003](decisions/0003-self-hosted-grammar-frontend.md) for the update procedure and boundary.
`lib/ibex/frontend/shadow_grammar.y` describes the same frontend with parameterized list rules and an inline terminal wrapper.
It is generated only in tests and must match the production parser's AST across the canonical grammar and extended fixtures;
see the [development guide](development.md).

The lexer also retains an immutable lexical CST without changing the semantic token stream. `Frontend::Parser#parse_document`
returns a `SourceDocument` whose source, token-indexed segments, and AST come from that single lexer/parser pass.
`SourceSpan` uses half-open zero-based byte offsets and one-based Unicode-scalar line/column positions. Actions and user-code
bodies remain opaque segments; whitespace, line breaks, both comment forms, user-code markers, and EOF remain individually traversable.
`render`, byte slicing, and byte/line/column conversion provide the common source contract for formatter, documentation, include,
and language-server layers. `RuleDocumentation` correlates immediately preceding `##` comment-only lines with semantic rule
locations and copy-enriches generated Root/Fragment nodes; occupied opaque-segment lines are never scanned as comments. See
[ADR 0004](decisions/0004-shared-semantic-and-lossless-source-model.md).

`Frontend::Formatter` classifies the document's existing semantic tokens, replaces only whitespace/newline trivia, and protects
token, comment, action, heredoc, marker, and user-code bytes. It reparses the rendered root or fragment in the same frontend mode
and compares ASTs with an explicit work stack after removing location fields. The CLI's stdout, batch check, and transactional
in-place surfaces are therefore downstream consumers of `SourceDocument`, not an alternate grammar parser. Existing newline
segment spellings and blank-line counts survive required line boundaries; new boundaries use the first newline even when it is
inside opaque text. Batch stages and hard-link backups live beside each resolved target. Alias rejection, reverse rollback, and
all-directory synchronization preserve full file modes and relative or absolute symlink identities. Backups are synchronized
before installation; a failed restore preserves its backup, while post-commit cleanup problems are status-0 warnings. See
[ADR 0004](decisions/0004-shared-semantic-and-lossless-source-model.md).

`Frontend::SourceLoader` is the shared disk/overlay read boundary. Resolver's default loader retains canonical filesystem
behavior; LSP injects open buffers, including safe new files, while the resolver continues to enforce realpath containment,
symlink escape rejection, cycle identity, and diamond deduplication. `LSP::DocumentStore` layers monotonic open versions,
root/include closures, reverse dependencies, and disk restoration over that loader. `PositionCodec` is the only UTF-16 adapter
over frontend byte/scalar spans. `SymbolIndex` derives navigation and guarded rename edits from parsed nodes and lossless tokens,
never from opaque Ruby or textual scanning. Content-Length transport, lifecycle handling, and request handlers remain separate
from workspace semantics; see [ADR 0004](decisions/0004-shared-semantic-and-lossless-source-model.md).

CLI file generation renders every requested output into an immutable `ArtifactSet` before entering `GenerationTransaction`.
The transaction records the exact root, fragment, IR, and message bytes read through `GenerationInput`, rejects portable target
collisions and input aliases, takes stable sidecar locks, stages and synchronizes every file, and can restore hard-link backups
in reverse publication order. Ordinary companions publish first, the parser second, and an opt-in generation manifest last.
That manifest is the coherence marker: readers verify its listed paths, sizes, and SHA-256 digests and retry from a newly read
manifest on a mismatch. It is not a claim that several filesystem renames occur atomically. `--watch` feeds the same transaction
only candidates whose complete canonical source closure and failed include attempts remain unchanged across rendering and
publication. Portable polling, bounded debounce, failure deduplication, and cancellable nonblocking locks keep the last successful
generation usable while a source is invalid; see [ADR 0013](decisions/0013-transactional-generation-publication.md).
The executable's ordinary generation path declares this pipeline directly instead of loading the complete library and every
subcommand. Optional subcommands and generation outputs load at their invocation boundary while their public constants remain
autoloadable.

### Effective configuration boundary

`Ibex::Configuration` gives generation, grammar-test, and analysis paths one closed definition for parser construction and
build-policy concepts. Each immutable value records its canonical key, typed domain, owner, override policy, selected origin,
explicitness, and whether the selection is canonical. `Configuration::CLIAdapter` translates the existing internal option
hash into domain values such as `parser.entries=isolated`, `cst.trivia=leading`, and
`source.line_mapping=all`; code generators do not interpret legacy CLI shapes directly.

`Configuration::Resolver` applies fixed and monotone-minimum algebra without loading a grammar file or executing user code.
A fixed grammar declaration accepts a matching request and raises `Configuration::Conflict` for a contradiction. An explicit
analysis override remains noncanonical and serializes both the declared and selected values. Evidence JSON is emitted in
canonical-key order. This boundary intentionally adds neither grammar syntax nor a project configuration file; those adapters
must supply the same closed keys when their separately reviewed formats exist.

Extended grammar paths cross an explicit `Frontend::Resolver` boundary. The canonical `import` declaration and compatible
`include` spelling share this boundary. Roots retain class, start, options, and user code;
fragments contain composable declarations and rules. Canonical realpaths define DFS order, diamond deduplication, cycle identity,
and the Rake dependency closure. Canonical dirname ancestry keeps every resolved target below the root grammar directory after
symlink resolution, including when that directory is a filesystem or drive root. The source-only Parser never follows an
include. A `Resolution` recursively freezes its owned AST and defensive provenance copies while retaining rule identity for
include-chain lookup. Rake resolves this closure at task definition and refuses invalid graphs before timestamp checks can reuse
a stale output; see [ADR 0005](decisions/0005-contained-grammar-composition.md).

Extended parameterized definitions remain structural AST templates rather than grammar symbols. The Normalizer validates the
complete template graph, interns an impossible `$parameter_N` helper for each canonical call, records that helper in a memo
before expanding its body, and substitutes formals through nested EBNF and calls. Resumable alternative, item, and EBNF
continuations on an explicit depth-first worklist preserve ordinary lowering order and active-depth semantics without consuming
the Ruby call stack. Same-argument recursion therefore closes over the memo, while a configurable total-specialization budget
and structural constructor-growth detection bound argument-growing recursion without an arbitrary depth cutoff. Template actions,
precedence, metadata, documentation, locations, and definition include chains flow into the specialized productions; see
[ADR 0006](decisions/0006-bounded-structural-grammar-lowering.md).

Inline definitions are lowered temporarily, then a bounded deterministic post-pass substitutes marked alternatives through
ordinary, parameterized, and EBNF productions before diagnostics and LR construction. It removes every marked symbol and
production, remaps the dense symbol/production ids, and retains eliminated semantic reductions as a stable post-order
action plan. The plan addresses flattened physical values followed by earlier logical results, records a nullable semantic
`result_type` on every newly emitted step, reconstructs surrounding stack
prefixes and semantic spans, and remains executable after IR serialization. Cycle validation covers paths through ordinary
rules and templates; the default 10,000-production cartesian budget is configurable. See
[ADR 0006](decisions/0006-bounded-structural-grammar-lowering.md).

The strict generated frontend remains the grammar authority during batch diagnostics. A diagnostic parse retries it after
suppressing only a whole declaration, whole rule, or outer alternative at balanced delimiters. Each retry must remove a new
original token and both attempts and emitted diagnostics are bounded. Lexical and syntax phases collect independently before a
global source-order limit is applied, so an earlier syntax error cannot be hidden by a later lexical error. Machine-readable
diagnostics retain source spans, defensive locations, and stable codes. A repaired AST is marked partial by `ParseResult`, and
is not attached to the unchanged source document. After a successful root parse, the CLI reports the first resolver grammar
failure through the same diagnostic schema, while actual resolution I/O failures remain invocation errors. The CLI exposes this
analysis only through `ibex diagnose`; see [ADR 0004](decisions/0004-shared-semantic-and-lossless-source-model.md).

The RBS generator emits the generated class namespace, superclass, parser-table constants, `.parser_tables` contract, and
private reduction and composed-fragment signatures. Declared symbol types refine the RHS tuple and LHS result independently,
with `untyped` used at undeclared boundaries; composed inputs resolve either a physical symbol type or an earlier plan step's
`result_type`. Reduction methods also receive a location tuple, surrounding location stack, and optional
`Runtime::LocationSpan`. Generated tables mark whether actions require locations. The runtime leaves the location stack
unallocated for ordinary two-element-token parses and creates or backfills it only when an action, tooling observer, or
three-element token requires it. The public immutable `Ibex::Location` range and `loc`/`result_loc` action helpers sit above the
same stack contract.
Default source mapping compiles opaque action methods with `class_eval` when the generated class loads. The opt-in action-shadow
generator makes those exact method bodies visible to Steep without runtime loading: runtime and shadow output share one method
source builder, while the shadow omits parser infrastructure and every user-code section. Ibex only generates this source;
executing Steep remains an application/CI boundary. See
[ADR 0011](decisions/0011-versioned-semantic-action-boundary.md). The
gem also ships a one-to-one rbs-inline-generated signature tree under `sig/` for every Ruby source in `lib/`, including the
self-hosted parser. CI regenerates into an empty temporary directory, compares the complete trees, validates the RBS environment,
and runs Steep against the entire library. Token/location records, grammar AST nodes, parser classifier and bootstrap state, the
Ruby DSL, IR records, and automaton actions use concrete domain types. Generated-parser reduction values, dynamic parser-table
cells, decoded JSON values, and user methods embedded as opaque Ruby source remain `untyped`; applications can reopen the generated
class in their own RBS files to declare embedded methods.

## Current Grammar IR

<!-- stable:current-ir:v1 -->

Top-level fields:

| Field | Meaning |
|---|---|
| `ibex_ir`, `schema_version` | `"grammar"`, current format |
| `class_name`, `superclass` | Generated Ruby class contract |
| `start`, optional `starts`, `expect`, `options` | Primary/ordered start names, unresolved S/R expectation, result/action flags |
| optional `params`, `printers` | Generated-constructor keywords and symbol-specific debug value formatters |
| optional `lexer` | Embedded independently versioned Lexer IR |
| `symbols` | Interned terminals and nonterminals; `$eof` id 0 and `error` id 1 |
| `productions` | Numeric LHS/RHS ids, action, precedence override, source origin |
| `user_code`, `conversions`, `warnings` | Concatenated code, external token expressions, structured diagnostics |
| `user_code_chunks` | Optional opaque chunks with first-code-line locations for compatible source mapping |

Warning records use the additive type vocabulary `undeclared_terminal`, `unused_terminal`, `unused_precedence`,
`unreachable_terminal`, `unreachable_nonterminal`, `duplicate_production`, and `empty_language`, and retain source locations.
The CLI applies display/error policy at the boundary;
normalization and IR serialization do not discard diagnostics.

A symbol has `id`, `name`, `kind`, `reserved`, optional `prec {associativity, level}`, `loc`, `display_name`, and
`semantic_type`.
A production has `id`, `lhs`, `rhs`, optional `action`, optional `prec_override`, and `origin`. Synthetic EBNF origins include
an additive, deterministic `expression` label used by text, DOT, and HTML presentation while numeric symbol identities remain
unchanged. An action has opaque `code`, `loc`, `named_refs [{name,index}]`, and `context_length`; middle-action helpers use the
last field to view preceding stack values.

IR objects and nested collections are frozen. JSON keys have deterministic order, so dump/load/dump is byte-stable.

Normalized grammars use the current format for declaration-free source and carry explicit nullable metadata:

| Record | Current-format metadata |
|---|---|
| grammar | `source_provenance {file, root, byte_span {start,end}}` |
| symbol | `doc` |
| production | `doc` and `expansion {parameter, inline, include_chain}` |
| action | `composition {strategy, fragments, plan {version, physical, steps}}`; new steps include nullable `result_type` |

The source-only text frontend supplies the source filename and leaves unknown metadata null. A resolved grammar also supplies its
canonical source root and each production's include chain while preserving its original-file origin. Lossless rule comments
populate symbol and user-production documentation, including through fragment resolution; synthetic EBNF helpers remain
undocumented. Parameterized specializations populate `expansion.parameter` with the template name and canonical structural
arguments while retaining the definition's include chain.
The current format adds one closed, root-owned `parser_contract`. Its `algorithm`, `entries`, and `cst_trivia` members each carry
`value`, `explicit`, and `loc`. An explicit member has an admitted value and source location; an unspecified member has all
three states fixed to `value: null`, `explicit: false`, and `loc: null`. Unspecified is not an encoding of the current built-in
default. The contract sits only at the root, so fragments cannot change parser-wide construction while their normalized
productions and source provenance remain composable.

Extended root grammars can populate `algorithm` and `entries` through one
domain-specific `parser ... end` declaration. The frontend rejects that block
in fragments and compatible mode, and rejects duplicate blocks, duplicate or
unknown keys, unknown values, and `algorithm auto` before normalization. The
typed configuration resolver treats those values as fixed grammar contracts:
canonical generation accepts only an absent or matching CLI request. Analysis
and grammar-test commands may move an explicitly different algorithm into a
reported noncanonical analysis origin; entry construction remains fixed. The
configuration inspector reads the same AST and import closure without running
actions or user sections.

`Serialize.load` and `Validator.validate` accept only the current Grammar IR format. Both declaration-free and
`parser`-declared sources write that same format, so there is no in-process migration path or compatibility reader.
Callers construct the current object directly through `IR::Grammar.new`; see
[ADR 0020](decisions/0020-grammar-ir-parser-contract.md).

The v1 stabilization freeze covers required core fields, meanings, ordering,
identity, and validation behavior. The future `x-` experimental namespace is
outside that freeze, but current schemas remain closed and reject unknown
fields. Experimental data must therefore begin in a new additive schema
version rather than weakening an existing document. See
[stability and deprecation](stability.md).

`Codegen::Documentation` renders normalized user rules and alternatives as escaped Markdown, self-contained accessible HTML, or
railroad SVG. The railroad renderer includes visible wrapped rule descriptions in its section-height calculation and exposes the
full escaped text through SVG descriptions. `ibex doc` resolves the same canonical include graph and writes to stdout or an
atomic file without generating or executing application parser code.

## Current Automaton IR

Top-level fields are `ibex_ir: "automaton"`, `schema_version`, `algorithm`, `grammar_digest`, embedded `grammar`, `states`,
optional `entry_states`, and `conflict_summary`. Embedding Grammar IR makes automaton JSON sufficient for code generation after
`--from=automaton-ir`. A multi-entry automaton maps every ordered grammar start name to its initial state.

Each state contains:

- merged items `{production, dot, lookaheads}`;
- named `transitions`;
- resolved terminal `actions` and nonterminal `gotos`;
- an optional reduce `default_action`, selected only when explicit error masks preserve every terminal lookup and reduce the
  total encoded ACTION entries;
- every conflict, including precedence-resolved conflicts and the resolution reason; multi-entry conflicts also carry their
  reachable `entries` and optional `composite` marker.

`conflict_summary.sr` counts unresolved default-shift conflicts for `expect`; `resolved_sr` counts retained precedence or
associativity decisions; `rr` counts reduce/reduce cells.

The current Automaton IR embeds the exact current Grammar IR, includes the parser contract in `grammar_digest`, and records
`entry_construction` as `shared` or `isolated`. Older documents are rejected rather than migrated. Callers construct the
current object directly through `IR::Automaton.new`.

`--from=grammar-ir` applies the current parser contract through the typed configuration resolver before constructing tables;
matching CLI values are allowed and conflicts are rejected with the contract location. `--from=automaton-ir` generates without
the original source and rejects algorithm/entry construction flags because its tables are already built. A generation
manifest records the grammar digest and contract separately from the embedded automaton's algorithm/entry facts and codegen-only
effective configuration. Static IR views validate opaque action strings but never execute them. Published Draft 2020-12
contracts for both current IR documents live under `schema/`; see
[ADR 0001](decisions/0001-separate-ir-pipeline.md).

`--emit=sets` is a deterministic analysis view rather than another IR: it emits lexically sorted nullable nonterminals and
FIRST/FOLLOW maps for nonterminals. DOT, Mermaid, and the self-contained searchable HTML report are deterministic presentation
views over Automaton IR.

## Construction algorithms and counterexamples

The `lalr` and `slr` strategies construct LR(0) states directly for a single entry. LALR lookaheads are the least fixed point of deterministic
shift, spontaneous-FIRST, and nullable-suffix propagation edges over item occurrences; SLR replaces completed lookaheads with
FOLLOW sets. Multiple entries seed distinct augmented canonical items and use canonical core merging because the direct
lookahead graph has a single-root contract. Canonical `lr1` retains the canonical collection. An explicit canonical-and-merge
LALR reference strategy proves byte equivalence without changing the Automaton IR algorithm label. `ielr` conservatively merges action-compatible canonical
states and refines partitions until outgoing transitions are congruent, avoiding LALR inadequacies without promising a minimum
state count. `--entry-isolation` instead constructs each start independently and concatenates the resulting state sets with
deterministic offsets. Shared builds attribute reachable entries to conflicts and compare isolated conflict fingerprints to
identify merge-created composite conflicts. All strategies use the same conflict resolver and default reduction pass. After a build, frozen diagnostic
`metrics` record the strategy and construction/final state counts, plus a canonical count only when one was actually built. See
[ADR 0007](decisions/0007-shared-parser-construction-pipeline.md).

`Ibex::LALR::Counterexample` consumes only Automaton IR. For each conflict it explores parser-stack configurations, forces the
competing actions, and searches for a common accepting suffix. A successful result contains both complete derivation trees and is
marked `unifying: true`. Search defaults to 32 tokens and 50,000 configurations; the Ruby and CLI APIs can set both positive
budgets. If no common sentence is found within them, the result is explicitly marked nonunifying and contains the deterministic
shortest reachability witness instead of claiming ambiguity.

`Ibex::Codegen::Explain` filters those immutable conflicts by state and canonical token identity before asking
`Counterexample#for_conflict` to search only the selected entries, then renders text or the versioned `explain` JSON analysis
shape. `Counterexample#all` retains its original all-conflict behavior. The view performs no additional parser analysis and does
not extend Grammar or Automaton IR.

`Ibex::Verify::Verifier` accepts validated Automaton IR and derives LR(0) or
canonical LR(1) collections from the embedded Grammar IR without calling the
parser builder. Default checks validate item/action soundness,
algorithm-specific lookaheads, expanded default reductions and error masks,
reachability, productivity, epsilon termination, resolver consistency, and
rebuilt plain/compact row equality. `--strict` adds collection completeness
and reports that same row equality as V5 rather than V4. The verifier does not
consume generated Ruby or a supplied executable table artifact. Its exact
shared dependencies, algorithm limits, resource semantics, fault mapping, and
non-goals are documented in the [verifier trust boundary](verifier-trust-boundary.md).
`ibex verify` uses exit statuses 0 for valid, 1 for a violation, and 2 for
reference-budget exhaustion.

`Ibex::Equiv` first compares normalized grammar structure, then generates
sentences in both directions and explores the product of two immutable LR
state-stack machines in breadth-first order. The product key includes both
stacks, statuses, and consumed-action counts; a supplied rule map also adds
both postorder reduction traces. The first reported token witness is therefore
shortest within the declared token/configuration bounds. Simulation uses only
Automaton IR actions and gotos. It validates both inputs with the independent
verifier and does not evaluate semantic actions. A rule map requests bounded
tree comparison; without one, only accepted language is compared. Every
successful bounded report explicitly states that it is not an equivalence
proof.

`Ibex::Fix` composes those two read-only safety oracles around a finite repair
space. It rebuilds a candidate through the shared construction pipeline, but
accepts it only after the target fingerprint disappears, other fingerprints
do not increase, independent verification succeeds, and bounded language plus
identity-mapped reduction traces find no difference. User actions remain
opaque. Source proposals are whole-file deterministic edits; the CLI delegates
application to the existing transactional writer and refuses aliased inputs.
`Ibex::Diff` and `Ibex::Metrics` are deterministic views over the same frozen
Grammar and Automaton IR. They do not add an IR stage or alter generated
parsers.

`Ibex::BisonImport` is a clean-room adapter in front of that frozen pipeline.
Its iterative scanner recovers declarations, production alternatives, source
positions, and opaque C actions under byte/token/rule/action budgets, then
emits ordinary extended source. It adds no frontend syntax or IR field.
Deterministic terminal/nonterminal namespaces prevent Bison casing and keyword
rules from changing symbol kinds. The report separates unsupported directives
that leave the recovered production graph complete from structural gaps.
Analysis may continue across either result, but Ruby generation rejects the C
action sentinel and `Fix` rejects structurally incomplete source. Pinned
third-party grammars exist only in temporary external CI directories; see the
[import guide](bison-import.md).

The repository's self-authored representative grammar feeds the current versioned `ibex_benchmark` v2 document. Its JSON Schema
is shipped beside the IR schemas, while committed environment-specific observations live under the matching
`benchmark/results/vN` directory. Timing and peak RSS remain non-gating; CI reproduces only deterministic structure and digests.
See the [benchmark guide](../benchmark/README.md).

## Runtime table contract

Generated subclasses expose `.parser_tables` with a required `format_version`, external `tokens`, display `token_names`, ACTION
and GOTO tables, per-state default actions, and production `{lhs,length,action}` records. The runtime validates the version before
reading input and rejects missing or unsupported formats with a regeneration instruction. The generator emits v6. For non-CST
tables, the runtime accepts v1's two-argument actions, v2/v3 explicitly marked five-argument location actions, v3 explicitly
marked six-argument composed actions, v4 one-Array values actions, and v5/v6 positional actions. Marker contracts are validated
before input. A CST table is executable only when it uses current format-v6 structured metadata; older or boolean CST shapes
must be regenerated. See
[ADR 0008](decisions/0008-versioned-runtime-package-boundary.md). Plain tables are arrays of Hash rows. Compact tables use row
displacement with offsets, values, and row-ownership checks; both expose equivalent lookups. Default reductions are restricted
to known token ids, and explicit error masks preserve the pre-optimization result of every declared terminal cell, including
the synthetic `error` terminal. Extended parser tables opt `expected_tokens` into lookahead correction: the runtime copies only
the state stack and simulates reductions and gotos for each declared terminal, without evaluating semantic actions. The explicit
`expected_tokens_exact` API exposes the same result for compatible tables. The deterministic size policy is fixed by
[ADR 0008](decisions/0008-versioned-runtime-package-boundary.md).

Runtime execution is packaged independently as `ibex-runtime`, with its own version and RBS tree. The generator package depends
on a compatible runtime series but does not duplicate runtime-owned files. Compact lookup values live in a runtime-safe leaf
file, while table construction remains generator-only. Normal output requires only `ibex/runtime`; `-E` embeds the same sources.
See [ADR 0008](decisions/0008-versioned-runtime-package-boundary.md).

The runtime maintains state and value stacks, pulls a lookahead only when required, and applies tagged `shift`, `reduce`,
`accept`, and `error` actions. Recovery pops to a state that shifts token id 1, suppresses repeated reports for three successful
shifts, and honors `yyerrok`. No-op shift, reduce, recovery, location-aware, and discard extension points observe successfully
committed events without changing parser results; the recovery hook retains the pre-pop error context and is distinct from an
ordinary token shift. A configured value printer affects only human `yydebug` output. Their ordering and payload contract is
extended additively by
[ADR 0010](decisions/0010-committed-runtime-observation.md). Grammar-declared
symbol printers are optional current IR metadata compiled into private methods and
an id-indexed table.

Ordinary generated tables are recursively frozen and made Ractor-shareable. Threads and Ractors share those tables but parse
through distinct instances; stacks, lookahead, lexer state, callbacks, observers, and semantic values are session-owned. A
single instance rejects overlapping drivers. Immutable `Runtime::ResourceLimits` values bound every stack push and recovery
entry with finite defaults. Exhaustion raises the structured `ResourceLimitError`; see
[ADR 0009](decisions/0009-isolated-parser-sessions.md).

Extended current Grammar IR may additionally carry synchronization terminals and ordered `%on_error_reduce` groups. Table
construction fills only otherwise erroneous ACTION cells with a unique highest-priority completed declared production. At
runtime, an explicit shift of the synthetic `error` token always wins; only when it is unavailable does panic recovery discard
through a configured synchronization token and pop to a state that accepts that retained lookahead. Generated parsers without
sync declarations omit the optional table field. The pull/push ordering and observer contract are fixed by
the runtime and grammar reference documentation.

The separate `Runtime::Parser#observe` API publishes ordered, immutable schema-v1 events for tooling. Its bounded sanitizer
copies only JSON data and never retains application identities or private stacks. With no observer, parse transitions construct
no Event, payload summary, or dispatch snapshot; parser initialization still creates its ownership mutex. Generated tables
contribute grammar digest, table format, state count, and production count to the `start` event. `Runtime::EventJSONLTracer`
exposes the versioned stream. The protocol and
exception/threading behavior are fixed by
[ADR 0010](decisions/0010-committed-runtime-observation.md).

Optional `Runtime::RepairPolicy` drives a bounded Dijkstra search over copied state stacks and buffered token identities. Search
uses explicit/default ACTION, GOTO, and production shape only; it never executes semantic code. A selected immutable edit plan is
reported once, then replayed through the ordinary runtime so actions and hooks remain committed-path effects. Pull lookahead,
push buffering, deterministic tie-breaking, fallback to yacc recovery, and no-policy compatibility are fixed by
[ADR 0012](decisions/0012-bounded-nonexecuting-analysis.md).

`Coverage::Collector` accepts only contiguous, complete runtime-event sessions with generated parser metadata. It counts entries
to the initial, shift, reduce-goto, and recovery states and counts committed reductions by production id. `Coverage::Report`
publishes ascending sparse hit arrays under the versioned runtime-coverage schema. Merge requires identical full grammar digest,
table format, and totals and uses checked addition. The coverage CLI only reads bounded JSON/JSON Lines and never loads generated
Ruby or executes semantic actions; collection, merge, threshold, and atomic-output policy are fixed by
[ADR 0010](decisions/0010-committed-runtime-observation.md).

`TableSimulation::Simulator` is a separate state-stack interpreter over validated Automaton IR. It resolves an explicit ACTION
cell before a default action, so explicit error masks remain authoritative, and never evaluates the opaque semantic-action
source stored in Grammar IR. Immutable steps expose state, lookahead, selected action source, reduction/goto metadata, and stack
depth. Action and stack budgets bound default/epsilon cycles and growth. The text/JSON CLI and versioned output contract are
fixed by [ADR 0012](decisions/0012-bounded-nonexecuting-analysis.md).

The current Grammar IR may carry ordered accept/reject source tests without adding them to parser tables. `GrammarTests::Runner` generates
one embedded parser and executes fresh parser instances in a separate Ruby process, distinguishing `ParseError` rejection from
lexer/application errors and bounding the whole suite by a timeout. The separate runner loads the generated file, so guarded
footer programs stay inactive. The source contract, isolation boundary, and CI behavior are fixed by
the grammar reference documentation.

## Clean-room boundary

Implementation work uses public racc documentation, CLI black-box behavior, and published LR algorithms only. racc implementation
sources and generated source are not inputs to the design. Self-authored compatibility grammars execute both outputs in separate
processes and compare observable results.

`RaccMigration::Checker` treats grammar code as opaque while reporting default-mode parse/normalization errors and known runtime
coupling. The separate harness generator emits source only; its output refuses an empty corpus and makes bounded child-process
execution explicit. The boundary is fixed by
[ADR 0012](decisions/0012-bounded-nonexecuting-analysis.md).
