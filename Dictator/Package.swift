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
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "Dictator",
            dependencies: [
                "FluidAudio",
            ],
            path: "Sources/Dictator",
            exclude: ["Info.plist"]
        )
    ]
)
