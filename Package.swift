// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WorldZones",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WorldZones", path: "Sources/WorldZones")
    ]
)
