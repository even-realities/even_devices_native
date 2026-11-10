# Even Enterprise Sdk

[English](README.md) | 简体中文

基于 Flutter 的 SDK，用于构建连接 **Even G2 glasses** 的 Android 和 iOS 应用，也提供 Kotlin、Swift 原生 SDK 供直接接入。蓝牙连接、设备授权、显示指令、麦克风音频和固件升级均由原生 SDK 处理。

## 申请使用

Enterprise SDK 当前处于 **alpha 申请阶段**。要让自己的应用连接 glasses：

1. 在 [Even Hub 官网](https://hub.evenrealities.com/)注册或登录。
2. 进入 [Enterprise tab](https://hub.evenrealities.com/hub?tab=enterprise) 申请 alpha 使用资格，并查看设备授权与固件详情。
3. 审核通过后，按接入指引获取设备 License 和已启用企业服务的固件。

## 选择接入方式

| 应用 | 安装方式 | 接入指南 |
| --- | --- | --- |
| Flutter | 通过 Git 依赖引入 `even_devices_native`。 | [Flutter 安装](#安装-flutter) |
| 原生 Android | 在 Gradle 中添加 `mavenCentral()` 和 `implementation("com.evenrealities.devices:even-devices-native-android:0.1.0-beta.14")`。 | [Kotlin 接入](docs/NATIVE_SDK.md#android--maven-central) |
| 原生 iOS | 在 Xcode 中通过 Swift Package Manager 添加[本仓库](https://github.com/even-realities/flutter_enterprise_sdk.git)，选择精确版本 `0.1.0-beta.14` 和 `EvenDevicesSDK` product。 | [Swift 接入](docs/NATIVE_SDK.md#ios--swift-package-manager) |

## 插件内容

- 设备扫描、左右腿连接状态、企业验签和时间同步。
- Even Hub 页面、文字、图片、音频、IMU、菜单及交互指令；原生 SDK 负责协议编码、应答和页面心跳。
- G2 固件升级由原生 SDK 执行，接入方式见[升级指南](docs/INTEGRATION.zh-CN.md#g2-固件升级)。
- 通过 Maven Central 引入 Android SDK，通过 Swift Package Manager 引入 iOS SDK，附带扫描、设备、Even Hub 和日志分开展示的示例。

当前支持 G2，详见[能力与范围](docs/SCOPE.md)。

## 安装 Flutter

在 App 的 `pubspec.yaml` 中添加依赖，然后执行 `flutter pub get`：

```yaml
dependencies:
  even_devices_native:
    git:
      url: https://github.com/even-realities/flutter_enterprise_sdk.git
      ref: ea53058edac83a6d7ecc6406593ab383c1f41e48
```

上面的依赖将 Flutter 适配层固定到审核后的 commit；两端原生 SDK 依赖均为 `0.1.0-beta.14`。

要求：Android 5.0+（API 21）、iOS 15+，以及已启用企业服务的眼镜固件。仓库使用 Flutter 3.32.0；构建要求与蓝牙权限见[平台配置](docs/INTEGRATION.zh-CN.md#平台要求)。iOS 宿主须在 `Info.plist` 中添加 `NSBluetoothAlwaysUsageDescription`。

iOS 构建前先开启 Swift Package Manager（本仓库验证 Flutter 3.32）：

```bash
flutter config --enable-swift-package-manager
```

也可仅对当前构建设置 `FLUTTER_SWIFT_PACKAGE_MANAGER=true flutter build ios`。
插件要求 Flutter 3.32+，iOS 仅使用 SPM。Android 宿主的依赖仓库需要包含 `google()` 和 `mavenCentral()`。
已有 iOS 工程的迁移步骤见[原生依赖管理](docs/INTEGRATION.zh-CN.md#原生依赖管理)。

## 如何使用

### 1. 初始化并扫描

准备签名平台导出的 License JSON，其中包含 App ID 和已授权的眼镜 SN。在 App 中声明资源：

```yaml
flutter:
  assets:
    - assets/even_license.json
```

先监听事件，再初始化：

```dart
import 'package:even_devices_native/even_devices_native.dart';
import 'package:flutter/services.dart';

final sdk = EvenDevicesNative.instance;
final subscription = sdk.events.listen((event) {
  // 将 discovery 事件中的 event.sn 和 event.devices 展示在扫描列表中。
  if (event.type == 'g2' &&
      event.phase == 'ready' &&
      event.side == null &&
      (event.generation ?? 0) > 0) {
    // 左右腿均已授权，可在 UI 中启用设备操作。
  }
  // 通过 timeSync 和 evenHub 事件观察指令结果及交互。
});

if (!await sdk.requestBluetoothPermissions()) {
  throw StateError('Bluetooth permission denied');
}
await sdk.initialize(
  namespace: 'my-enterprise-app',
  licenseJson: await rootBundle.loadString('assets/even_license.json'),
);
await sdk.scan();
```

### 2. 连接选中的眼镜

从扫描事件中收集同一 SN 的左右腿，两个端点可能分别到达。使用原始地址和名称提交连接：

```dart
Future<void> connectSelectedGlasses({
  required String sn,
  required G2Endpoint left,
  required G2Endpoint right,
}) async {
  await sdk.stopScan();
  await sdk.connectG2(sn: sn, left: left, right: right);
}
```

原生 SDK 按目标 SN 匹配 License JSON，未匹配时在连接前拒绝。保留导出的 `app_id` 原值；App 中仅保存签名证明，签名平台账号和私钥应保存在 App 之外。

### 3. 显示 Even Hub 页面

收到原生整机 `ready` 事件后，显示一个短文字页面：

```dart
await sdk.openEvenHubTextPage(text: 'Hello Even Hub');
// evenHub / active 表示眼镜确认创建页面；原生 SDK 自动续期心跳。
// 通过 evenHub / input 事件接收交互。

// 用户结束使用时：
await sdk.closeEvenHub();
await sdk.disconnectG2();
await sdk.reset();
await subscription.cancel();
```

连接和短文字页接口完成时表示请求已提交，实际结果通过 `sdk.events` 返回。其它页面及设备交互使用 `executeEvenHubCommand`，参数见[指令契约](docs/evenhub_commands.json)和[接入参考](docs/INTEGRATION.zh-CN.md)。

## 运行示例

连接手机后，在仓库根目录执行：

```bash
fvm flutter pub get
cd example
fvm flutter run
```

打开设置，粘贴 License JSON 并初始化；扫描并选择眼镜后，在设备、Even Hub 和日志页进行操作。设备详情可选择 G2 固件文件并输入目标版本进行 OTA。示例会记录上次成功连接的眼镜，供手动重连。详见[示例说明](example/README.md)。

## 官方文档

从 **[Even Enterprise 文档](https://hub.evenrealities.com/docs/enterprise/)**开始（即将上线）。上线前可先参考本仓库的 [Flutter 接入参考](docs/INTEGRATION.zh-CN.md)、[原生 SDK 指南](docs/NATIVE_SDK.md)和[示例应用](example/README.md)。

[验证状态](docs/VALIDATION.md) · [原生产物来源](PROVENANCE.md) · [Apache 2.0 许可证](LICENSE) · [第三方许可](THIRD_PARTY_NOTICES.md)
