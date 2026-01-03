// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XcodeErrorMCP",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "xcode-error-mcp", targets: ["XcodeErrorMCP"]),
    ],
    targets: [
        .executableTarget(
            name: "XcodeErrorMCP",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
    ]
)

