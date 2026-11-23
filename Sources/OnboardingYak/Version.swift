/// The package version. Keep it in step with the git tag.
public let onboardingYakVersion = "1.0.0"

/// Sent as `sdk_version`. The `-swift` suffix keeps Swift installs apart from React Native ones in OnboardingYak's
/// own stats, and still passes the server's version check (`1.0.0-swift` counts as able to report arrivals).
let sdkVersion = "\(onboardingYakVersion)-swift"

let keyHeader = "X-OnboardingYak-Key"

#if os(iOS)
let platformName = "ios"
#else
let platformName = "other"
#endif

func warn(_ message: String) {
    #if DEBUG
    print("OnboardingYak: \(message)")
    #endif
}
