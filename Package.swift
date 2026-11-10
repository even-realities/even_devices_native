// swift-tools-version: 5.9
import PackageDescription

// SwiftPM consumes the same release framework as the Flutter CocoaPods adapter.
let package = Package(
    name: "EvenDevicesSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "EvenDevicesSDK", targets: ["EvenDevicesSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "EvenDevicesSDK",
            path: "spm/EvenDevicesSDK-0.1.0-beta.14.xcframework.zip"
        ),
    ]
)
