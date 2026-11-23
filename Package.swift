// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OnboardingYak",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "OnboardingYak", targets: ["OnboardingYak"]),
    ],
    targets: [
        .target(name: "OnboardingYak"),
        .testTarget(name: "OnboardingYakTests", dependencies: ["OnboardingYak"]),
    ]
)
