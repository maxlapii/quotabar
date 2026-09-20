//
//  Service.swift
//  ClaudeStatus
//
//  Fetches Claude usage from Anthropic's (unofficial) OAuth usage endpoint
//  using the Claude Code credentials stored on this Mac.
//

import Foundation
import Security
import ServiceManagement

// MARK: - Constants

enum Config {
    /// Anthropic's (unofficial) OAuth usage endpoint.
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Required beta header for that endpoint.
    static let betaHeader = "oauth-2025-04-20"
    /// Keychain item Claude Code writes on macOS (same JSON as the file).
    static let keychainService = "Claude Code-credentials"
    /// Auto-refresh cadence.
    static let refreshInterval: Duration = .seconds(180)

    /// `~/.claude/.credentials.json`, using the real home even when sandboxed.
    static var credentialsPath: String {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
        return home + "/.claude/.credentials.json"
    }
}

// MARK: - Model

/// One rate-limit window as returned by the usage endpoint.
struct UsageBucket: Sendable, Equatable {
    /// Percent of the window already used, 0…100.
    var utilization: Double
    /// When the window resets, if the API provided it.
    var resetsAt: Date?

    /// Utilization clamped to 0…100 and rounded to a whole percent.
    var percent: Int {
        Int(min(max(utilization, 0), 100).rounded())
    }

    /// Five-block ASCII gauge, e.g. "▮▮▮▯▯".
    var blocks: String {
        let filled = Int((min(max(utilization, 0), 100) / 100 * 5).rounded())
        let clamped = min(max(filled, 0), 5)
        return String(repeating: "▮", count: clamped) + String(repeating: "▯", count: 5 - clamped)
    }
}

/// A complete usage reading.
struct UsageSnapshot: @unchecked Sendable, Equatable {
    /// `five_hour.utilization` → shown as "5h".
    var fiveHour: UsageBucket
    /// `seven_day.utilization` → shown as "W".
    var sevenDay: UsageBucket
    /// Fable weekly limit → shown as "F". Read from the `limits` array entry
    /// with kind `weekly_scoped` (scope.model.display_name "Fable"), else from
    /// `seven_day_fable` / `seven_day_opus` / `seven_day_sonnet`, else `seven_day`.
    var fable: UsageBucket
    /// Where `fable` was read from, e.g. "limits.weekly_scoped (Fable)", or "seven_day" when it fell back.
    var fableKey: String
    /// Display name of the scoped model, normally "Fable".
    var fableName: String
    /// Every top-level bucket the API returned, in response order.
    var allBuckets: [(key: String, bucket: UsageBucket)]
    /// Raw response, pretty-printed, for troubleshooting ("Copy raw JSON").
    var rawJSON: String
    var fetchedAt: Date

    /// True when no Fable-specific field existed and `fable` mirrors `sevenDay`.
    var fableIsFallback: Bool { fableKey == "seven_day" }

    static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool {
        lhs.fetchedAt == rhs.fetchedAt && lhs.rawJSON == rhs.rawJSON
    }
}

// MARK: - Errors

enum UsageError: LocalizedError, Equatable {
    case credentialsNotFound(path: String)
    case tokenMissing
    case tokenExpired(Date)
    case unauthorized
    case rateLimited
    case badStatus(Int)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "Not signed in to Claude Code."
        case .tokenMissing:
            return "Credentials file has no OAuth access token."
        case .tokenExpired(let date):
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return "OAuth token expired \(f.string(from: date))."
        case .unauthorized:
            return "Anthropic rejected the token (401). It has probably expired."
        case .rateLimited:
            return "Usage endpoint rate-limited this request (429)."
        case .badStatus(let code):
            return "Usage endpoint returned HTTP \(code)."
        case .network(let detail):
            return "Network error: \(detail)"
        case .decoding(let detail):
            return "Unexpected response format: \(detail)"
        }
    }

    /// True when the fix is to (re)sign in to Claude Code.
    var needsSignIn: Bool {
        switch self {
        case .credentialsNotFound, .tokenMissing, .tokenExpired, .unauthorized: return true
        default: return false
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .credentialsNotFound, .tokenMissing:
            return "Claude Desktop's login isn't shared with other apps. Sign in the claude command-line tool once: click “Sign in via Terminal”, type /login, finish in the browser, then click Refresh (3min)."
        case .tokenExpired, .unauthorized:
            return "Click “Sign in via Terminal” (Claude Code refreshes the token when it starts), then click Refresh (3min)."
        case .rateLimited:
            return "Wait a minute and try again."
        case .badStatus, .network, .decoding:
            return "Check your connection and try again."
        }
    }
}

