# yazls

Yet another zig language server.
<https://github.com/zigtools/zls> を fork して改造した <https://github.com/ousttrue/zls> を整理したものです。

zls の zls.exe のみを置き換えて使います。

## vscode の設定

```json:settings.json
"zls.path": "PATH_TO_HERE/zig-out/bin/yazls.exe",
```

# TODO

* [ ] 0.1: 改造版の zls を移植するところまで

|                                  | zls | yazls |                                                 |
|----------------------------------|-----|-------|-------------------------------------------------|
| initialize                       | ✅   | ✅     |                                                 |
| initialized                      |     | ✅     | 何もしてない                                    |
| shutdown                         | ✅   | ✅     |                                                 |
| textDocument/didOpen             | ✅   | ✅     |                                                 |
| textDocument/didChange           | ✅   | ✅     |                                                 |
| textDocument/didSave             | ✅   | ✅     | BuildFile 再評価無し                            |
| textDocument/didClose            | ✅   | ✅     |                                                 |
| textDocument/publishDiagnostics  | ✅   | ✅     | camel_case, snake_case 等のスタイルチェック無し |
| textDocument/semanticTokens/full | ✅   | ✅     |                                                 |
| textDocument/formatting          | ✅   | ✅     |                                                 |
| textDocument/documentSymbol      | ✅   | ✅     |                                                 |
| textDocument/declaration         | ✅   |       | declaration と definition の区別                |
| textDocument/definition          | ✅   | ✅     | 不完全                                          |
| textDocument/completion          | ✅   | ✅     | 不完全                                          |
| @cImport                         |     |       |                                                 |
| gyro.zzz から pkg マップをロード |     |       |                                                 |

## textDocument/declaration textDocument/definition

* [ ] textDocument/declaration => struct_decl まで飛ぶ
* [ ] textDocument/definition => var_decl, container_field まで飛ぶ
* [x] call => fn_decl
* [x] field_access => container_field
* [ ] type from fn that return type

## textDocument/completion

* [ ] builtin 関数
* [x] member field 列挙
* [x] package, *.zig 列挙
* [ ] struct_init 時の field 入力
* [ ] enum

## simple 化

* Config ない
* Document の reference カウントしない
* BuildFile は workspace/build.zig ひとつに決め打ち
* import の 参照記録していない。ファイル外からの references を実装してない

# 実装メモ

`std.zig.parse` から `std.zig.Ast` を得られる。
この Ast 内で identifier Token の symbol 名の解決ができる。
symbol 名は、 local変数, container変数 の何れかである。
local 変数は関数ボディ内で、関数引数、ブロック、if_payload, while_payload, switch_case_payload である。
container 変数は struct の static 変数である。
一番外のスコープは、暗黙的に struct (root container) である。
`@import` は外部の `zig` ファイルの `root` container を表す。

変数宣言の型を解決したい。
変数宣言 `const val : TYPE = EXPR`, 関数引数 `param: TYPE`, ifなどの条件式 `if(EXPR)` から解決する。
TYPE 、無ければ EXPR の型を再帰的に解決する。
関数呼び出し `call` は返り値の型、ポインタ, `optional` 型, `error_union` 型, `try` 式, array の index 参照などは適当に中身の型に参照を解除する。
`field_access` は左辺の struct を取得し、struct のメンバー変数、関数、フィールドから右辺の名前を検索する。
この過程で `@import` の解決が必要になる。
最終的に `u32, type` などの primitive か, `array`, `slice` などの複合型、`fn` もしくは `struct_decl` を得る。
`struct_decl` の場合は `field_acess` が可能で、コンテキストによって、型か値としてふるまうのだが、lsp 用途では区別しなくてもよさそう(手抜き)。

## 課題

* 型解決が多段で起こるので、途中で止まったり間違ったりするのをデバッグ可能にしたい
* completion を解決するときの AST が入力途中で不完全な状態になるので、コンテキストを決定する方法(dicChange の追跡？)
