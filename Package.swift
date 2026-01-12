// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Maverick",
    platforms: [
        .macOS(.v15), .iOS(.v18),
    ],
    products: [
        .executable(name: "Maverick", targets: ["Maverick"]),
        .library(name: "MaverickModels", targets: ["MaverickModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
        .package(url: "https://github.com/vapor/multipart-kit.git", from: "4.7.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.5.1"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "0.9.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.7.3"),
        .package(url: "https://github.com/jsorge/textbundleify.git", branch: "master"),
        .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "2.2.0"),
    ],
    targets: [
        .target(
            name: "Micropub",
            dependencies: [
                "PathKit",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .target(
            name: "MaverickLib",
            dependencies: [
                .product(name: "Leaf", package: "leaf"),
                "MaverickModels",
                "Micropub",
                "ShellOut",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "TextBundleify", package: "textbundleify"),
                "PathKit",
                .product(name: "Vapor", package: "vapor"),
                "Yams",

                // unused in the target but needed to let the dependency be pinned for Sendable-related
                // reasons. The version attached to Vapor has Swift 6 build errors, but the one in the
                // package dependencies does not. Hopefully this can go away at some point.
                .product(name: "MultipartKit", package: "multipart-kit"),
            ]
        ),
        .executableTarget(
            name: "Maverick",
            dependencies: [
                "MaverickLib"
            ]
        ),
        .target(
            name: "MaverickModels",
                dependencies: [
                    "PathKit",
                ]
        ),
        .testTarget(
            name: "MaverickLibTests",
            dependencies: [
                "MaverickLib",
                "PathKit",
                .product(name: "TextBundleify", package: "textbundleify"),
            ]
        ),
    ]
)
