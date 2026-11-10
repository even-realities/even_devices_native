// swift-tools-version: 5.9
import PackageDescription

// Pin the native iOS archive independently of the Flutter plugin binaries.
let package = Package(
    name: "EvenDevicesSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "EvenDevicesSDK", targets: ["EvenDevicesSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "EvenDevicesSDK",
            path: "spm/EvenDevicesSDK-0.1.0-beta.12.xcframework.zip"
        ),
    ]
)
