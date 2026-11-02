// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAutoKey",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacAutoKey", targets: ["MacAutoKey"])],
    targets: [
        .executableTarget(name: "MacAutoKey"),
        .testTarget(name: "MacAutoKeyTests", dependencies: ["MacAutoKey"])
    ]
)
