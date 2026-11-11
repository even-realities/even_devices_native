# 原生 SDK 与 Flutter 插件发布

SDK 使用 Apache 2.0 许可。Android/iOS 原生源码、共享协议、原生示例和发布脚本现统一在独立的 [enterprise_sdk 仓库](https://github.com/even-realities/enterprise_sdk)维护。Flutter 仓库只负责插件、参数/事件适配及 Flutter 示例。

| 平台 | 当前分发入口 | 发布维护位置 |
| --- | --- | --- |
| Android | `com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14` | 原生仓库构建并上传 Maven Central；坐标不变 |
| iOS | `https://github.com/even-realities/enterprise_sdk.git`，exact `0.1.0-beta.14`，product `EvenDevicesSDK` | 原生仓库根目录 `Package.swift` 和对应版本 tag |
| Flutter | `https://github.com/even-realities/flutter_enterprise_sdk.git` | 本仓库 `main` 或审核后的插件 commit |

## 原生 SDK 发布

按 [原生发布指南](https://github.com/even-realities/enterprise_sdk/blob/main/docs/PUBLISHING.md)在原生仓库执行构建、签名、打包和发布。公司 Central Token/GPG 私钥通过环境或 CI 密钥注入，不能写入仓库或聊天。

此次仓库拆分复用原始 beta.14 二进制，不重新发布已存在的 Maven 版本。下一次有原生改动时使用新的版本，并在原生仓库完成 Android/iOS 测试、产物校验、SPM 解析及双平台宿主构建。传输成功、构建通过或自动化测试通过均不能代替真机接入及 OTA 安装验收。

本仓库的 `android/maven`、`ios/Frameworks`、`spm`、`source`、根目录 `Package.swift`、原有版本 tag 和 `tool/package_maven_central.py` / `tool/publish_maven_central.py` 保留用于既有版本的来源核验。历史 `PROVENANCE.md`、`build_records` 和校验清单描述原始构建，不改写为新仓库身份。后续原生发行应使用原生仓库的脚本。

## Flutter 插件更新

1. 原生 SDK 两端发布完成并可从远端解析后，再更新 `android/build.gradle` 的 Maven 版本和 `ios/even_devices_native/Package.swift` 的 exact 版本。
2. 两端指向同一原生版本；iOS package identity 为 `enterprise_sdk`，product 保持 `EvenDevicesSDK`。
3. 在插件和 `example` 分别执行 `fvm flutter pub get`、`fvm flutter analyze`、`fvm flutter test`；运行 `tool/verify_artifacts.sh` 核验归档与依赖契约。
4. 远端解析 SPM 并更新示例的 `Package.resolved`，构建 Android APK 和 iOS 宿主。记录实际解析的原生 tag/commit 和产物校验值。
5. 提交插件变更。现有客户端 pin 的历史 tag 或 commit 保持可用，不移动/覆盖已有 tag，也不删除旧二进制。

启用 Flutter SPM：

```bash
fvm flutter config --enable-swift-package-manager
fvm flutter pub get
cd example
fvm flutter build apk --debug
fvm flutter build ios --profile --no-codesign
```

完整接口：[Flutter](enterprise/enterprise-flutter-sdk.md)、[Android](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-android-sdk.md)、[iOS](https://github.com/even-realities/enterprise_sdk/blob/main/docs/enterprise/enterprise-ios-sdk.md)。
