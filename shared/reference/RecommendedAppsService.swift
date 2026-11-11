import Foundation
import SwiftUI

// =====================================================================
// 「開発者のほかのアプリ」リモート配信クライアント（ひな形）
//
// 使い方:
//   1. このファイルを対象アプリの Services/ などにコピーする
//   2. 下の RecommendedAppsConfig だけアプリごとに直す
//   3. 設定画面に shared/reference/README.md の SwiftUI スニペットを貼る
//
// 配信元は GitHub Pages の静的 JSON 1 本（全アプリ共通）。
// 取得失敗時は「前回のキャッシュ → アプリ内蔵の既定値」の順に落ちるので
// オフラインでも表示が消えない。送信する情報は無く、問い合わせは GET のみ。
// =====================================================================

// MARK: - ▼ アプリごとに直すのはここだけ ▼

private enum RecommendedAppsConfig {
    /// このアプリ自身の App Store ID。
    /// placements の設定漏れで自分自身を出してしまわないための保険に使う。
    static let ownAppStoreID = "0000000000"

    /// 通信もキャッシュも無いときに出す内容。
    /// アイコンは Assets に同梱したものを使う（空配列にすると初回だけ何も出ない）。
    static let bundledDefaults: [BundledApp] = [
        // BundledApp(id: "bookdeck", ja: ("読書記録・本棚管理", "読んだ本・読んでいる本・これから読む本をシンプルに記録"),
        //            en: ("BookDeck", "Track what you've read, what you're reading, and what's next"),
        //            appStoreID: "6811623217", asset: "BookDeckRecommended")
    ]

    /// 表示に使う言語コード（"ja" / "en" / "ko" / "zh-Hans"）。
    /// アプリ側に独自の言語設定があるなら、その値を返すように差し替える。
    @MainActor
    static var languageCode: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ja") { return "ja" }
        if preferred.hasPrefix("ko") { return "ko" }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    struct BundledApp {
        let id: String
        let ja: (title: String, detail: String)
        let en: (title: String, detail: String)
        let appStoreID: String
        let asset: String?
    }
}

// MARK: - ▲ ここまで ▲

/// 配信元。全アプリ共通。
private let recommendedAppsFeedURL = URL(
    string: "https://taka3267-collab.github.io/tkApps/shared/recommended-apps.json"
)!

@MainActor
@Observable
final class RecommendedAppsStore {
    static let shared = RecommendedAppsStore()

    /// 取得間隔。起動のたびに取りに行かない。
    private static let refreshInterval: TimeInterval = 6 * 60 * 60
    private static let lastFetchKey = "recommendedAppsLastFetch"

    private(set) var apps: [RecommendedApp] = []
    /// 最初から見せる件数。これを超える分は「開発者のほかのアプリ」を押すまで隠す。
    private(set) var visibleCount: Int = 0

    private var feed: RecommendedAppsFeed?
    private var isLoading = false

    private init() {
        feed = Self.loadCachedFeed()
        rebuild()
    }

    /// 言語設定が変わったときなどに呼ぶ。表示用の文言を組み直す。
    func rebuild(languageCode: String? = nil) {
        let lang = languageCode ?? RecommendedAppsConfig.languageCode
        if let feed {
            let selection = feed.selection(for: Bundle.main.bundleIdentifier, language: lang)
            if !selection.apps.isEmpty {
                apps = selection.apps
                visibleCount = selection.initiallyVisible
                return
            }
        }
        apps = RecommendedApp.bundledDefaults(language: lang)
        visibleCount = apps.count
    }

    /// 必要なら最新の内容を取りに行く。失敗しても何も起きない（表示は現状維持）。
    func refreshIfNeeded(force: Bool = false) {
        guard !isLoading else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastFetchKey)
        let elapsed = Date().timeIntervalSince1970 - last
        guard force || last == 0 || elapsed > Self.refreshInterval else { return }
        isLoading = true

