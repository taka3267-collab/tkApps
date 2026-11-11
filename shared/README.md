# おすすめアプリ（全アプリ共通）

各アプリの「おすすめアプリ」欄は、このフォルダの `recommended-apps.json` を見て表示されます。
**アプリを更新しなくても、ここを書き換えるだけで内容・並び順・アイコンを変えられます。**

## 管理ページ

https://taka3267-collab.github.io/tkApps/admin/recommended-apps.html

フォーム操作だけで編集できます。初回に ⚙︎ から GitHub のアクセストークンを登録してください。

- トークンは GitHub → Settings → Developer settings → Personal access tokens →
  **Fine-grained tokens** で作成し、リポジトリは **tkApps のみ**、権限は **Contents: Read and write** にする
- トークンはブラウザ（localStorage）にだけ保存され、GitHub 以外には送信されない
- 「公開する」でこのリポジトリに直接コミットされる。各アプリには数分以内に反映される

## ファイルの構成

```jsonc
{
  "catalog": {           // アプリの情報。1か所にまとめる
    "bookdeck": {
      "appStoreId": "6811623217",
      "icon": "icons/bookdeck.png",
      "localizations": { "ja": { "title": "…", "detail": "…" }, "en": { … } }
    }
  },
  "placements": {        // どのアプリに、どれを、どの順で出すか（キーは Bundle ID）
    "default":        ["diary", "bookdeck", "quicknote", "focuscamera"],
    "com.taka.diary": ["bookdeck", "quicknote", "focuscamera"]
  },
  "bundleToApp": {       // Bundle ID → catalog の ID（自分自身を表示しないために使う）
    "com.taka.diary": "diary"
  }
}
```

- `placements` に無いアプリには `default` が使われる
- 配列の途中に `"--more--"` を入れると、**そこから下は「開発者のその他のアプリ」を押すまで隠れる**
  （管理ページの「『開発者のその他のアプリ』の区切りを入れる」で追加・移動できる）
- 言語は `ja` / `en` / `ko` / `zh-Hans`。足りない言語は 英語 → 日本語 の順で代用される
- アイコンは `icons/` に 256×256 の PNG（管理ページからアップロードすると自動で変換される）

## アプリ側の実装

- 日記アプリ: `Diary/Services/RecommendedAppsService.swift`
- 6時間に1回だけ取得し、結果は端末内にキャッシュする
- 取得できないときは「前回の内容 → アプリ内蔵の既定値」の順に落ちるので、表示が消えることはない
- 送信する情報は無し（静的ファイルへの GET のみ）
