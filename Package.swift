// swift-tools-version: 5.9
import PackageDescription

// Native iOS consumers reuse the audited framework shipped with the Flutter
// plugin. No Flutter source, runtime or second BLE owner enters this product.
let package = Package(
    name: "EvenDevicesSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "EvenDevicesSDK", targets: ["EvenDevicesSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "EvenDevicesSDK",
            path: "ios/Frameworks/EvenDevicesSDK.xcframework"
        ),
    ]
)
