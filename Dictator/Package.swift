// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dictator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Dictator", targets: ["Dictator"])
    ],
    targets: [
        .executableTarget(
            name: "Dictator",
            path: "Sources/Dictator",
            exclude: ["Info.plist"]
        )
    ]
)
