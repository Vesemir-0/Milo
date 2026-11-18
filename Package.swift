// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MiloCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MiloCore", targets: ["MiloCore"])],
    targets: [
        .target(name: "MiloCore", path: "AIScheduleAssistant", exclude: ["App", "Views", "Assets.xcassets", "Utils/DesignSystem.swift", "AIScheduleAssistantApp.swift", "Info.plist", "AIScheduleAssistant.entitlements"], sources: ["Models", "Services", "ViewModels", "Utils/KeychainService.swift"]),
        .testTarget(name: "MiloCoreTests", dependencies: ["MiloCore"], path: "Tests/MiloCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