// MARK: - Credentials

/// Reads the Claude Code OAuth token. Nothing to configure: it uses whatever
/// login Claude Code (including the one inside Claude Desktop) already has.
///
/// 1. `~/.claude/.credentials.json` if it exists.
/// 2. Otherwise the login Keychain item "Claude Code-credentials", which is
///    where Claude Code stores the same JSON on macOS. macOS asks once to allow
///    access; choose "Always Allow".
///
/// If the file's token has expired but the Keychain has a fresh one, the
/// Keychain wins, because Claude Code refreshes the Keychain copy.
enum CredentialsStore {

    struct Token: Sendable {
        let accessToken: String
        let expiresAt: Date?
        var isExpired: Bool { expiresAt.map { $0 < Date() } ?? false }
    }

    private struct CredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?   // milliseconds since epoch
        }
        let claudeAiOauth: OAuth?
    }

    static func loadToken() throws -> Token {
        let fileToken = FileManager.default.contents(atPath: Config.credentialsPath).flatMap { try? parse($0) }
        if let fileToken, !fileToken.isExpired { return fileToken }

        let keychainToken = readKeychain(service: Config.keychainService).flatMap { try? parse($0) }
        if let keychainToken, !keychainToken.isExpired { return keychainToken }

        if let expired = fileToken?.expiresAt ?? keychainToken?.expiresAt {
            throw UsageError.tokenExpired(expired)
        }
        if FileManager.default.fileExists(atPath: Config.credentialsPath) {
            throw UsageError.tokenMissing
        }
        throw UsageError.credentialsNotFound(path: "~/.claude/.credentials.json")
    }

    private static func parse(_ data: Data) throws -> Token {
        let file = try JSONDecoder().decode(CredentialsFile.self, from: data)
        guard let token = file.claudeAiOauth?.accessToken, !token.isEmpty else {
            throw UsageError.tokenMissing
        }
        let expiresAt = file.claudeAiOauth?.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        return Token(accessToken: token, expiresAt: expiresAt)
    }

    private static func readKeychain(service: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}

// MARK: - API client

enum UsageAPI {
    /// Keys tried for the "F" (Fable) gauge, most specific first.
    static let fableKeyPreference = ["seven_day_fable", "seven_day_opus", "seven_day_sonnet"]

