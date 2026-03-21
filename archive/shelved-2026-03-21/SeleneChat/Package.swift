// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SeleneChat",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "SeleneChat",
            targets: ["SeleneChat"]
        ),
        .executable(
            name: "selene-calendar",
            targets: ["selene-calendar"]
        ),
        .library(
            name: "SeleneShared",
            targets: ["SeleneShared"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "SeleneShared",
            path: "Sources/SeleneShared"
        ),
        .executableTarget(
            name: "SeleneChat",
            dependencies: [
                "SeleneShared",
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/SeleneChat",
            exclude: [
                "Services/CLAUDE.md",
                "Views/CLAUDE.md"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "selene-calendar",
            path: "Sources/SeleneCalendar",
            exclude: [
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "SeleneChatTests",
            dependencies: ["SeleneChat", "SeleneShared"],
            path: "Tests",
            exclude: [
                "FOCUS_TEST_PLAN.md",
                "UAT"
            ]
        )
    ]
)
