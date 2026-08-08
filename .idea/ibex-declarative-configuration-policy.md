# Ibex 宣言的設定の採用基準

- 対象: [`ydah/ibex`](https://github.com/ydah/ibex)
- 文書種別: Grammar/CLI configuration policy
- 基準日: 2026-08-04
- ステータス: Proposal
- 関連文書:
  - `ibex-world-strongest-design-v3.md`
  - `ibex-world-strongest-work-orders-v3.md`
  - `ibex-world-strongest-adversarial-review.md`

---

## 1. 原則

Ibex の文法ファイルは、単に production rule を並べるファイルではなく、
**言語と、その言語を処理する parser の永続的な契約を宣言するファイル**である。

したがって、通常の parser 生成に毎回必要となる重要な CLI option があり、
その値が文法と不可分であるなら、それを build command の暗黙知として残すべきではない。

ただし、次は同義ではない。

- CLI option を文法内でも宣言できるようにする
- CLI option をそのまま文法へコピーする
- あらゆる option を文法に入れる
- 文法ファイルを build script にする

Ibex が採るべき方針は次である。

> **一つの型付き設定モデルを用意し、設定の所有者が文法であると判定された項目だけに、
> domain-specific な文法表現を与える。CLI は同じ設定モデルに値を供給する別 frontend とする。**

次のような generic syntax は採用しない。

```text
# bad: CLI spelling に文法を従属させる
cli_option "--algorithm=ielr"
cli_option "--cst-trivia=balanced"

# bad: 型も責務もない key-value dump
set "algorithm" "ielr"
set "output" "parser.rb"
```

文法は「何を生成する契約か」を表し、CLI は「今回何を実行するか」を表す。

---

## 2. なぜ最強化につながるのか

重要な parser contract が CLI にしかない場合、同じ `grammar.y` から異なる parser が生成される。

例:

```sh
ibex --algorithm=lalr grammar.y
ibex --algorithm=ielr grammar.y
ibex --entry-isolation grammar.y
ibex --cst-trivia=drop grammar.y
ibex --cst-trivia=balanced grammar.y
```

これらは単なる表示差ではない。

- algorithm は state、conflict、選択される action に影響し得る
- entry isolation は multiple entry の state graph と conflict attribution に影響する
- CST trivia policy は tree ownership、座標、incremental API の利用可能性に影響する
- `drop` は source coordinate と incremental API を意図的に無効化する

通常生成に必要な値が command line、Rake task、CI file にだけ存在すると、
grammar を読んでも parser contract が分からない。

宣言的設定により、次が可能になる。

1. grammar 単体から canonical parser contract を理解できる
2. build command の hidden flag を減らせる
3. Grammar IR / Automaton IR / manifest の再現性を高められる
4. LSP が設定値を補完・検証できる
5. formatter が設定を lossless に扱える
6. import/migration が失われた設定を明示できる
7. CLI と grammar の競合を静的に検出できる
8. `ibex config` で値と出所を説明できる
9. parser generator の利用者と grammar author の責任境界が明確になる

GNU Bison が LR construction type を `%define lr.type` として grammar 側から選べるのも、
construction strategy が永続的な grammar/parser contract になり得るためである。
Ibex でも同じ発想は有効である。ただし Bison syntax の模倣ではなく、
Ibex の責務と compatibility policy に合わせて設計する。

---

## 3. 「宣言的」の定義

Ibex における宣言的設定は、次を満たす。

### 3.1 What を表し、How/When を表さない

Good:

```text
parser
  algorithm ielr
  entries isolated
end
```

Bad:

```text
if ENV["CI"]
  run with --algorithm=ielr
end
```

### 3.2 同じ入力から同じ意味を得る

設定値は次に依存してはならない。

- current time
- current working directory
- machine hostname
- secret
- network response
- mutable environment variable
- shell command
- filesystem discovery whose result is not an explicit input

### 3.3 静的に型検査・検証できる

- enum は既知の値だけ
- number は range を検査
- setting combination を normalize 前に検査
- unknown key は error
- duplicate declaration は error
- source location を保持

### 3.4 source order に意味を持たせない

同じ scope 内の独立設定を並び替えても意味は変わらない。
優先順位が必要な機能は、順番ではなく明示的な priority model を持つ。

### 3.5 user code を実行しない

設定の解釈に Ruby action、header、footer、external command を使わない。

---

## 4. Grammar Configuration Admission Test

CLI concept に grammar syntax を与えるには、以下の **A1–A8 をすべて満たし**、
かつ **X1–X7 のいずれにも該当しない**ことを原則とする。

## A1 — Contract relevance

少なくとも一つに影響する。

- accepted token/string language
- parse action/conflict behavior
- semantic action ABI
- parser public API
- AST/CST shape or ownership
- recovery semantics
- canonical parser construction
- source-local correctness invariant

単に出力形式や画面表示を変えるだけなら不合格。

## A2 — Persistence

grammar の通常利用者が、通常の build ごとに同じ値を使うことが合理的である。

「今日は調査のために変える」「CI だけ厳しくする」値は不合格。

## A3 — Reproducibility

値が grammar source と versioned inputs だけから再現できる。

## A4 — Static validation

frontend/normalizer が application code を実行せず妥当性を検査できる。

## A5 — Composition

次のいずれかを明確に定義できる。

- root-only
- fragment-local
- additive merge
- exact-match requirement
- monotone lower bound

「import 順で最後に勝つ」は採用しない。

## A6 — Stable domain meaning

CLI flag spelling や一つの code generator implementation ではなく、
parser/grammar domain の概念として名前を付けられる。

例:

- `parser algorithm ielr`: domain concept
- `emit packed Ruby constant`: backend implementation detail

## A7 — Serialization and provenance

値を versioned IR または明示的な companion contract に保持できる。
effective value と origin を manifest/report に記録できる。

## A8 — Override safety

grammar と CLI の両方に値がある場合の解決規則を決定できる。

- fixed
- minimum
- overrideable default

silent and unreported override は認めない。

---

## X1 — Operation selection

次のような「今回何をするか」は grammar に入れない。

- emit
- check
- watch
- format
- diagnose
- diff
- fuzz
- reduce

## X2 — Paths and publication destinations

- output file
- report path
- DOT/HTML/SVG path
- manifest path
- log path

grammar の置き場所や checkout に parser contract を依存させるため不合格。

## X3 — Presentation

- locale
- color
- verbose
- human-readable report format
- help/version output

## X4 — Caller resource budgets

- timeout
- max configurations
- max tokens
- max output bytes
- fuzz count
- reducer trials

budget は caller の資源と evidence scope を表す。
grammar に置くと、bounded result を grammar property と誤認しやすい。

## X5 — Packaging/deployment

- embedded runtime
- shebang
- frozen-string comment
- table encoding
- target output companion selection

同じ grammar を複数 deployment で利用できなくなるため不合格。

## X6 — Environment or secrets

- network endpoint
- credential
- environment-dependent conditional
- shell expansion

## X7 — Diagnostic suppression

global `warnings none` のように将来の問題を文法から隠す設定は入れない。

source-local な expectation や、理由付きの局所 suppression は別途評価できる。

---

## 5. 所有クラス

設定は次のいずれかに分類する。

## 5.1 Grammar Contract

parser artifact の意味または公開契約に属する。

- grammar declaration が authoritative
- conflicting generation CLI は error
- matching CLI value は受理可能
- root-only または明示的 merge
- IR に保存
- grammar digest の対象

例:

- parser construction algorithm
- multiple-entry strategy
- CST trivia policy
- superclass
- action ABI options

## 5.2 Grammar Minimum

source-local validation の最低条件。

- CLI/CI は強化できる
- CLI で弱められない
- effective value は monotone merge

候補:

- grammar-declared test production coverage minimum

ただし normalized synthetic production を数えるのか user production を数えるのかが未定義なため、
現在の `--coverage` を直ちに grammar 化しない。

## 5.3 Project Build Policy

意味は変えないが、repository/build artifact の作り方を決める。

- Rake task、CI、将来の小さな project config
- grammar には入れない
- generation manifest には effective value を記録

例:

- compact/plain table
- embedded runtime
- debug build
- line conversion
- RBS/action-source companion
- executable/shebang

## 5.4 Invocation Request

一回の実行だけに属する。

- CLI/subcommand only
- grammar/Grammar IR に保存しない

例:

- emit
- output
- watch
- reports
- analysis limits
- locale

---

## 6. Override algebra

## 6.1 Fixed

Grammar Contract に使用する。

```text
built-in default < grammar declaration
```

generation CLI:

- declarationなし: CLI または built-in default
- declarationあり、CLIなし: grammar
- declarationあり、同じCLI値: grammar contract と一致、成功
- declarationあり、異なるCLI値: error

例:

```text
grammar: parser.algorithm = ielr
CLI:     --algorithm=lr1
result:  conflict error
```

## 6.2 Minimum

Grammar Minimum に使用する。

```text
effective = max(grammar minimum, project/CLI request)
```

CLI が grammar minimum より弱い場合は error。

## 6.3 Analysis override

`metrics`、`explain`、cross-algorithm `test` のような非canonical分析では、
grammar contract と異なる値を明示的に選べる。

ただし report は必ず次を持つ。

```json
{
  "declared": "ielr",
  "selected": "lr1",
  "override": true,
  "canonical_generation": false
}
```

analysis override を generated canonical artifact へ黙って流用しない。

## 6.4 No implicit precedence by source order

root grammar と CLI の競合を「CLI が常に勝つ」で済ませない。
重要な契約を CLI で上書きできるなら、文法に書いた意味が弱くなるためである。

---

## 7. Scope and import rules

初期実装では、parser-wide configuration は **root-only** とする。

fragments は次を宣言できない。

- algorithm
- entry strategy
- CST trivia ownership
- generated superclass
- table representation

理由:

- reusable fragment が consumer 全体の construction policy を支配してしまう
- diamond import で conflict する
- merge order が semantic dependency になる
- root grammar の intent が読めなくなる

future fragment requirement は、実例が出た後に別設計する。
generic capability registry を先に作らない。

duplicate root declaration は、同値でも error を基本とする。
一つの contract に一つの source location を持たせるためである。

---

## 8. 現行 CLI option の判定

## 8.1 すでに grammar 側にある

| CLI | Grammar側 | 判定 |
|---|---|---|
| `--mode=extended` | `pragma extended` | Grammar Contract |
| `--superclass=CLASS` | class header `< CLASS` | Grammar Contract |
| `--no-omit-actions` | `options no_omit_action_call` | Grammar Contract |
| default/result variable behavior | `options result_var/no_result_var` | Grammar Contract |
| start selection | `start` | Grammar Contract |
| expected conflicts | `expect`, `%expect-rr` | source-local invariant |

現状では CLI が grammar value を上書きできる経路がある。
互換性を壊さず、origin を記録し、将来 fixed policy へ移行する必要がある。

## 8.2 Grammar declaration を追加すべき

| CLI | 提案domain | Policy | 理由 |
|---|---|---|---|
| `--algorithm=slr|lalr|ielr|lr1` | `parser.algorithm` | fixed | automaton/conflict/canonical construction |
| `--entry-isolation` | `parser.entries` | fixed | multiple entry state graph/public diagnostics |
| `--cst-trivia=leading|balanced|drop` | `cst.trivia` | fixed | CST ownership、coordinates、incremental API |

これらは source に書かれていなければ従来どおり CLI/default を使う。

## 8.3 別概念として将来評価できる

| Current CLI | Possible declaration | 判定条件 |
|---|---|---|
| `ibex test --coverage=N` | test coverage minimum | user production coverage の定義と monotone merge |
| global warning policy | specific expectation/suppression | warning ID、source span、理由、将来互換性 |
| repair costs | recovery declaration | existing RepairSearch と semantic-value policy の統合 |

current option をそのまま移植しない。

## 8.4 Project Build Policy

| CLI |
|---|
| `--table=plain|compact` |
| `--embedded` |
| `--debug` |
| `--frozen` |
| `--line-convert-all`, `--no-line-convert` |
| `--rbs`, `--action-source`, `--manifest` |
| `--executable` |

`plain` と `compact` は意味論的に等価であることを検証すべき表現選択であり、
grammar semantics ではない。

## 8.5 Invocation Request

| Group | CLI examples |
|---|---|
| pipeline | `--emit`, `--from` |
| paths | `--output-file`, `--dot`, `--html`, `--railroad`, `--log-file` |
| operation | `--watch`, `--check`, `--check-only`, `--output-status` |
| observation | `--verbose`, `--counterexamples`, `--suggest-ielr` |
| warning execution policy | `--warnings` |
| budgets | counterexample limits、fuzz/reduce/equiv/verify limits、test timeout |
| presentation | `--lang`, `--help`, `--version`, `--copyright` |
| internal compatibility | `-P`, `-D` |

---

## 9. Proposed grammar surface

最終syntaxは frontend prototype の前に固定しない。
次は意図を示す候補である。

```text
class ExampleParser
pragma extended
pragma cst

parser
  algorithm ielr
  entries isolated
  cst_trivia balanced
end

rule
  # ...
end
```

### 9.1 Design rules

- generic key-value は使わない
- accepted key は frontend grammar に明示
- value は enum token として型検査
- block は root-only
- unknown key は positioned error
- duplicate key は error
- canonical formatter order を定義
- `pragma cst` は Stable compatibility surface として残す
- `cst_trivia` は CST enabled (`pragma cst`) のときだけ許可
- `entries isolated` は multiple start でのみ意味を持つ
- `algorithm auto` は初期版に入れない

### 9.2 Why no `generate` block

`generate` という名前にすると、output path、table、reportなどが流入しやすい。
`parser` block は parser contract に責務を限定できる。

### 9.3 Why not extend current `options` bag

current `options` は action ABI の boolean switch を扱う。
algorithm、entry strategy、CST policy を stringly-typed な同じ列へ追加すると、
責務と値型が不明確になる。

---

## 10. Effective configuration model

CLI と grammar が別々の hash を持つのではなく、一つの typed model に統合する。

Conceptual record:

```ruby
ConfigurationValue = Data.define(
  :key,
  :value,
  :owner,
  :policy,
  :origin,
  :explicit
)
```

Example:

```json
{
  "key": "parser.algorithm",
  "value": "ielr",
  "owner": "grammar",
  "policy": "fixed",
  "origin": {
    "kind": "grammar",
    "file": "grammar.y",
    "line": 6,
    "column": 3
  },
  "explicit": true
}
```

### 10.1 Key registry

Internal registry records:

- canonical key
- type
- allowed values
- built-in default
- ownership class
- override algebra
- scope
- IR encoding
- CLI spelling
- grammar frontend adapter
- manifest encoding
- documentation owner

この registry は generic grammar syntax を自動生成するものではない。
各 grammar declaration は明示的に設計する。

### 10.2 `ibex config`

Proposed command:

```sh
ibex config grammar.y
ibex config --format=json grammar.y
```

Example output:

```text
parser.algorithm  ielr      grammar grammar.y:6:3  fixed
parser.entries    isolated  grammar grammar.y:7:3  fixed
cst.trivia        balanced  grammar grammar.y:8:3  fixed
table.format      compact   builtin                  build
runtime.embedded  false     builtin                  build
```

Requirements:

- static-no-user-code
- import closure を解決
- effective value と origin
- CLI conflict を source span 付きで説明
- canonical/noncanonical analysis selection を表示
- deterministic JSON

---

## 11. IR strategy

grammar declaration を追加するなら、source-only feature にしてはいけない。

次を満たす必要がある。

- `--emit=grammar-ir` で失われない
- `--from=grammar-ir` で同じ canonical contract を再構成できる
- Automaton IR が selected construction と整合する
- migration が unknown/unspecified を正しく扱う

### 11.1 Recommended direction

Grammar IR v3 に optional root contract を追加する案を第一候補とする。

```json
{
  "parser_contract": {
    "algorithm": {
      "value": "ielr",
      "explicit": true,
      "loc": {}
    },
    "entries": {
      "value": "isolated",
      "explicit": true,
      "loc": {}
    },
    "cst_trivia": {
      "value": "balanced",
      "explicit": true,
      "loc": {}
    }
  }
}
```

ADR で次と比較する。

- Grammar IR v3
- separate Parser Contract IR
- grammar bundle envelope

### 11.2 Migration caveat

Grammar IR v2 は algorithm、entry isolation、CST trivia の source declarationを持たない。

したがって v2 -> v3 migration は、historical CLI value を推測してはならない。

- absent source declaration -> `explicit: false` / unspecified
- normal generation -> built-in or CLI selection
- Automaton IR に algorithm があれば、その automaton の事実として保持
- entry isolation は exactに回収できないなら unknown
- CST trivia は generated table からのみ分かる場合がある
- unavailable data を migration metadata に記録

---

## 12. Manifest and provenance

現行 generation manifest は一部の CLI options を記録するが、
value の origin を区別しない。

さらに現行 option inventory では `cst_trivia` が manifest option list に含まれていない。
これは generated CST contract を変える option として優先的に修正すべきである。

### 12.1 Immediate correction

- manifest の effective options に `cst_trivia` を含める
- regression test
- same grammar / different trivia policy の manifest 差を固定

### 12.2 Manifest v2 direction

Raw CLI hash ではなく、次を分ける。

```json
{
  "configuration": [
    {
      "key": "parser.algorithm",
      "value": "ielr",
      "origin": "grammar",
      "policy": "fixed"
    }
  ],
  "invocation": {
    "emit": "ruby"
  }
}
```

- configuration: parser contract/build selection
- invocation: command execution
- artifacts: paths/digests
- limits: bounded analysisを行った場合
- logical source identity と filesystem path を分離

---

## 13. Compatibility

### 13.1 Existing grammar

新 declaration がなければ挙動を変えない。

- default algorithm: current LALR
- current shared entry construction
- current leading CST trivia default
- existing CLI options continue to work

### 13.2 Grammar declaration + matching CLI

成功。manifest origin は grammar、CLI match は確認情報として扱える。

### 13.3 Grammar declaration + conflicting generation CLI

positioned error。

```text
grammar.y:6:3: parser.algorithm is declared as ielr;
(cli): --algorithm=lr1 conflicts with the grammar contract
```

### 13.4 Existing CLI override surfaces

`--superclass` と `--no-omit-actions` は既存 compatibility surface である。

移行案:

1. effective configuration origin を記録
2. source declarationとの conflict warning
3. deprecation policy を公開
4. canonical generation では conflict error
5. noncanonical migration harness では明示 override を許可

v1 contract と利用実態を確認せず即時削除しない。

---

## 14. Adversarial checks

## 14.1 Grammar dumping ground

Risk:

あらゆる CLI request が「再現性」を理由に grammar へ入る。

Control:

Admission Test と owner table を必須にする。
一つでも X 条件に該当すれば拒否。

## 14.2 Backend lock-in

Risk:

`table compact`、`embedded runtime` 等が grammar を Ruby codegen に固定する。

Control:

representation/deployment は project build policy。

## 14.3 Hidden override

Risk:

grammar を読んでも CLI で意味が変わる。

Control:

fixed/minimum algebra、effective config provenance、conflict error。

## 14.4 Fragment conflicts

Risk:

imported library grammar が root algorithm を変更する。

Control:

初期 parser contract は root-only。

## 14.5 IR churn

Risk:

setting ごとに schema field/version が増える。

Control:

一つの parser contract designでまとめてIR v3を検討。
syntaxごとにIRを継ぎ足さない。

## 14.6 CLI and grammar drift

Risk:

CLI は新しい valueを受けるがgrammar parserは受けない。

Control:

typed key registry、cross-surface conformance test、generated documentation inventory。

## 14.7 “auto” instability

Risk:

`algorithm auto` がversionごとに異なるautomatonを選ぶ。

Control:

初期版では explicit algorithm only。
future auto selection は selected algorithm とdecision evidenceをartifactに固定する。

---

## 15. Success criteria

- 全 CLI option が owner class を持つ
- unclassified option が0
- canonical generationに必要な semantic-affecting hidden flagsが0
- grammar-declared contract が Grammar IR round-tripで失われない
- `ibex config` が全 effective value と origin を説明する
- conflicting generation override を全件拒否する
- analysis override が noncanonical として記録される
- manifest が effective config を記録する
- source-declared config の formatter/LSP coverageがある
- no arbitrary code during config resolution
- fragment/root composition casesが全て決定的
- compatibility mode の declaration-free grammar bytes/behavior が変わらない

---

## 16. Adoption order

1. option inventory と Admission Test を固定
2. typed effective configuration model
3. `cst_trivia` manifest omissionを修正
4. `ibex config`
5. IR persistence ADR
6. parser algorithm declaration
7. entry strategy declaration
8. CST trivia declaration
9. CLI conflict/deprecation policy
10. declarative validation minimumを別評価

重要なのは、grammar syntaxを最初に追加しないことである。
先に同じconceptをCLI/default/IR/manifestで一貫して扱えるmodelを作り、
最後にdomain-specific syntaxを与える。
