import XCTest
@testable import OnboardingYak

/// Collects the events a tracker sends instead of hitting the network.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []
    var status = 204

    var transport: @Sendable (URLRequest) async -> Int? {
        { [self] request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            record(body)
            return status
        }
    }
    private func record(_ body: [String: Any]) { lock.lock(); bodies.append(body); lock.unlock() }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return bodies.map { "\($0["event_name"]!)\($0["screen_id"].map { ":\($0)" } ?? "")" } }
    var all: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return bodies }
}

final class OnboardingTrackerTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "onboardingyak-tests")!
        defaults.removePersistentDomain(forName: "onboardingyak-tests")
    }

    func tracker(_ recorder: Recorder) -> OnboardingTracker {
        OnboardingTracker(appId: "my-app", apiKey: "oy_pub_test", baseURL: URL(string: "https://example.com")!, environment: .testing, defaults: defaults, transport: recorder.transport)
    }

    func testSendsTheFunnelInOrder() async {
        let recorder = Recorder()
        let onboarding = tracker(recorder)
        onboarding.screen("welcome")
        onboarding.screen("welcome") // repeated: ignored
        onboarding.next()
        onboarding.screen("pick-goal")
        onboarding.finish()
        await onboarding.flush()
        XCTAssertEqual(recorder.events, ["flow_started", "screen_viewed:welcome", "screen_completed:welcome", "screen_viewed:pick-goal", "screen_completed:pick-goal", "flow_completed:pick-goal"])
        let first = recorder.all[0]
        XCTAssertEqual(first["app_id"] as? String, "my-app")
        XCTAssertEqual(first["environment"] as? String, "testing")
        XCTAssertEqual(first["flow_version"] as? Int, 0)
        XCTAssertEqual(first["sdk_version"] as? String, "\(onboardingYakVersion)-swift")
        XCTAssertEqual(Set(recorder.all.map { $0["session_id"] as! String }).count, 1)
    }

    func testRejectsInvalidTags() async {
        let recorder = Recorder()
        let onboarding = tracker(recorder)
        onboarding.screen("Pick Goal")
        await onboarding.flush()
        XCTAssertEqual(recorder.events, [])
        XCTAssertTrue(OnboardingTracker.isValidTag("pick_goal-2"))
        XCTAssertFalse(OnboardingTracker.isValidTag("-welcome"))
    }

    func testResumesASessionWithoutAnotherStart() async {
        let recorder = Recorder()
        tracker(recorder).screen("welcome")
        // The app relaunches mid-onboarding: a new tracker picks up the saved session.
        let relaunched = tracker(recorder)
        relaunched.screen("pick-goal")
        await relaunched.flush()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(recorder.events.filter { $0 == "flow_started" }.count, 1)
        XCTAssertEqual(Set(recorder.all.map { $0["session_id"] as! String }).count, 1)
    }

    func testDisabledSendsNothing() async {
        let recorder = Recorder()
        let onboarding = tracker(recorder)
        onboarding.setEnabled(false)
        onboarding.screen("welcome")
        onboarding.finish()
        await onboarding.flush()
        XCTAssertEqual(recorder.events, [])
    }

    func testArrivalIsReportedOnce() async {
        let recorder = Recorder()
        let onboarding = tracker(recorder)
        onboarding.screen("welcome")
        onboarding.finish()
        await onboarding.flush()
        onboarding.reportArrival()
        try? await Task.sleep(nanoseconds: 100_000_000)
        onboarding.reportArrival()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(recorder.events.filter { $0 == "reached_home" }.count, 1)
        XCTAssertEqual(recorder.all.last?["session_id"] as? String, recorder.all.first?["session_id"] as? String)
    }

    func testFinishStartsAFreshSessionNextTime() async {
        let recorder = Recorder()
        let onboarding = tracker(recorder)
        onboarding.screen("welcome")
        onboarding.finish()
        onboarding.screen("welcome")
        await onboarding.flush()
        XCTAssertEqual(recorder.events.filter { $0 == "flow_started" }.count, 2)
        XCTAssertEqual(Set(recorder.all.map { $0["session_id"] as! String }).count, 2)
    }
}
