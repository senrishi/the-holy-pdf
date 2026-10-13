// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TheHolyPdf",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TheHolyPdf"
        )
    ]
)
