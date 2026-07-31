# v1 安定 API

この文書は v1 で Stable と判定された公開契約の日本語案内です。詳細な
構文表や全メソッド一覧はリンク先の英語リファレンスを正本としますが、
下記の契約、互換性、失敗条件は日本語でも同じ意味を持ちます。

## racc 互換パーサ生成

<!-- stable:compatible-parser -->

既定モードは racc 互換の文法を読み、Pure Ruby の LR パーサを生成します。
生成クラスは `do_parse` と `yyparse` を提供します。既定の直接 LALR 構築、
plain/compact 表、yacc `error` 回復、コールバック、観測イベント、
`ResourceLimits`、移行検査、境界付きの競合反例解析が Stable です。
互換モードを明示せずに拡張構文へ切り替えることはありません。構文と CLI
の詳細は [`grammar-reference.md`](../grammar-reference.md) を参照してください。

## バージョン付き IR と表

<!-- stable:versioned-ir -->

Grammar IR、Automaton IR、Lexer IR、パーサ表、JSON レポートには版があり、
closed schema の検証器は未知フィールド、不正な参照、版の不一致を拒否します。
dump → load → dump は決定的です。既存の版の意味は書き換えず、互換性のない
変更は新しい major schema として導入します。詳しい段階境界は
[`architecture.md`](../architecture.md) にあります。

## バッチ Red/Green CST

<!-- stable:batch-cst -->

format v6 のバッチ CST は、損失のない Green 値と位置・親参照を持つ Red
ビューを分離します。typed syntax view、永続編集、差分、`ibex_cst` schema
v1 の直列化が Stable です。エラー入力も `Error` / `Missing` 要素として木に
残ります。syntax-only incremental session は Experimental であり、この
Stable 契約には含まれません。API 例は [`cst.md`](../cst.md) を参照してください。

## 互換性と非推奨化

<!-- stable:compatibility-policy -->

Stable API は semantic versioning に従います。v1.0 以降の削除や意味変更は、
少なくとも2回の minor release にわたって移行警告、代替手段、最短削除版を
文書化します。Preview は少なくとも1回の minor release で予告し、
Experimental は予告なく変わる可能性があります。正確な在庫と昇格条件は
[`stability.md`](../stability.md) にあります。
