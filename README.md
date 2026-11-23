# OnboardingYak for Swift

See where people drop off in your iOS app's onboarding. Your screens stay in your code; you tag each one, and the
[OnboardingYak](https://onboardingyak.com) studio shows how many people reach it and where they leave.

This package tracks onboarding that the app builds itself. To have OnboardingYak draw the screens and update them
without a release, use the [React Native SDK](https://www.npmjs.com/package/@onboarding-yak/react-native).

## Install

In Xcode: **File → Add Package Dependencies…**, paste `https://github.com/OnboardingYak/onboarding-yak-swift`, and add
`OnboardingYak` to your app target. Or in `Package.swift`:

```swift
.package(url: "https://github.com/OnboardingYak/onboarding-yak-swift", from: "1.0.0")
```

Requires iOS 15+.

## Set up

Create one tracker and share it. Get the app ID and publishable key from **App settings → Tracking setup** in the studio.

```swift
import OnboardingYak

let onboarding = OnboardingTracker(
    appId: "<app id>",
    apiKey: "oy_pub_…",
    baseURL: URL(string: "https://onboardingyak.com")!,
    captureScreens: true // debug builds only: screenshots each screen for the studio
)
```

## Tag the screens

SwiftUI:

```swift
struct GoalScreen: View {
    var body: some View {
        VStack { … Button("Continue") { onboarding.next(); path.append(.plan) } }
            .trackedScreen("pick-goal", in: onboarding)
    }
}
```

UIKit:

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    onboarding.screen("pick-goal")
}
```

- `screen(_:)` when a screen appears, `next()` when the person continues, `finish()` where onboarding ends, including Skip.
- Tags are fixed names: lowercase letters, digits, `-` and `_`. Never rename one; that starts a new funnel row.
- Never put personal data in a tag.

## Did they reach the app?

On the screen people land on after onboarding (home, the main tab):

```swift
HomeView().onboardingArrival(onboarding)   // UIKit: onboarding.reportArrival() in viewDidAppear
```

It sends one `reached_home` event for the onboarding that just finished. Later visits send nothing. Don't also tag
this screen with `trackedScreen`.

## Options

| Option | Default | |
|---|---|---|
| `environment` | `.development` in debug builds, else `.production` | Pass `.testing` for TestFlight builds. |
| `resumeHours` | `24` | Keep the session when the app is closed and reopened mid-onboarding. `0` turns it off. |
| `enabled` | `true` | Pass `false` until the person consents; change later with `setEnabled(_:)`. Events are dropped, not queued. |
| `captureScreens` | `false` | Debug builds only. Each tagged screen is screenshotted about 0.7 s after it appears. Turn on **Screenshots from dev builds** in the studio's Tracking panel. |

## Privacy

Events carry only the app ID, the screen tag, a random session ID, the platform and the environment. No device or
advertising identifiers and no answers. This is first-party analytics, so it needs no App Tracking Transparency prompt.
Screenshots are only ever taken in debug builds, so release builds change nothing for your App Store privacy label.

## License

MIT
