// swift-tools-version: 5.9
import PackageDescription

// Keep the Flutter adapter separate from the Flutter-free binary SDK. Pin the
// same release as Android so each host receives identical protocol capabilities.
let package = Package(
    name: "even_devices_native",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "even-devices-native", targets: ["even_devices_native"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/even-realities/flutter_enterprise_sdk.git",
            exact: "0.1.0-beta.14"
        ),
    ],
    targets: [
        .target(
            name: "even_devices_native",
            dependencies: [
                .product(name: "EvenDevicesSDK", package: "flutter_enterprise_sdk"),
            ],
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
    ]
)
