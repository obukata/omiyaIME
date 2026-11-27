// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "omiyaIME",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "omiyaIME", targets: ["OmiyaIME"])
    ],
    targets: [
        .target(name: "OmiyaInput"),
        .executableTarget(name: "OmiyaIME", dependencies: ["OmiyaInput"]),
        .testTarget(name: "OmiyaInputTests", dependencies: ["OmiyaInput"]),
        .testTarget(name: "OmiyaIMETests", dependencies: ["OmiyaIME", "OmiyaInput"])
    ]
)