    static func fetch(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Config.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("Non-HTTP response")
        }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw UsageError.unauthorized
        case 429: throw UsageError.rateLimited
        default: throw UsageError.badStatus(http.statusCode)
        }

        return try parse(data)
    }

    /// Decodes the response generically so new/renamed buckets still show up.
    static func parse(_ data: Data) throws -> UsageSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw UsageError.decoding(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw UsageError.decoding("top level is not an object")
        }

        // Preserve the server's key order for display.
        let orderedKeys = keyOrder(in: data) ?? Array(root.keys).sorted()
        var buckets: [(key: String, bucket: UsageBucket)] = []
        for key in orderedKeys {
            guard let dict = root[key] as? [String: Any], dict["utilization"] != nil || dict["resets_at"] != nil else { continue }
            let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
            let resetsAt = (dict["resets_at"] as? String).flatMap(parseDate)
            guard utilization != nil || resetsAt != nil else { continue }
            buckets.append((key, UsageBucket(utilization: utilization ?? 0, resetsAt: resetsAt)))
        }

        func bucket(_ key: String) -> UsageBucket? { buckets.first { $0.key == key }?.bucket }

        // The `limits` array is what claude.ai's usage page renders:
        //   kind "session" → 5h, "weekly_all" → W, "weekly_scoped" (+ scope.model) → F.
        struct Limit { let kind: String; let modelName: String?; let bucket: UsageBucket }
        var limits: [Limit] = []
        if let array = root["limits"] as? [[String: Any]] {
            for entry in array {
                guard let kind = entry["kind"] as? String,
                      let percent = (entry["percent"] as? NSNumber)?.doubleValue else { continue }
                let model = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let b = UsageBucket(utilization: percent, resetsAt: (entry["resets_at"] as? String).flatMap(parseDate))
                limits.append(Limit(kind: kind, modelName: model, bucket: b))
                let label = model.map { "limits.\(kind) (\($0))" } ?? "limits.\(kind)"
                buckets.append((label, b))
            }
        }
        func limit(_ kind: String) -> Limit? { limits.first { $0.kind == kind } }

        guard let fiveHour = bucket("five_hour") ?? limit("session")?.bucket,
              let sevenDay = bucket("seven_day") ?? limit("weekly_all")?.bucket else {
            throw UsageError.decoding("missing five_hour or seven_day (got: \(orderedKeys.joined(separator: ", ")))")
        }

        // F: scoped weekly limit named Fable, else any scoped limit, else legacy keys, else weekly.
        var fableKey = "seven_day"
        var fableName = "Fable"
        var fable = sevenDay
        if let scoped = limits.first(where: { $0.kind == "weekly_scoped" && ($0.modelName ?? "").lowercased().contains("fable") })
                     ?? limits.first(where: { $0.kind == "weekly_scoped" }) {
            fable = scoped.bucket
            fableName = scoped.modelName ?? "Fable"
            fableKey = "limits.weekly_scoped (\(fableName))"
        } else if let k = orderedKeys.first(where: { $0.lowercased().contains("fable") && bucket($0) != nil }) {
            fable = bucket(k)!; fableKey = k
        } else if let k = fableKeyPreference.first(where: { (root[$0] as? [String: Any])?["utilization"] is NSNumber }) {
            fable = bucket(k)!; fableKey = k
        }

        // Keep the field list readable: drop empty helper buckets.
        buckets.removeAll { $0.bucket.utilization == 0 && $0.bucket.resetsAt == nil }

        let pretty = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? (String(data: data, encoding: .utf8) ?? "")

        return UsageSnapshot(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fable: fable,
            fableKey: fableKey,
            fableName: fableName,
            allBuckets: buckets,
            rawJSON: pretty,
            fetchedAt: Date()
        )
    }

    /// Top-level key order as they appear in the raw JSON text.
    private static func keyOrder(in data: Data) -> [String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Match `"key":` at nesting depth 1.
        var keys: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var current = ""
        var collecting = false
        var lastString = ""
        for ch in text {
            if inString {
                if escaped { escaped = false; if collecting { current.append(ch) } }
                else if ch == "\\" { escaped = true; if collecting { current.append(ch) } }
                else if ch == "\"" { inString = false; lastString = current; collecting = false }
                else if collecting { current.append(ch) }
                continue
            }
            switch ch {
            case "\"": inString = true; current = ""; collecting = (depth == 1)
            case "{", "[": depth += 1
            case "}", "]": depth -= 1
            case ":": if depth == 1, !lastString.isEmpty { keys.append(lastString); lastString = "" }
            default: break
            }
        }
        return keys.isEmpty ? nil : keys
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - Service (observable state + auto refresh)

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var error: UsageError?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    /// Auto-refresh cadence.
    static let refreshInterval: Duration = Config.refreshInterval

    private var loop: Task<Void, Never>?

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    /// Starts (or restarts) the background refresh loop.
    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// `~/Library/Caches/ClaudeStatus/last-usage.json` — the most recent raw
    /// response (usage numbers only, no token), for troubleshooting.
    static var lastResponseURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("ClaudeStatus/last-usage.json")
    }

    private static func saveLastResponse(_ json: String) {
        let url = lastResponseURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Fetches usage once. Safe to call from the "Refresh (3min)" button.
    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let token = try CredentialsStore.loadToken()
            let result = try await UsageAPI.fetch(token: token.accessToken)
            snapshot = result
            error = nil
            lastUpdated = result.fetchedAt
            Self.saveLastResponse(result.rawJSON)
        } catch let e as UsageError {
            error = e
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}

// MARK: - Launch at login

/// Registers the app as a login item with the native macOS 13 API.
/// Shows up under System Settings ▸ General ▸ Login Items and can be removed there too.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled: Bool = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
