// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MergeWatch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MergeWatch", targets: ["MergeWatch"])],
    targets: [.executableTarget(name: "MergeWatch")]
)
