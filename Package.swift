// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "omiyaIME",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "omiyaIME", targets: ["OmiyaIME"]),
        .executable(name: "omiya-walk-preview", targets: ["OmiyaWalkPreview"])
    ],
    targets: [
        .target(name: "OmiyaInput"),
        .target(name: "OmiyaWalkCore"),
        .target(name: "OmiyaWalk", dependencies: ["OmiyaWalkCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "OmiyaWalkPreview", dependencies: ["OmiyaWalk", "OmiyaWalkCore"]),
        .executableTarget(name: "OmiyaIME", dependencies: ["OmiyaInput", "OmiyaWalkCore"]),
        .testTarget(name: "OmiyaInputTests", dependencies: ["OmiyaInput"]),
        .testTarget(name: "OmiyaWalkTests", dependencies: ["OmiyaWalkCore"]),
        .testTarget(name: "OmiyaIMETests", dependencies: ["OmiyaIME", "OmiyaInput"])
    ]
)
