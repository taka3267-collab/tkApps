# 「開発者のほかのアプリ」を別のアプリに入れる手順

対象: SwiftUI のアプリ（`/Users/taka/Dev/*`）。
日記（`/Users/taka/Dev/diary`）が最初の実装で、ここにあるのはそれを汎用化したひな形。

> **Flutter のアプリの場合**
> `RecommendedAppsService.swift` の Dart 移植が
> `/Users/taka/Dev/friend-talk-ios/lib/services/recommended_apps_service.dart` にある。
> JSON の読み方（`catalog` / `placements` / `bundleToApp` / `--more--`）と
> フォールバックの順序は Swift 版と同じで、違うのは次の3点だけ。
> - キャッシュは `path_provider` を足さずに `shared_preferences` に JSON 文字列で持つ
> - Bundle ID は `package_info_plus` から取る
> - 画面側は `RecommendedAppsStore.shared`（`ChangeNotifier`）を `ListenableBuilder` で listen する
>
> 設定画面のスニペットは下の SwiftUI 版ではなく、
> `friend-talk-ios/lib/screens/settings/settings_screen.dart` の
> `_RecommendedAppsSection` をコピーする。

所要: 1 アプリ 15〜30 分。**アプリ更新が必要なのは最初の 1 回だけ**で、
以後は内容・並び順・「開発者のほかのアプリ」の位置を管理ページから差し替えられる。

- 配信元: `https://taka3267-collab.github.io/tkApps/shared/recommended-apps.json`
- 管理ページ: `https://taka3267-collab.github.io/tkApps/admin/recommended-apps.html`
- 仕組み全体の説明: [`../README.md`](../README.md)

---

## 1. アプリ側（1 回だけ・要アプリ更新）

### 1-1. クライアントを置く

`RecommendedAppsService.swift` を対象アプリの `Services/`（無ければ適当な場所）にコピーし、
ファイル冒頭の `RecommendedAppsConfig` だけ直す。

| 項目 | 直し方 |
|---|---|
| `ownAppStoreID` | **そのアプリ自身の App Store ID**。設定漏れで自分を出さないための保険 |
| `bundledDefaults` | 通信もキャッシュも無い初回に出す内容（2〜3 件）。アイコンは Assets に同梱したものを指定。`[]` でもよい（初回だけ何も出ない） |
| `languageCode` | アプリに独自の言語設定があるならその値を返すように差し替える。無ければ端末設定のままでよい |

他は触らない。`placements` / `catalog` はすべて JSON 側にあるので、
「どのアプリを出すか」はこのファイルに一切書かない。

> Xcode プロジェクトを Ruby の `xcodeproj` で生成しているアプリは、
> ファイルを足したあと `ruby gen_project.rb` を忘れずに。

### 1-2. 設定画面に出す

```swift
@State private var recommendedAppsStore = RecommendedAppsStore.shared
@State private var showsAllRecommendedApps = false
```

```swift
if !recommendedAppsStore.apps.isEmpty {
    Section("おすすめアプリ") {
        ForEach(visibleRecommendedApps) { app in
            Link(destination: app.url) { recommendedAppRow(app) }
                .buttonStyle(.plain)
        }
        if hasHiddenRecommendedApps {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showsAllRecommendedApps.toggle() }
            } label: {
                HStack {
                    Text(showsAllRecommendedApps ? "閉じる" : "開発者のほかのアプリ")
                    Spacer()
                    Image(systemName: showsAllRecommendedApps ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
        }
    }
}
```

```swift
/// 押す前は、配信側で指定された件数までしか出さない。
private var visibleRecommendedApps: [RecommendedApp] {
    let apps = recommendedAppsStore.apps
    guard !showsAllRecommendedApps else { return apps }
    let count = recommendedAppsStore.visibleCount
    guard count > 0, count < apps.count else { return apps }
    return Array(apps.prefix(count))
}

private var hasHiddenRecommendedApps: Bool {
    let count = recommendedAppsStore.visibleCount
    return count > 0 && count < recommendedAppsStore.apps.count
}

/// アイコンはリモート取得。読み込み中・失敗時は同梱画像、それも無ければ下地だけ。
@ViewBuilder
private func recommendedAppIcon(_ app: RecommendedApp) -> some View {
    if let url = app.iconURL {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default: recommendedAppIconPlaceholder(app)
            }
        }
    } else {
        recommendedAppIconPlaceholder(app)
    }
}

@ViewBuilder
private func recommendedAppIconPlaceholder(_ app: RecommendedApp) -> some View {
    if let asset = app.bundledIconAsset {
        Image(asset).resizable().scaledToFill()
    } else {
        Rectangle().fill(.quaternary)
    }
}

private func recommendedAppRow(_ app: RecommendedApp) -> some View {
    HStack(alignment: .center, spacing: 14) {
        recommendedAppIcon(app)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
            Text(app.title).font(.headline).foregroundStyle(.primary)
            Text(app.detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 4)
        Image(systemName: "arrow.up.right.square").font(.title3).foregroundStyle(.secondary)
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
}
```

