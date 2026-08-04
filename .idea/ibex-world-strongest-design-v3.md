# Ibex 最強化計画 v3 — 宣言的で検証可能な Ruby LR Toolchain

- 対象: [`ydah/ibex`](https://github.com/ydah/ibex)
- 文書種別: 敵対的監査後の改訂設計
- 基準日: 2026-08-02
- 現行バージョン: `0.2.0`
- ステータス: Proposal
- 対応監査: `ibex-world-strongest-adversarial-review.md`
- 宣言的設定基準: `ibex-declarative-configuration-policy.md`
- 原則: **active roadmap と research parking lot を混ぜない**

---

## 1. Executive decision

Ibex の北極星を次に固定する。

> **Ruby で最も信頼でき、宣言的で、検証可能な LR parser generator /
> grammar engineering toolchain になる。**

ここでいう「宣言的」とは、通常生成される parser の意味や公開契約が、
隠れた command line ではなく grammar source から読めることを意味する。
CLI は同じ typed configuration model の別 frontend とし、今回の操作・出力・分析予算だけを主に所有する。

ここでいう「信頼できる」は、次を意味する。

- Racc grammar と runtime behavior の移行境界が明確
- grammar、automaton、table の各段階が inspectable
- conflict、ambiguity、error を bounded evidence として説明可能
- generated artifact が再現可能
- static tooling が user semantic action を実行しない
- lossless CST と semantic parse を同じ grammar から得られる
- Stable / Preview / Experimental が公開されている
- 強い主張が revision 固定の evidence に結び付く

次は active roadmap の必須目標にしない。

- 独自 package registry
- 複数言語 runtime
- generic language workbench
- GLR/RNGLR
- attribute grammar
- scannerless parsing
- formatter/query の独自 DSL

これらは external demand と採用 gate を通過した場合だけ研究する。

---

## 2. Primary users

## 2.1 Primary persona A — Racc parser maintainer

必要なもの:

- grammar compatibility
- migration check
- behavior harness
- generated parser API compatibility
- precise incompatibility report
- Ruby version/runtime matrix
- performance evidence
- stable release and deprecation policy

この persona に対する価値は、機能数より「移行して壊れないこと」である。

## 2.2 Primary persona B — Ruby language / DSL tool author

必要なもの:

- deterministic LR choices
- generated lexer or lexer contract
- typed semantic values
- AST/CST
- error diagnostics
- grammar tests
- editor-facing syntax session
- source fidelity
- reproducible generation

## 2.3 Secondary persona — grammar engineer / parser researcher

必要なもの:

- Grammar IR
- Automaton IR
- SLR/LALR/IELR/LR1 comparison
- conflict explanation
- counterexamples
- diff/equiv
- verifier
- fuzz/reducer
- import analysis

## 2.4 Explicit non-primary users

- ten-language code generationを必要とする利用者
- arbitrary ambiguous grammar をそのまま実行したい利用者
- full IDE platform を自動生成したい利用者
- network package registry を parser generator に求める利用者

これらを満たすために primary users の契約を複雑にしない。

---

## 3. Current baseline

現行 Ibex はすでに次を持つ。

- direct LALR(1)、SLR(1)、canonical LR(1)
- canonical state partition による IELR path
- compatible / extended grammar mode
- EBNF、parameterized、inline、middle action、multiple entry、import
- generated lexer
- semantic types、AST、RBS
- stable batch Red/Green CST
- experimental syntax-only incremental CST
- formatter、LSP、playground
- conflict explanation、ambiguity search、equiv、diff、fix、fuzz、reduce
- versioned Grammar/Automaton/Lexer IR
- independent verifier
- generation manifest
- transactional publication
- public migration/performance/error evidence

参照:

- [`README.md`](https://github.com/ydah/ibex/blob/main/README.md)
- [`docs/architecture.md`](https://github.com/ydah/ibex/blob/main/docs/architecture.md)
- [`docs/stability.md`](https://github.com/ydah/ibex/blob/main/docs/stability.md)
- [`docs/release-readiness.md`](https://github.com/ydah/ibex/blob/main/docs/release-readiness.md)

したがって最初の課題は新アルゴリズムではなく、**現行 claim の完成と採用証拠**である。

---

## 4. Correct trust model

安全境界を「解析は何も実行しない」と単純化しない。

| Execution path | Grammar parser action | Generated lexer action | User header/inner/footer | Trust |
|---|---:|---:|---:|---|
| grammar source parse/normalize | no | no | no | static |
| conflict/diff/equiv/verify | no | no | no | static |
| grammar formatter/LSP | no | no | no | static |
| generated semantic parse | yes | yes | yes at class load | application code |
| generated syntax-only parse | no | **yes** | generated class may load user code | trusted application boundary |
| safe syntax workbench profile | no | declarative builtins only | no | nonexecuting profile |
| generalized forest experiment | no | restricted profile | no | research |

### 4.1 Static non-execution guarantee

Static commands may consume validated source/IR/table data but may not:

- require generated application parser
- compile semantic action
- invoke lexer action
- load user header/inner/footer
- call application hooks

### 4.2 Runtime warning

Generated parser execution is not a sandbox.
`parse_syntax` suppresses production actions but the existing generated lexer still executes lexer actions.

### 4.3 Safe syntax profile

将来「untrusted source を editor で解析できる」と主張する場合、次を要求する。

- declarative lexer
- no Ruby header/inner/footer
- no parser action
- no arbitrary conversion
- resource limits
- data-only parser tables
- explicit encoding

---

## 5. What “strongest” means

## 5.1 Evaluation axes

| Axis | Ibex target | Scope |
|---|---|---|
| Migration | public Racc grammars with documented adapters | Ruby |
| Correctness | independently checked Grammar/Automaton/table artifacts | deterministic LR |
| Diagnostics | actionable conflict/error evidence | bounded, reviewed |
| Syntax tooling | lossless CST and safe incremental syntax sessions | generated lexer constraints explicit |
| Performance | no regression on representative Ruby workloads | same environment/config |
| Operations | reproducible, transactional, versioned artifacts | released surfaces |
| Interoperability | loss-reporting imports | analysis first |

## 5.2 Scoped claims

次のように corpus と trust assumptions を必ず付ける。

Bad:

> fault detection 100%

Good:

> committed v1 fault corpus の20/20 mutationを検出した。

Bad:

> grammar is unambiguous

Good:

> max 12 tokens / 100,000 configurations では ambiguity witness を検出しなかった。

Bad:

> generated parser is independently verified

Good:

> embedded Grammar IR、Automaton IR、plain/compact table data の整合を independent checker が検証した。
> Opaque Ruby actions、runtime implementation、application hooks は対象外である。

---

## 6. Strategic moat

Ibex は次の組合せで差別化する。

## 6.1 Migration moat

- Racc-compatible source
- public black-box behavior harness
- migration diagnostics
- adapter generation
- source mapping
- no native extension

## 6.2 Analysis moat

- multiple deterministic LR algorithms
- conflict attribution and concrete witnesses
- bounded ambiguity/equivalence
- independent automaton verification
- grammar diff/metrics/fix
- versioned closed IR

## 6.3 Syntax moat

- semantic parse and Red/Green CST from one grammar
- exact source reconstruction
- error-containing trees
- persistent editing/diff
- syntax-only incremental reuse
- typed CST views

## 6.4 Declarative contract moat

- canonical parser construction を grammar から読める
- parser-wide contract と invocation request を分類する
- CLI と grammar が一つの typed configuration model を共有する
- effective value、origin、override policy を説明できる
- source-declared contract が Grammar IR round-trip で失われない
- hidden semantic-affecting generation flags を減らす
- generic CLI option dump ではなく domain-specific declaration を使う

第一候補は次である。

- `parser.algorithm`
- `parser.entries`
- `cst.trivia`

一方、table encoding、embedded runtime、output path、watch、analysis budgets は grammar に入れない。

これら四つの moat に直接寄与しない機能は conditional または research とする。

---

## 7. Decision gates

新しい public feature は実装前に以下を通す。

## DG-0 — Problem gate

- 誰が困っているか
- 現行 workaround
- public grammar / reproducible fixture
- なぜ既存 feature では不足か

実ユーザーがいない研究は `Research` と表示する。

## DG-1 — Semantics gate

次を文章と executable examples で固定する。

- accepted input
- rejected input
- tie-break
- error behavior
- source mapping
- interaction with actions/CST/recovery
- unsupported cases

## DG-C — Declarative configuration admission gate

CLI concept に grammar syntax を与える場合、
`ibex-declarative-configuration-policy.md` の Admission Test を通す。

必須確認:

- parser/language/public syntax contract に関係するか
- build ごとに永続すべきか
- static に検証できるか
- root/fragment composition を定義できるか
- IR と manifest に保存できるか
- CLI conflict を fixed/minimum/default のいずれかで解決できるか
- operation、path、presentation、budget、packaging ではないか

CLI flag spelling を generic key-value として grammar にコピーしない。

## DG-2 — Oracle gate

- independent reference
- small exhaustive model
- black-box external implementation
- property relation
- fault injection

自己実装だけを oracle にしない。

## DG-3 — Boundary gate

- Grammar IR impact
- table ABI impact
- runtime gem impact
- generated source impact
- compatible mode
- action execution
- path/network boundary
- schema migration

## DG-4 — Evidence gate

- representative corpus
- deterministic structural evidence
- performance observation
- adverse cases
- limitation publication

## DG-5 — Adoption gate

Experimental から Preview/Stable へ上げる条件:

- external use
- two released versions where policy requires
- no specification churn
- docs/tooling
- migration path
- exact-release rerun

---

## 8. Active architecture

```text
racc-compatible / extended grammar source
                 |
                 v
      lossless self-hosted frontend
                 |
          contained resolver
                 |
          +------+------+
          |             |
      Grammar AST   root declarations
          |             |
          +------ typed configuration resolver
                 |             ^
                 |             |
             Grammar IR     CLI/project inputs
                 |
       +---------+----------+
       |                    |
deterministic LR build   static analysis
       |                    |
  Automaton IR      explain/equiv/diff/fix
       |
  executable table artifact
       |
  Ruby code wrapper + opaque actions
       |
    ibex-runtime
```

Configuration resolver は各値について value、owner、origin、override policy を保持する。
Grammar Contract と Invocation Request を同じ untyped hash に混ぜない。

### 8.1 New near-term artifact

Stronger verification should first introduce a **data-only executable table artifact**.

```text
grammar.y
  -> Grammar IR
  -> Automaton IR
  -> parser-tables.ibex.json or canonical binary
  -> generated Ruby wrapper references/embeds table bytes
```

Independent checker can validate the data artifact without parsing arbitrary Ruby source.

### 8.2 Authority rules

- Grammar source is authoring authority.
- Grammar IR is normalized grammar authority.
- Automaton IR is deterministic construction authority.
- Table artifact is executable table authority.
- generated Ruby is packaging/wrapper plus opaque application action code.
- derived tree schema is not a second grammar authority.
- verifier report is evidence, not source of truth.
- grammar owns canonical parser contracts admitted by the configuration policy.
- CLI owns one-shot operations、paths、presentation、analysis budgets。
- project build policy owns equivalent representation and deployment choices。
- a conflicting CLI value never silently changes a grammar-owned fixed contract。

---

## 9. ABI and schema policy

Every runtime-facing proposal must answer:

1. Does parser-table format v6 suffice?
2. Is the new data generator-only?
3. Can it be a separately versioned sidecar?
4. Must runtime reject an old/new combination before token consumption?
5. Is embedded runtime affected?
6. Is `ibex-runtime` minor/major version change required?
7. Can generated bytes remain unchanged when feature is off?

### 9.1 Preferred order

1. internal object
2. versioned report
3. sidecar data artifact
4. opt-in generated constant
5. new table format
6. Stable ABI

新 table format は最後に選ぶ。

### 9.2 Schema budget

独立 schema は次を満たす場合だけ追加する。

- external persistence/interchange が必要
- in-memory object では不足
- owner と migration policy がある
- source artifact digest と結び付く
- duplicate authority にならない

---

## 10. Roadmap

## Stage 0 — Finish v1.0 truthfully

### Deliverables

- 10-case error UX external review
- exact release revision rerun
- reproducible gem evidence
- stable API lock
- release provenance
- public limitations

### Exit

- release report の decision と evidence が一致
- no new Stable grammar syntax
- current feature freeze を正しく解除

---

## Stage 1 — Prove current value

### Deliverables

- public workload registry
- migration corpus expansion
- Preview feature decision table
- competitor comparison protocol
- claim registry
- error/conflict UX round 2
- runtime/table ABI evolution note
- matrix-growth strategy

### Exit

- primary personas に対応する public use cases
- new work の優先順位を usage data で決められる
- active P0 が8件以内

---

## Stage 2 — Declarative parser configuration

この stage は、CLI option を無制限に grammar へ移すものではない。
parser の canonical contract を source-owned にする。

### First-wave admitted concepts

- parser construction algorithm
- multiple-entry construction strategy
- CST trivia ownership

Existing equivalents are preserved:

- `pragma extended`
- class header superclass
- action ABI `options`
- `start`
- `expect` / `%expect-rr`

### Internal model first

1. current CLI option inventory
2. owner classification
3. typed configuration key registry
4. fixed/minimum/invocation merge algebra
5. value origin/provenance
6. deterministic effective-config report
7. manifest coverage
8. IR persistence decision
9. grammar syntax last

### Proposed source direction

Illustrative only:

```text
class ExampleParser
pragma extended
pragma cst

parser
  algorithm ielr
  entries isolated
  cst_trivia balanced
end
```

- parser block is root-only
- generic key-value is rejected
- `algorithm auto` is initially rejected
- `pragma cst` remains a Stable compatibility surface
- no declaration means current CLI/default behavior

### CLI behavior

Canonical generation:

- no source declaration -> current CLI/default
- declaration + matching CLI -> success
- declaration + conflicting CLI -> positioned error

Analysis commands may explicitly select another algorithm, but report it as a noncanonical override.

### IR and manifest

- source declarations must survive `grammar-ir` round-trip
- a Grammar IR v3 or separate parser-contract IR requires ADR
- v2 migration must not invent historical CLI values
- generation manifest must record effective value and origin
- `cst_trivia` must be added to the effective manifest inventory
- `ibex config` exposes all values and origins without executing user code

### Exit

- every CLI option has an owner class
- no unclassified option
- first-wave contract settings are source-declarable
- hidden semantic-affecting flags are absent from canonical generation
- declaration-free compatible grammar behavior remains unchanged
- frontend、formatter、LSP、IR、manifest、test all agree

## Stage 3 — Verifiable generation bundle

“proof-carrying”とは呼ばない。

### Scope

検証する:

- input digests
- Grammar IR digest
- Automaton IR semantics
- action/goto/table consistency
- plain/compact equivalence
- executable table artifact digest
- generated wrapper/artifact digest binding

検証しない:

- opaque semantic action
- lexer action
- Ruby runtime implementation
- application hooks
- side effects
- grammar unambiguity

### Deliverables

- verifier trusted-computing-base document
- data-only table artifact
- verification report schema
- non-cyclic manifest binding
- fault injection

Publication order is `table/wrapper/report -> generation manifest`。
The report binds input/IR/table digests; the manifest binds the report and every published artifact。
The report must not contain the manifest digest, which would create a circular hash dependency。
Canonical evidence digests use logical artifact identity rather than checkout-dependent absolute paths。

### Exit

第三者が generated application code をロードせず table artifact の整合を確認できる。

---

## Stage 4 — Syntax services kit

Generic IDE platform ではなく、syntax services に限定する。

### Initial API

```ruby
profile = MyParser.syntax_execution_profile
# => :trusted_application_code または :declarative

session = MyParser.syntax_session(source)
session.edit(edits)
session.syntax_root
session.diagnostics
```

既存 generated class は load 時点で user header/footer を実行し得るため、
session 作成時の boolean flag で sandbox 化できるとは表現しない。

### Safety profiles

- `:trusted_application_code`: current generated class。class load と lexer action を信頼する
- `:declarative`: action-free syntax artifact + declarative lexer
- parser production actions are never run inside the syntax session

`safe: true` のような flag で、すでに load 済みの arbitrary Ruby code を安全化したことにはしない。

### Possible services

- syntax diagnostics
- exact expected-token completion
- selection/folding from CST
- source-preserving edits
- grammar-specific hooks

### Not automatic

- semantic rename
- type checking
- references
- semantic tokens
- workspace index

これらは application semantics を必要とする。

### Query path

1. Ruby typed API
2. cacheability model
3. two real consumers
4. only then query DSL

### Formatter path

1. trivia-only formatter experiment
2. parse/format/parse relation
3. comment policy
4. two real consumers
5. only then formatter DSL

---

## Stage 5 — Conditional direct IELR

direct IELR は feature gap ではなく conditional optimization/research である。

### Trigger

- at least two representative grammars where current canonical IELR construction exceeds a predeclared practical budget
- users need IELR rather than LALR/LR1 workaround
- algorithm owner exists

### Specification

Before implementation:

- define adequacy invariant
- define conflict preservation
- define state correspondence relation
- define deterministic numbering policy
- define construction limits
- define verifier strategy without full canonical enumeration at scale

### Oracle

Small grammars:

- canonical LR(1)
- exhaustive bounded sentences
- existing IELR path as regression, not sole oracle
- independent verifier

Large grammars:

- local propagation invariants
- certificate/witness for splits
- table bisimulation or bounded differential execution
- canonical oracle optional/inconclusive, not mandatory

### Legal boundary

GNU Bison implementation is GPL.
Do not translate or structurally copy it into MIT Ibex.
Use published algorithms/specifications and an independently designed implementation.

### Exit

- no merge-introduced conflict; action candidate sets correspond to canonical LR(1) under the declared resolver semantics
- deterministic output
- current LALR/default path unchanged
- real workload improvement
- verifier does not erase the scale benefit

---

## Stage 6 — Conditional declarative automaton lexer

Do not call it a backend replacement for current Ruby Regexp lexer.

### Two lexical profiles

### `regexp`

- current Ruby Regexp match semantics
- leftmost-first inside a rule
- longest returned lexeme across rules
- arbitrary Ruby lexer actions
- trusted application execution

### `automaton`

- explicitly specified regular-language semantics
- maximal munch
- declaration-order rule tie
- no lookbehind/backreference/semantic predicate
- declarative state transitions
- optional pure builtin conversions
- deterministic automaton
- resource-bounded construction

Example difference:

```ruby
/\A(?:a|ab)/.match("ab")[0] # "a" under Ruby Regexp
```

An automaton language containing both `a` and `ab` selects `ab` under maximal munch.
Automatic migration is therefore unsafe.

### Adoption trigger

At least one:

- real ReDoS/worst-case requirement
- portable/action-free syntax requirement
- measured generation/runtime win on representative lexers
- incremental lexing requirement impossible with opaque actions

### Implementation sequence

1. semantics document
2. programmatic regex AST
3. reference NFA interpreter
4. DFA construction with limits
5. differential properties against the reference interpreter
6. Ruby runtime spike
7. benchmark
8. syntax proposal last

### Construction limits

- regex AST nodes
- fragment expansions
- Unicode ranges
- NFA states/edges
- DFA states/transitions
- determinization work
- serialized bytes
- runtime token buffer bytes
- maximum token bytes

### Unicode

Must version:

- scalar-value definition
- property database
- case-fold behavior
- encoding policy
- invalid byte behavior

Do not silently inherit one part from Ruby Regexp and another from bundled tables.

---

## Stage 7 — Conditional true incremental lexing

Only `automaton` or another snapshot-complete declarative lexer qualifies initially.

### Restart state

- byte offset
- decoding state
- line/column policy
- lexical state stack
- layout stack
- pending trivia
- token-channel state
- pure conversion identity

### Resync proof

Reuse suffix only when:

- restart state is equal
- source suffix is byte-identical
- lexer transition semantics/version are equal
- no external mutable state
- all derived token values are reproducible

A fixed number of equal tokens is only a heuristic and is not accepted as a soundness proof.

### Fallback

Any uncertainty -> fresh full lex/parse.

### Exit

Random edits compare full result:

- token kinds
- text
- values
- locations
- states
- trivia
- diagnostics
- CST

---

## Stage 8 — Recovery improvement built on current engine

Current `RepairSearch` already supplies bounded Dijkstra search and deterministic ranking.
Reuse it.

### First target

syntax-only editor repair:

- missing/deleted/replaced token in CST
- fix-it text edit
- no semantic action replay
- no invented application value

### Semantic runtime policy

Only after explicit value model:

- missing sentinel
- token-specific default
- parser remains syntax-only
- application callback marked unsafe
- or reject repair

Never silently use `nil`.

### Local policy problem

`recover statement` is not implemented until policy applicability is defined over:

- LR states
- active items
- production provenance
- competing scopes
- deterministic precedence
- conflict report

### Exit

- existing repair corpus preserved
- no second search engine
- external usefulness review
- CST source fidelity
- explicit budget exhaustion

---

## 11. Research parking lot

## 11.1 GLR/RNGLR

Trigger:

- two real grammars require intentional ambiguity
- LR1/IELR and grammar refactoring are inadequate
- action-free/declarative tree model is acceptable
- maintainer capacity exists

First experiment:

- separate gem/IR
- action-free grammar
- token-based parsing
- GSS/SPPF
- bounded forest
- no opaque Ruby action
- no parser-to-lexer feedback
- no Stable promise

Do not make GLR a condition for calling Ibex strong.

## 11.2 Portable runtime

Trigger:

- external runtime implementer
- action-free portable use case
- need for a language-neutral Core Grammar IR

Current Grammar IR is Ruby-specific and is not the portable ABI.

## 11.3 Package reuse

Use:

- local contained imports
- gem-packaged fragments
- Bundler-resolved dependencies
- explicit source roots
- digests

Do not build an Ibex registry or package solver.

## 11.4 Query / formatter DSL

Implement only after the Ruby API has two independent consumers and semantics are stable.

## 11.5 Attribute grammar and language injection

Research only. They require semantic dependency and nested source-map models beyond current parser-generator core.


## 11.6 Contextual tokens

Research only until parser/lexer feedback semantics are specified.

Must define:

- base and contextual token both expected
- candidate ordering
- recovery/repair behavior
- table simulation
- multiple entry
- incremental restart dependency on parser state

Do not treat `when expected` as a local lexer optimization.

## 11.7 Layout-sensitive lexing

A future first scope is Python-style indentation tokens only。
Do not claim Haskell or YAML compatibility from a generic INDENT/DEDENT stack。
Haskell layout insertion and YAML lexical/layout context require separate specifications。

---

## 12. Competitive evaluation protocol

No comparative claim without a versioned report.

## 12.1 Comparison set

- Racc
- Lrama
- GNU Bison
- Menhir
- Tree-sitter
- ANTLR

Add other tools only with a concrete reason.

## 12.2 Categories

| Category | Measurement |
|---|---|
| Grammar classes | supported semantics, not syntax count |
| Diagnostics | witness correctness + human usefulness |
| Recovery | accepted repair quality and unsafe cases |
| Incremental | fresh equivalence after edits |
| Artifacts | size, reproducibility, inspectability |
| Verification | exact trusted computing base |
| Performance | same input/environment/config |
| Migration | public behavior suite |
| Declarative completeness | semantic-affecting config、origin、hidden flags |
| Ecosystem | documented, not converted to a score |

## 12.3 Rules

- public interfaces only
- exact revisions
- exact commands
- no generated-source reverse engineering when prohibited by protocol
- failure rows remain
- “not comparable” is valid
- subjective UX requires external reviewers
- aggregate numbers never imply semantic equivalence

---

## 13. Corpus strategy

## 13.1 Core theoretical corpus

- LR0 / SLR / LALR / LR1 distinctions
- LALR inadequacy
- precedence and associativity
- reduce/reduce
- nullable chains/cycles
- multiple entry
- conflict counterexamples
- grammar-state explosion families
- malformed IR/table mutations

## 13.2 Ruby migration corpus

Each entry records:

- project/revision
- grammar path
- license
- public command
- adapter
- behavioral suite
- known unsupported behavior
- generation/runtime measurements

## 13.3 Syntax corpus

- Unicode identifiers
- stateful strings
- comments/trivia
- error recovery
- mixed newlines
- invalid UTF-8 policy
- streaming chunks
- random edits
- early accept
- push/pull

## 13.4 No vanity thresholds

10,000 productions等の数を先に成功条件にしない。

Publish:

- scaling curve
- failure resource
- representative workloads
- synthetic shape
- environment

---

## 14. Test architecture

## 14.1 Core matrix

Keep the current core axes:

- algorithm
- table
- CST
- locations
- entries

Do not add every new feature to the same full Cartesian product.

## 14.2 Interaction map

For each feature, declare which core axes can affect it.

Example:

| Feature | algorithm | table | CST | locations | entries |
|---|---:|---:|---:|---:|---:|
| table verifier | yes | yes | no | no | yes |
| query API | no | no | yes | yes | no |
| declarative lexer | no | no | yes | yes | no |
| local recovery | yes | yes | yes | yes | yes |

Use:

- pairwise combinations
- feature-specific exhaustive tests
- scheduled long fuzz
- zero-cost golden
- fault injection
- promotion-only full interaction review

## 14.3 Oracle independence

- direct IELR: canonical oracle only on feasible small grammars
- DFA: NFA/reference interpreter, not Ruby Regexp
- incremental: fresh full lex/parse
- recovery: table simulator + apply-and-reparse
- table bundle: independent decoder/checker
- GLR research: tiny exhaustive chart/oracle

---

## 15. Metrics

All metrics include scope.

## 15.1 Release

- required gates passed on exact SHA
- artifact digest
- stable declaration diff
- external review identity/date

## 15.2 Adoption

- public migrations
- public extended grammar users
- open issues by feature
- adapters required
- feature removal/promotion decisions

No arbitrary “10 users” threshold; record evidence and predeclare promotion criteria.

## 15.3 Correctness

- committed fault corpus detected
- property run seed/count
- oracle corpus mismatch
- fresh/incremental mismatch
- schema invalid fixtures rejected

## 15.4 Declarative configuration

- classified CLI options / total options
- unclassified option count
- grammar-owned contract keys with source syntax
- canonical generation hidden semantic flag count
- effective values with provenance
- IR round-trip losses
- conflicting overrides detected
- manifest configuration omissions

## 15.5 Performance

- generation time/allocation
- reuse parse time/allocation
- new-instance cost
- generated bytes
- lexer token throughput
- incremental edit work
- peak state/item counts

Timing is observation unless a feature-specific, same-environment regression policy is predeclared.

---

## 16. Risks and controls

| Risk | Control |
|---|---|
| Preview surface grows | syntax budget; active roadmap only |
| algorithm research displaces users | problem gate |
| DFA changes tokens | separate lexical profile |
| incremental reuse is unsound | exact state + unchanged suffix proof |
| verification wording overclaims | trusted-computing-base document |
| runtime ABI breaks | mandatory ABI impact assessment |
| test combinations explode | interaction map / covering strategy |
| GLR action semantics are wrong | action-free first |
| custom ecosystem duplicates Bundler | no custom solver/registry |
| derived schema diverges | one authority + digest binding |
| GPL implementation contamination | paper/spec-based independent implementation |
| human UX evidence is weak | separate release review from comparative study |
| grammar becomes a CLI dump | admission policy and domain-specific syntax |
| CLI silently overrides grammar | fixed/minimum algebra and provenance |
| fragments fight over global settings | root-only first-wave contracts |
| config disappears through IR | IR persistence gate before syntax release |
| build representation pollutes grammar | project build policy boundary |

---

## 17. Active priorities

### P0 — now

1. v1 external error review
2. exact release rerun
3. protected provenance
4. trust-boundary correction
5. claim/comparison protocol
6. public workload registry
7. Preview maturity decisions
8. ABI/test-matrix policy

### P1 — after v1

1. declarative configuration admission inventory
2. typed effective configuration and provenance
3. `ibex config`
4. parser algorithm / entry strategy / CST trivia declarations
5. migration corpus expansion
6. error/conflict UX round 2
7. data-only table artifact
8. verifier TCB and verification report
9. syntax services API
10. existing repair safety improvements

### Conditional

- direct IELR
- direct multi-entry LALR
- automaton lexer
- true incremental lexing
- query API/DSL
- formatter
- local recovery syntax

### Research

- GLR/RNGLR
- portable runtime
- attribute grammar
- language injection

### Rejected for core roadmap

- custom Ibex package registry
- automatic Ruby Regexp -> DFA conversion
- generalized parsing with opaque actions
- “proof-carrying” claim for generated Ruby
- capability version constraints in grammar before a concrete negotiation need
- generic `cli_option` / stringly-typed configuration syntax
- output paths、watch、report formats、analysis budgets in grammar

---

## 18. Final decision

Ibex を最強にするために、すべての parser/tooling feature を持つ必要はない。

最も強い到達像は次である。

> **Racc から安全に移行でき、LR grammar の構造と conflict を深く調べられ、
> generated automaton/table を独立に検証でき、必要なら lossless CST と incremental syntax tooling まで
> Pure Ruby で一貫して使える。**

この到達像では、文法ファイルを parser contract の readable source of truth とする。
通常生成の algorithm、entry strategy、CST ownership が隠れた command にしか存在する状態を解消し、
一方で output path、packaging、observation、analysis budget を文法へ流入させない。

この到達像は現行 Ibex の延長線上にあり、外部 evidence で検証できる。
direct IELR、declarative lexer、workbench はその北極星を強める場合だけ採用する。
GLR、portable runtime、package ecosystem は「ないと最強でない機能」ではなく、
需要が発生したときに別判断する研究対象である。
