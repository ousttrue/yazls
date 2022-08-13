# yazls

Yet another zig language server.
<https://github.com/zigtools/zls> を fork して改造した <https://github.com/ousttrue/zls> を整理したものです。

zls の zls.exe のみを置き換えて使います。

## vscode の設定

```json:settings.json
"zls.path": "PATH_TO_HERE/zig-out/bin/yazls.exe",
```

## 新機能(予定)

* @cImport に対する処理
* pkg マップのロード(project root から適当な json をロードする)
* gyro.zzz から pkg マップをロード
