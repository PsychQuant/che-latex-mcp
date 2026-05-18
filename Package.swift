// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "che-latex-mcp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "che-latex-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)
