import Foundation

/// Did people who finished onboarding actually reach the app? Finishing only proves the onboarding said it was done;
/// a paywall that won't close, a sign-up that fails after the last screen, or a crash on first load all happen after it.
///
/// `finish()` remembers the session it ended. `reportArrival()` on the screen people land on afterwards sends one
/// `reached_home` event for that session and forgets it.
struct PendingArrival: Codable {
    let appId: String
    let sessionId: String
    let environment: String
    let platform: String
    let baseURL: String
    let apiKey: String
    let finishedAt: TimeInterval
}

/// UserDefaults is thread-safe; older SDKs just don't mark it Sendable.
struct Store: @unchecked Sendable { let defaults: UserDefaults; init(_ defaults: UserDefaults) { self.defaults = defaults } }

enum OnboardingArrival {
    /// Arriving weeks later says nothing about the hand-off from onboarding, so old ones are dropped unsent.
    static let maxAge: TimeInterval = 7 * 24 * 3600
    private static let lock = NSLock()
    // Several screens can report at once; one send per app at a time.
    nonisolated(unsafe) private static var sending = Set<String>()

    static func key(_ appId: String) -> String { "onboardingyak:arrival:\(appId)" }

    static func remember(_ pending: PendingArrival, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: key(pending.appId)) }
    }

    private static func claim(_ appId: String) -> Bool { lock.lock(); defer { lock.unlock() }; return sending.insert(appId).inserted }
    private static func release(_ appId: String) { lock.lock(); sending.remove(appId); lock.unlock() }

    static func report(appId: String, defaults: UserDefaults, transport: @escaping @Sendable (URLRequest) async -> Int?) {
        guard claim(appId) else { return }
        guard let data = defaults.data(forKey: key(appId)), let pending = try? JSONDecoder().decode(PendingArrival.self, from: data), pending.appId == appId, let base = URL(string: pending.baseURL) else { release(appId); return }
        if Date().timeIntervalSince1970 - pending.finishedAt > maxAge { defaults.removeObject(forKey: key(appId)); release(appId); return }

        var request = URLRequest(url: base.appendingPathComponent("api/events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(pending.apiKey, forHTTPHeaderField: keyHeader)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["app_id": appId, "event_name": "reached_home", "session_id": pending.sessionId, "flow_version": 0, "environment": pending.environment, "platform": pending.platform, "sdk_version": sdkVersion] as [String: Any])
        let storageKey = key(appId)
        let store = Store(defaults)
        Task {
            defer { release(appId) }
            // Offline or a server error keeps it for the next call; anything else (sent, or refused for good) clears it.
            if let status = await transport(request), status < 500 { store.defaults.removeObject(forKey: storageKey) }
        }
    }
}
