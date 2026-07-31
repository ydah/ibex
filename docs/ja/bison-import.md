# Bison 文法の解析用インポート

`ibex import bison` は Bison 形式の文法構造を、解析専用の extended Ibex
ソースへ一方向に変換します。互換パーサを生成するモードではありません。C
アクションは不透明なまま保持され、解析中には実行されず、Ruby 生成はコードを
出力する前に拒否されます。

```sh
ibex import bison parser.y -o parser.analysis.y
ibex import bison --format=json parser.y > import-report.json
ibex explain --state=STATE parser.y
ibex metrics parser.y
```

2 個の `%%` 区切りを持つファイルは `explain` や `metrics` から直接解析
できます。修復差分は変換後ソースのバイト位置に対するものなので、修復には
明示的に出力した canonical 解析ファイルが必要です。

対応指令は次の3種類です。

- `%token`、結合規則、`%start`、`%expect`、`%empty`、`%prec` は既存の
  Ibex 構文へ変換します。
- `%type`、`%union`、printer/destructor、parameter、`%define`、`%code`
  は位置付き metadata として報告します。
- GLR、`%dprec`、`%merge`、生成制御、未知の指令は、出現ごとに元の行・列を
  付けて未対応として報告します。

`$$`、`$1`、型付き参照、`@$` は機械的に変換されますが、C の意味を Ruby
として解釈しません。大文字の非終端、予約語、正規化後の名前衝突も、
`bison_nt_*` / `BISON_T_*` と決定的な suffix で分離します。

レポートと生成ソースは、単なる未対応と「生成規則を完全には復元できない」
構造的不完全を区別します。後者には
`ibex-bison-structural-status: incomplete` が付き、`ibex fix` は安全な
同値修復を主張せず拒否します。

既定上限は入力 20 MiB、構造 token 1,000,000、rule group 50,000、action
100,000 です。`--max-*` は正の整数だけを受け付け、上限超過は JSON で明示し
終了コード 2 になります。`-o` は原子的に書き込み、入出力 alias、symlink、
複数 hard link を拒否します。

外部 CI は5個の checksum 固定 GNU Bison 文法を一時取得し、成果物には含め
ません。Bison 時代の CRuby `parse.y` では production 781 と未解決競合 0 が
一致し、Bison 1,304 state と Ibex 1,303 state の差は、Bison が EOF shift
専用 accept state を持つためです。

現行 CRuby `parse.y` は Lrama 拡張を含み、GNU Bison の生入力ではありません。
Ibex は `%rule` などを構造的不完全として全列挙し、限定した `explain` は
近似文法の証拠としてのみ提示します。この状態で `fix` を提案しないことが安全
契約です。固定 revision、license、取得元は
[`gallery/EXTERNAL.md`](../../gallery/EXTERNAL.md) にあります。
