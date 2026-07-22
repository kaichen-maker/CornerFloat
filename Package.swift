// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CornerFloat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CornerFloat", targets: ["CornerFloat"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .executableTarget(
            name: "CornerFloat",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CornerFloat",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("AuthenticationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../Frameworks"
                ])
            ]
        )
    ]
)
