// swift-tools-version: 6.2

import PackageDescription

let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "SwiftDunk",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SwiftDunk", targets: ["SwiftDunk"]),
        .library(name: "SwiftDunkTestSupport", targets: ["SwiftDunkTestSupport"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/adam-fowler/swift-srp",
            from: "2.3.0"
        ),
        .package(
            url: "https://github.com/apple/swift-certificates",
            from: "1.19.0"
        ),
        .package(
            url: "https://github.com/apple/swift-crypto",
            from: "3.9.0"
        ),
    ],
    targets: [
        .target(
            name: "SwiftDunkCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            swiftSettings: commonSettings
        ),
        .target(
            name: "SwiftDunkAnisette",
            dependencies: ["SwiftDunkCore"],
            swiftSettings: commonSettings
        ),
        .target(
            name: "SwiftDunkAuth",
            dependencies: [
                "SwiftDunkAnisette",
                .product(name: "SRP", package: "swift-srp"),
            ],
            swiftSettings: commonSettings
        ),
        .target(
            name: "SwiftDunkPortal",
            dependencies: ["SwiftDunkAuth"],
            swiftSettings: commonSettings
        ),
        .target(
            name: "SwiftDunkCertificates",
            dependencies: [
                "CSwiftDunkSecurity",
                "SwiftDunkPortal",
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: commonSettings
        ),
        .target(
            name: "CSwiftDunkSecurity",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "SwiftDunk",
            dependencies: ["SwiftDunkCertificates"],
            swiftSettings: commonSettings
        ),
        .target(
            name: "SwiftDunkTestSupport",
            dependencies: ["SwiftDunk"],
            swiftSettings: commonSettings
        ),
        .testTarget(
            name: "SwiftDunkTests",
            dependencies: [
                "SwiftDunkTestSupport",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "SRP", package: "swift-srp"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: commonSettings
        ),
        .executableTarget(
            name: "swiftdunk-cli",
            dependencies: ["SwiftDunk"],
            path: "Examples/CLI",
            swiftSettings: commonSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
