#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Sends a screen view when this view appears, and again if `tag` changes.
    /// `GoalScreen().trackedScreen("pick-goal", in: onboarding)`
    public func trackedScreen(_ tag: String, in tracker: OnboardingTracker) -> some View {
        task(id: tag) { tracker.screen(tag) }
    }

    /// Put this on the screen people land on after onboarding (home, the main tab). Sends one `reached_home` event
    /// for the onboarding that just finished; later appearances send nothing. Never also tag this screen with `trackedScreen`.
    public func onboardingArrival(_ tracker: OnboardingTracker) -> some View {
        onAppear { tracker.reportArrival() }
    }
}
#endif
