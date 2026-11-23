import Foundation

/// Funnel analytics for an onboarding the app builds itself.
///
/// Sends four events (`flow_started`, `screen_viewed`, `screen_completed`, `flow_completed`) tagged with screen ids
/// the app chooses, so the OnboardingYak studio can show views and drop-off per screen.
///
/// Privacy: events carry only the app id, the screen tag, a random session id, the platform and the environment.
/// No device or advertising identifiers, no answers, nothing shared with third parties. This is first-party analytics,
/// not tracking in the App Tracking Transparency sense, so it needs no ATT prompt.
public final class OnboardingTracker: @unchecked Sendable {
    public enum Environment: String, Sendable { case development, testing, production }

    /// The app's ID in OnboardingYak.
    public let appId: String
    let apiKey: String
    let baseURL: URL
    let environment: Environment
    let resumeInterval: TimeInterval
    let captureScreens: Bool
    let defaults: UserDefaults
    /// Sends a request and returns its status code, or nil when it failed (offline). Replaced in tests.
    var transport: @Sendable (URLRequest) async -> Int? = { request in
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    private let lock = NSLock()
    private var enabled: Bool
    private var session: Session?
    /// The session `finish()` ended, so a stale saved copy is never resumed.
    private var ended: String?
    private var started = false
    private var current: String?
    private var completed = Set<String>()
    private var captured = Set<String>()
    private var stopCapturing = false
    /// Sends run one after another, so events arrive in the order they happened.
    private var queue: Task<Void, Never>?

    struct Session { let id: String; let resumed: Bool }
    struct StoredSession: Codable { let id: String; let startedAt: TimeInterval }

    /// - Parameters:
    ///   - appId: The app's ID in OnboardingYak.
    ///   - apiKey: The app's publishable key (`oy_pub_…`).
    ///   - baseURL: The OnboardingYak origin, e.g. `https://onboardingyak.com`.
    ///   - environment: TestFlight builds should pass `.testing`. Defaults to `.development` in debug builds and `.production` otherwise.
    ///   - resumeHours: Keep the same session when the app is closed and reopened mid-onboarding, for up to this many hours. 0 turns it off.
    ///   - enabled: Pass false until the person consents to analytics. Events are dropped, not queued.
    ///   - captureScreens: In debug builds only, screenshot each tagged screen once it settles, so the studio shows the
    ///     real screen instead of a mockup. Release builds never capture, whatever is passed.
    public init(appId: String, apiKey: String, baseURL: URL, environment: Environment? = nil, resumeHours: Double = 24, enabled: Bool = true, captureScreens: Bool = false) {
        self.appId = appId
        self.apiKey = apiKey
        self.baseURL = baseURL
        #if DEBUG
        self.environment = environment ?? .development
        #else
        self.environment = environment ?? .production
        #endif
        self.resumeInterval = max(0, resumeHours) * 3600
        self.enabled = enabled
        self.captureScreens = captureScreens
        self.defaults = .standard
    }

    init(appId: String, apiKey: String, baseURL: URL, environment: Environment, defaults: UserDefaults, transport: @escaping @Sendable (URLRequest) async -> Int?) {
        self.appId = appId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment
        self.resumeInterval = 24 * 3600
        self.enabled = true
        self.captureScreens = false
        self.defaults = defaults
        self.transport = transport
    }

    // MARK: Public API

    /// Starts a session (once). The first `screen(_:)` calls it for you.
    public func start() { locked { startLocked() } }

    /// The person sees this screen. Use the screen's tag, e.g. `welcome` or `pick-goal`. Repeated calls for the same screen are ignored.
    public func screen(_ tag: String) {
        let capture: Bool = locked {
            guard Self.isValidTag(tag), tag != current else { return false }
            startLocked()
            current = tag
            completed.remove(tag)
            send("screen_viewed", tag)
            guard captureScreens, enabled, !stopCapturing, !captured.contains(tag) else { return false }
            captured.insert(tag)
            return true
        }
        if capture { scheduleCapture(tag) }
    }

    /// The person moved past this screen. The tag defaults to the last screen they saw.
    public func next(_ tag: String? = nil) {
        locked {
            guard let tag = tag ?? current, Self.isValidTag(tag), !completed.contains(tag) else { return }
            completed.insert(tag)
            send("screen_completed", tag)
        }
    }

    /// The person finished the onboarding, including Skip paths that end it early. Also counts the last screen as
    /// completed, then ends the session.
    public func finish(_ tag: String? = nil) {
        locked {
            let tag = tag ?? current
            if let tag, Self.isValidTag(tag), !completed.contains(tag) {
                completed.insert(tag)
                send("screen_completed", tag)
            }
            send("flow_completed", tag)
            // Remembered so reportArrival() on the app's home can report that this session got there.
            if enabled, let session {
                OnboardingArrival.remember(PendingArrival(appId: appId, sessionId: session.id, environment: environment.rawValue, platform: platformName, baseURL: baseURL.absoluteString, apiKey: apiKey, finishedAt: Date().timeIntervalSince1970), defaults: defaults)
            }
            // Forget the saved copy, and never resume it.
            if let session {
                ended = session.id
                if storedSession()?.id == session.id { defaults.removeObject(forKey: sessionKey) }
            }
            resetLocked()
        }
    }

    /// Turns sending on or off at runtime, e.g. after a consent prompt.
    public func setEnabled(_ value: Bool) { locked { enabled = value } }

    /// Forgets the current session, so the next screen starts a new one.
    public func reset() { locked { resetLocked() } }

    /// Call on the screen people land on after onboarding (home, the main tab). Sends one `reached_home` event for
    /// the session `finish()` just ended; later calls, and people who never went through onboarding, send nothing.
    public func reportArrival() { OnboardingArrival.report(appId: appId, defaults: defaults, transport: transport) }

    /// Screen tags: lowercase letters, digits, `-` and `_`, starting with a letter or digit, up to 64 characters.
    public static func isValidTag(_ tag: String) -> Bool {
        let valid = tag.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil
        if !valid { warn("\"\(tag)\" is not a valid screen tag. Use lowercase letters, digits, - and _ (e.g. \"pick-goal\"). The event was not sent.") }
        return valid
    }

    /// Waits for every queued event to be sent. For tests.
    func flush() async { await locked { queue }?.value }

    // MARK: Internals (call with the lock held)

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private func startLocked() {
        guard !started, enabled else { return }
        started = true
        // A session resumed from storage already sent flow_started when it began.
        send("flow_started", nil, skipIfResumed: true)
    }

    private func resetLocked() {
        session = nil; started = false; current = nil; completed.removeAll()
    }

    private var sessionKey: String { "onboardingyak:track-session:\(appId)" }

    private func storedSession() -> StoredSession? {
        defaults.data(forKey: sessionKey).flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
    }

    private func loadSession() -> Session {
        if let session { return session }
        let now = Date().timeIntervalSince1970
        if resumeInterval > 0, let saved = storedSession(), saved.id != ended, now - saved.startedAt < resumeInterval {
            session = Session(id: saved.id, resumed: true)
        } else {
            let id = UUID().uuidString.lowercased()
            if resumeInterval > 0, let data = try? JSONEncoder().encode(StoredSession(id: id, startedAt: now)) { defaults.set(data, forKey: sessionKey) }
            session = Session(id: id, resumed: false)
        }
        return session!
    }

    private func send(_ event: String, _ tag: String?, skipIfResumed: Bool = false) {
        guard enabled else { return }
        let session = loadSession()
        if skipIfResumed && session.resumed { return }
        var body: [String: Any] = ["app_id": appId, "event_name": event, "session_id": session.id, "flow_version": 0, "environment": environment.rawValue, "platform": platformName, "sdk_version": sdkVersion]
        if let tag { body["screen_id"] = tag }
        let request = jsonRequest("api/events", body)
        let previous = queue
        let transport = transport
        queue = Task {
            await previous?.value
            switch await transport(request) {
            case 401: warn("event rejected (401). Check that apiKey is this app's publishable key (oy_pub_…).")
            case 403: warn("event rejected (403). appId must be the app the publishable key belongs to.")
            case 422: warn("event rejected (422) for screen \"\(tag ?? "")\".")
            default: break // Sent, or offline: analytics are best effort.
            }
        }
    }

    func jsonRequest(_ path: String, _ body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: keyHeader)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Screenshots (debug builds only)

    private func scheduleCapture(_ tag: String) {
        #if DEBUG && canImport(UIKit) && !os(watchOS)
        Task { @MainActor in
            // Long enough for an entrance animation to finish, short enough to beat the first tap.
            try? await Task.sleep(nanoseconds: 700_000_000)
            // Captured only if the person is still on the screen, so it's never a half-finished transition.
            guard locked({ current == tag && !stopCapturing }), let image = ScreenCapture.jpegBase64(width: 600) else { return }
            await upload(tag, image)
        }
        #endif
    }

    private func upload(_ tag: String, _ image: String) async {
        var request = jsonRequest("api/captures", ["app_id": appId, "tag": tag, "environment": "development", "image": image])
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else { return }
        if status == 409 {
            // Off, or not a tracked app: the server says which. Stop trying for the rest of this run.
            locked { stopCapturing = true }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            warn("screenshot not kept. \(message ?? "")")
        } else if status == 401 || status == 403 {
            warn("screenshot of \"\(tag)\" rejected (\(status)). Check appId and apiKey.")
        }
    }
}
