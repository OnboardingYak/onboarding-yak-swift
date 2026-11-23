# OnboardingYak Swift SDK: rules for AI coding agents

Read this before changing onboarding in an iOS app that uses the `OnboardingYak` Swift package. It applies to Codex,
Claude Code, Cursor, Copilot, and people too.

This package only **tracks** onboarding the app builds itself. The screens are in the app's code, and you change them
there, like any other UI. OnboardingYak gives the funnel: how many people reach each screen and where they drop off.
Its studio shows a picture of each screen next to the numbers: a screenshot, or a mockup. In OnboardingYak these apps
have `mode: "track"` (MCP tool `list_apps`).

## Ask first

When setting up tracking, ask the user before changing anything how the studio should show their screens, and wait
for the answer. Every option tags the screens and sends the same analytics:

- **A. Real screenshots (recommended).** Tag the screens and pass `captureScreens: true`. The user opens the onboarding
  once in a debug build, and each screen is screenshotted as they reach it.
- **B. A mockup in OnboardingYak.** Recreate each screen in the studio from the code (see below). Best when the app
  doesn't run yet, or the user plans to redesign it in the studio.
- **C. Screenshots you take** in the iOS Simulator (step 5 below). Only when A isn't possible.

For B and C, leave `captureScreens` off.

## Tag the screens

```swift
import OnboardingYak

// One shared tracker, e.g. in Onboarding/Tracking.swift
let onboarding = OnboardingTracker(appId: "<app id>", apiKey: "oy_pub_…", baseURL: URL(string: "https://onboardingyak.com")!, captureScreens: true)

// SwiftUI
GoalScreen().trackedScreen("pick-goal", in: onboarding)
// UIKit: onboarding.screen("pick-goal") in viewDidAppear

// on continue: onboarding.next(); where onboarding ends: onboarding.finish()
```

- Give every onboarding screen one tag: lowercase letters, digits, `-` and `_`, such as `welcome`, `pick-goal` or
  `paywall`. Never reuse a tag for another screen, and never rename one. Renaming starts a new funnel row and splits
  the history.
- Call `next()` where the screen's continue action runs, and `finish()` where onboarding ends, including Skip paths
  that end it early.
- **Never send personal data.** Tags are fixed names, never user input, names, emails or answers.
- Put `appId`, `apiKey` and `baseURL` in one file and use that tracker everywhere. Get the values from
  **App settings → Tracking setup** in the studio, or ask the user.
- TestFlight builds should pass `environment: .testing`.
- Call `.onboardingArrival(onboarding)` (UIKit: `onboarding.reportArrival()` in `viewDidAppear`) on the screen people
  land on after onboarding (home, the main tab). It sends one `reached_home` event for the session `finish()` just
  ended. **Never tag that screen with `trackedScreen`**: it isn't an onboarding screen. If you can't tell which screen
  it is, ask the user.
- For option A, `captureScreens: true` screenshots each tagged screen about 0.7 s after it appears, in **debug builds
  only**. Release builds never capture, so nothing changes for App Store privacy labels and no permission is needed.
  Keep it in place; don't gate it yourself. The studio only keeps screenshots while **Screenshots from dev builds** is
  on in its Tracking panel (7 days at a time); if the console logs that screenshots are off, tell the user to turn it on.

## Write the screens into the studio (MCP)

The MCP endpoint is `https://onboardingyak.com/api/mcp`. The user creates a key in the studio under
**Account settings → Connect agent**. Never ask the user to paste the key into chat.

Do this for every option. The studio hangs each tag's numbers on a screen in the app's draft, and its AI insights read
that screen's text. With screenshots (A, C) keep it plain; for a mockup (B), style it too.

1. Read the onboarding screens in the code, in the order people see them.
2. Call `get_draft`. Build one screen per tag. **The screen `id` must equal the tag.** Copy the real wording into
   `title`, `subtitle`, `button` and `options`. Pick the closest `kind` and `answerType`. For B only, set `accent` and
   `theme` colors close to the app's.
3. On each screen, set `mock`: `{ source: "App/Onboarding/GoalScreen.swift", notes: "What this screen does" }`.
3b. **Branches.** When the code only shows a screen after a certain answer, make the question screen
   `kind: "Question"` with `answerType: "singleChoice"` and its real `options`, then set
   `showIf: { screen: "<question tag>", anyOf: ["<answer>"] }` on every screen of that branch (`not: true` for
   "any answer except"). Without it, the studio counts everyone who took the other path as a drop-off.
4. Call `save_draft` with `baseRevision`. **Never call `publish_flow` for a tracked app.** It's refused.
5. Screenshots. For A, tell the user to check that **Screenshots from dev builds** is on, then go through the
   onboarding once in a debug build. For C, capture each screen in the iOS Simulator in its empty state, before
   anything is typed or picked: `xcrun simctl io booted screenshot <tag>.png`. Upload each with `create_asset_upload`,
   set `mock.screenshot` to the `publicUrl`, and `save_draft`. Never capture screens from real users.
6. Call `get_tracking_status`. Fix tags that sent events but aren't in the mockup, and mockup screens that never
   received events. For each screen in `looksConditional`, check the code and add `showIf` if it really is a branch.

When onboarding code changes later (a screen added, removed, reordered or reworded, or a branch's answers changed),
update the tags and the mockup in the same task, retake the screenshots of screens whose look changed, and say so.

## Build a studio design in code (`get_code_spec`)

When the user designed a flow in the studio and chose **Build in my code**:

1. Call `get_code_spec`. It returns the screens, every image and video URL in `assets`, and the steps to follow.
2. Write each screen as real SwiftUI or UIKit in this app, with its own navigation and styling. Keep the copy exactly.
   Download the assets into the asset catalog.
3. Tag each screen with `.trackedScreen("<screen id>", in: onboarding)`. **The screen ids are already the tags.**
4. Set `mock.source` on each mockup screen (`get_draft`, then `save_draft`), run the app, and check
   `get_tracking_status`.
5. Wire permissions, paywalls and `custom:` actions to the app's real code, or leave a TODO and tell the user. Never
   ship sample reviews, ratings or numbers from a template as real ones.