        Task { [weak self] in
            defer { Task { @MainActor in self?.isLoading = false } }
            var request = URLRequest(url: recommendedAppsFeedURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 12
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                let http = response as? HTTPURLResponse, http.statusCode == 200,
                let decoded = try? JSONDecoder().decode(RecommendedAppsFeed.self, from: data),
                !decoded.catalog.isEmpty
            else { return }

            Self.saveCachedFeed(data)
            await MainActor.run {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastFetchKey)
                self?.feed = decoded
                self?.rebuild()
            }
        }
    }

    // MARK: - キャッシュ

    private static var cacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("recommended-apps.json")
    }

    private static func loadCachedFeed() -> RecommendedAppsFeed? {
        guard
            let url = cacheURL,
            let data = try? Data(contentsOf: url),
            let feed = try? JSONDecoder().decode(RecommendedAppsFeed.self, from: data)
        else { return nil }
        return feed
    }

    private static func saveCachedFeed(_ data: Data) {
        guard let url = cacheURL else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 表示用

/// 設定画面に並べる 1 件分。
struct RecommendedApp: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let appStoreID: String
    /// リモートのアイコン。無い場合は `bundledIconAsset` を使う。
    let iconURL: URL?
    /// アプリに同梱しているアイコン（オフライン時・既定値用）。
    let bundledIconAsset: String?

    /// ストアフロント（/us/ など）は付けず、利用者の国の App Store で開かせる。
    var url: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    /// 通信できないときに使う、アプリ内蔵の内容。
    static func bundledDefaults(language: String) -> [RecommendedApp] {
        RecommendedAppsConfig.bundledDefaults.map { item in
            let text = language == "ja" ? item.ja : item.en
            return RecommendedApp(
                id: item.id,
                title: text.title,
                detail: text.detail,
                appStoreID: item.appStoreID,
                iconURL: nil,
                bundledIconAsset: item.asset
            )
        }
    }

    /// 同梱アイコンを持っているものだけ、リモート取得前でも絵を出せるようにする。
    static func bundledIconAsset(for id: String) -> String? {
        RecommendedAppsConfig.bundledDefaults.first { $0.id == id }?.asset
    }
}

// MARK: - 配信ファイルの形

/// GitHub Pages に置く JSON の構造。
///
/// - `catalog`: アプリの情報（名前・説明・アイコン・App Store ID）を 1 か所にまとめたもの
/// - `placements`: どのアプリに、どれを、どの順で出すか（キーは Bundle ID）
/// - `bundleToApp`: Bundle ID ↔ catalog の ID。自分自身を表示しないために使う
struct RecommendedAppsFeed: Decodable {
    struct Localized: Decodable {
        let title: String
        let detail: String?
    }

    struct Entry: Decodable {
        let appStoreId: String
        let icon: String?
        let localizations: [String: Localized]

        func localized(_ language: String) -> Localized? {
            localizations[language] ?? localizations["en"] ?? localizations["ja"]
        }
    }

    let version: Int?
    let iconBaseUrl: String?
    let catalog: [String: Entry]
    let placements: [String: [String]]
    let bundleToApp: [String: String]?

    /// 一覧と、「開発者のほかのアプリ」を押す前に見せる件数。
    struct Selection {
        let apps: [RecommendedApp]
        let initiallyVisible: Int
    }

    /// `placements` の配列にこの印が入っていると、そこから下は押すまで隠す。
    static let moreSeparator = "--more--"

    func selection(for bundleID: String?, language: String) -> Selection {
        let ids = bundleID.flatMap { placements[$0] } ?? placements["default"] ?? []
        let selfID = bundleID.flatMap { bundleToApp?[$0] }
        let ownStoreID = RecommendedAppsConfig.ownAppStoreID

        var built: [RecommendedApp] = []
        var visible: Int?

        for id in ids {
            if id == Self.moreSeparator {
                // 印が複数あっても最初のものだけを使う。
                if visible == nil { visible = built.count }
                continue
            }
            guard id != selfID, let entry = catalog[id] else { continue }
            // 設定漏れで自分自身を出してしまわないための保険。
            guard entry.appStoreId != ownStoreID else { continue }
            guard let text = entry.localized(language), !text.title.isEmpty else { continue }

            var iconURL: URL?
            if let icon = entry.icon, !icon.isEmpty {
                if icon.hasPrefix("http") {
                    iconURL = URL(string: icon)
                } else if let base = iconBaseUrl, let baseURL = URL(string: base) {
                    iconURL = baseURL.appendingPathComponent(icon)
                }
            }

            built.append(
                RecommendedApp(
                    id: id,
                    title: text.title,
                    detail: text.detail ?? "",
                    appStoreID: entry.appStoreId,
                    iconURL: iconURL,
                    bundledIconAsset: RecommendedApp.bundledIconAsset(for: id)
                )
            )
        }

        // 印が無い／先頭にある／隠れる分が無い場合は、全部そのまま見せる。
        let initiallyVisible = visible.map { max(1, $0) } ?? built.count
        return Selection(apps: built, initiallyVisible: min(initiallyVisible, built.count))
    }
}
