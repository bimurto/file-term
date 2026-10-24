// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FileTermCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "FileTermCore", targets: ["FileTermCore"])],
  targets: [
    .target(name: "FileTermCore", path: "FileTerm/Core"),
    .testTarget(
      name: "FileTermCoreTests", dependencies: ["FileTermCore"], path: "FileTermCoreTests"),
  ]
)
