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
        .target(name: "OmiyaWalk", resources: [.copy("Resources")]),
        .executableTarget(name: "OmiyaWalkPreview", dependencies: ["OmiyaWalk"]),
        .executableTarget(name: "OmiyaIME", dependencies: ["OmiyaInput"]),
        .testTarget(name: "OmiyaInputTests", dependencies: ["OmiyaInput"]),
        .testTarget(name: "OmiyaIMETests", dependencies: ["OmiyaIME", "OmiyaInput"])
    ]
)