呼び出しを足す。

```swift
.onAppear { recommendedAppsStore.refreshIfNeeded() }
// アプリ内に言語設定があるなら
.onChange(of: languageRaw) { _, _ in recommendedAppsStore.rebuild() }
```

### 1-3. 文言

多言語対応しているアプリは、文字列カタログ（`Localizable.xcstrings` など）にこれを足す。

| ja | en | ko | zh-Hans |
|---|---|---|---|
| おすすめアプリ | Apps you may like | 추천 앱 | 推荐应用 |
| 開発者のほかのアプリ | More by this developer | 개발자의 다른 앱 | 开发者的其他应用 |
| 閉じる | Close | 닫기 | 收起 |

### 1-4. 通信について

静的ファイルへの GET のみで、送信する情報は無い。
そのため **App Store Connect のプライバシー申告を変更する必要は無い**（データ収集なし）。
`NSAppTransportSecurity` の追加も不要（https）。

---

## 2. 配信側（アプリ更新なし・いつでも）

### 2-1. そのアプリを「出す側」として登録する

管理ページの **アプリ情報** タブ →「アプリを追加」。

- **ID**: 英小文字の短い識別子（例 `bookdeck`）。JSON の `catalog` のキーになる
- **Bundle ID**: 実物の値（推測で入れない。`project.pbxproj` の `PRODUCT_BUNDLE_IDENTIFIER` を見る）
- **App Store ID**: 公開ページ URL の `id` の数字
- アイコン: 画像をドラッグすると 256×256 PNG に変換して `shared/icons/` に入る
- 説明文: ja / en（ko / zh-Hans は任意。無ければ en → ja の順に落ちる）

これで**他のアプリからおすすめとして出せる**ようになる。

### 2-2. そのアプリを「出される側」として設定する

**表示設定** タブ → 上の選択欄で対象アプリを選び、並べる／並び替える。
点線の区切りより下が「開発者のほかのアプリ」を押すまで隠れる分。
自分自身は自動で除外されるので、入っていても出ない。

### 2-3. 対応済みフラグを立てる

`admin/recommended-apps.html` の

```js
const SUPPORTED = ["com.taka.diary"];
```

に Bundle ID を足す。立てないと管理ページで
「※このアプリはまだこの仕組みに対応していないため、今の設定は反映されません」と出続ける。
`shared/README.md` の「対応しているアプリ」も合わせて直す。

### 2-4. 公開

`shared/` と `admin/` を commit + push すれば GitHub Pages に出る。
反映は 1〜10 分（`cache-control: max-age=600`）。
確認するときは URL に `?v=2` のような適当なクエリを付けてキャッシュを外す。

---

## 3. 確認

1. シミュレータか実機で設定画面を開く → 一覧が出る／「開発者のほかのアプリ」で残りが出る
2. キャッシュの実物: `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<id>/Library/Application Support/recommended-apps.json`
3. 配信内容を変えてもすぐ反映されないのは正常（取得間隔 6 時間 + Pages のキャッシュ 10 分）。
   すぐ試すならアプリを削除して入れ直す

---

## つまづきやすいところ

- **`--more--` は位置の印**。件数ではないので、間に挟む場所で「最初に見せる件数」が決まる
- **Bundle ID を推測しない**。間違っていると黙って `default` の内容が出るだけで気づけない
- **GitHub Pages のキャッシュ**。変えたのに出ないときはまずこれ。`?v=N` を付けて確認する
- **PAT** は tkApps だけに絞った fine-grained（Contents: Read and write）。
  ブラウザの localStorage にしか保存されず、GitHub 以外には送らない
