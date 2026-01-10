// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Maverick",
    platforms: [
        .macOS(.v12), .iOS(.v14),
    ],
    products: [
        .executable(name: "Maverick", targets: ["Maverick"]),
        .library(name: "MaverickModels", targets: ["MaverickModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.67.5"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.2.4"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "0.9.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "1.0.0"),
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
                "Yams"
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
    ],
    swiftLanguageModes: [
        .v5,
    ]
)
