# 原生 SDK Flutter 示例

只依赖 `even_devices_native`，用于手动验证原生 G2 连接、EvenHub 与双腿 OTA。启动不会自动初始化、扫描或连接。

## 原生依赖

Android 使用 Maven Central 的 beta.14，iOS 使用 SPM 的同版本 SDK。运行 iOS 前执行 `fvm flutter config --enable-swift-package-manager`；也可在构建命令前添加 `FLUTTER_SWIFT_PACKAGE_MANAGER=true`。示例已移除 CocoaPods 集成，详见[依赖迁移记录](../docs/DEPENDENCY_MIGRATION.md)。

```bash
fvm flutter pub get
cd example
fvm flutter run -d <device-id>
```

1. 打开右上角设置，填写 namespace 和签名平台导出的完整多 SN License JSON，初始化并允许系统蓝牙权限；Android 旧系统还需开启定位服务。
2. 在「扫描」页扫描，等目标 SN 的左右腿均被发现后点击连接。扫描候选独立于当前设备详情。
3. 在「设备」页查看整机状态、SN、双腿端点和原生阶段。整机 READY 后可执行时间同步、EvenHub 或 OTA。进行 OTA 时，关闭活动的 EvenHub 页面，选择对应型号的 EVENOTA `.bin`（示例限 32 MiB），填写固件发布的目标版本，再点击开始升级。可在本页查看进度和取消，最终成功需等双腿重连并读回目标版本。
4. 在「EvenHub」页编辑短文字并显示到眼镜。预览是待提交内容；原生 `active` 才代表眼镜确认创建。页面创建成功后点击「开启麦克风」。收到音频后，每 0.5 秒刷新累计帧数、字节数和最近一帧的前 32 个 PCM 字节（十六进制）。点击「停止麦克风」清空预览；音频字节只在页面内短暂显示。
5. 「日志」页独立展示带时间的请求和原生事件，支持搜索、类别筛选、暂停显示、清空和复制；暂停仍会采集，最多保留 500 条。复制内容经过字段白名单处理。
6. 结束时断开或 Reset。切换 namespace 后重新初始化。EvenHub 页面活动时暂不可同步时间，避免与页面命令竞争原生传输。

「设备」页会记录该 namespace 上次成功连接的眼镜 SN、左右腿端点及时间，重启 Demo 后仍可查看。初始化后点击「连接上次设备」可直接提交重连；若当前扫描已发现同一 SN 的完整双腿，则优先使用新端点。每次连接仍由原生 SDK 匹配 License、执行企业验签和业务 AUTH。

只有原生整机 READY 才会更新记录；扫描、连接请求和单腿成功不会覆盖。断开或 Reset 保留记录，「清除记录」只删除当前 namespace 的本机历史，不断开眼镜。记录不包含 License 或签名，也不会触发自动初始化、扫描或连接。Android 使用 SharedPreferences，iOS 使用 UserDefaults，均通过 Demo 自己的存储通道读写，不新增依赖。

也可以用本机、不入 Git 的文件预填 license：

```bash
fvm flutter run -d <device-id> --dart-define-from-file=/absolute/path/local-config.json
```

配置文件结构为 `{"EVEN_ENTERPRISE_LICENSE_JSON":"<完整 JSON 字符串>"}`。示例不携带真实签名、平台账号或私钥，日志不打印 license 和原始业务 payload。宿主 applicationId 与签名使用的 `app_id` 由接入方确认；不要改写签名中的 app_id。

Android 示例固定 compileSdk 36 / NDK 27.0.12077973；iOS 最低 15.0，已添加蓝牙用途说明。示例 UI 演示连接、时间同步和 EvenHub 文字页；其余 EvenHub 指令可通过插件公共 API 接入。不包含 R1、通知和 OTA 演示。

EvenHub 的编码、命令应答、图片分包、页面心跳和事件解析均在原生 SDK。示例只提交文字与展示原生事件，不持有业务定时器或协议状态机。

iOS 示例使用单窗口 UIScene 生命周期，以支持 Xcode 27 / iOS 27 的启动要求。仓库固定的 Flutter 3.32 尚无 `FlutterSceneDelegate`，因此示例在自定义 `SceneDelegate` 获取 storyboard 创建的 Flutter 控制器后注册插件，复用同一个 engine。迁移到 Flutter 3.38 以上时可按 [Flutter 官方说明](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)改用框架提供的 scene delegate。

## 构建和原生 license 校验测试

```bash
fvm flutter build apk --debug
fvm flutter build ios --no-codesign --debug
```

Apple Silicon + Xcode 27 上，Flutter 3.32 通用模拟器构建遇到多架构 `lipo` 校验问题时，在 `example/ios` 使用单架构验证。替换为 `xcrun simctl list devices available` 中的模拟器 UUID：

```bash
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<simulator-uuid>' \
  -derivedDataPath ../build/native-simulator-test \
  'CONFIGURATION_BUILD_DIR=$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -only-testing:RunnerTests test
```

此测试实际链接 Swift SDK，通过插件提交非法 JSON，确认原生拒绝后不能扫描；不申请蓝牙权限或连接眼镜。Intel Mac 使用 `ARCHS=x86_64`。通用模拟器构建需要包含 [上游修复](https://github.com/flutter/flutter/pull/188625) 的 Flutter 工具链。

2026-11-09 验证：示例 analyze 无问题，11 项 widget 测试通过；链接最终 beta.6 的 Android APK 与 iOS Profile 签名构建通过。iOS 已安装启动到 WK iPhone 15，但此次没有触发真实眼镜连接。原生 10 条 EvenHub 指令、产物身份和完整测试结果见 [验证记录](../docs/VALIDATION.md#evenhub)。

后续 beta.7 在两端原生 SDK 修复了心跳 Cnt 回显要求和通知尾部填充解析。复测时先连接眼镜，再显示文字，观察「心跳确认」持续递增；问题定位日志使用原生 `[EvenDevicesSDK][EvenHubHeartbeat]` 前缀。详见[心跳修复记录](../docs/VALIDATION.md#evenhub)。

诊断版 beta.8 增加 ACK 命令、magic、字段编号与类型、具体拒绝项诊断；不输出页面或 License 内容。beta.7 真机仍失败，不能将成功结果码 12 单独视为整条心跳应答已通过。

beta.9 仅在原生心跳应答支持现场观察到的 Cmd12 变体，标准 Cmd13、响应分支15、成功码12及连接身份校验保留。验收需观察连续心跳确认超过15秒，并确认主动关闭后停止续期。

2026-11-09 beta.9：WK iPhone 15 用户反馈心跳确认37次。计数来自原生已校验 ACK 事件；因控制台断开，尚无本轮连续 ACK 原始日志，关闭停止续期与 Android 真机待验。

2026-11-09 beta.11：两端原生 TimeSync 请求使用 1–255 非零 magic，修复 beta.10 日志证实的低 8 位回填匹配问题。安装后需手动初始化、连接并关闭 EvenHub，再点击时间同步；构建通过不能代替本轮真机验收。

2026-11-09 连接记录：Demo analyze 无问题，18 项测试通过（包含记录校验、串行存储、重启恢复、手动重连、namespace 隔离及存储失败）。Android APK 与 iOS Profile 签名构建通过，继续链接 beta.11；本次尚未做真实眼镜连接后的跨重启验收。
