# 验证记录

## G2 业务 AUTH（本地 beta.14）

- 干净源码构建通过 125 项 Android 单测及 release lint，80 项 Swift 单测通过。两个插件分发目录各自验证了 73 项交付文件，涵盖 Maven、CocoaPods、SwiftPM、源码包及许可证。原生源码提交、构建检查及制品摘要见[构建记录](../build_records)。
- PHB110 手动连接 S200LABJ270010 后，Android 原生日志确认两条腿各自完成业务 AUTH，整机进入 READY。

## beta.13 构建记录

beta.13 适配层内置原生 SDK `0.1.0-beta.13`。来源、源码摘要、原生构建工具及既有检查结果分别保存在 [PROVENANCE.md](../PROVENANCE.md) 和 [build_records](../build_records)。本次 Android 与 iOS 分别从交付源码包中的干净提交 `03d441c1fb4cc45077f26503f0263876176983fe` 构建。119 项 Android 原生测试与 80 项 Swift 测试通过。构建记录含 Git tree 与制品校验值，源码包内附构建命令。

独立仓库上传前检查：

- 从待上传 Git 文件重新导出，在独立目录运行 pub get、插件和 Demo 的 analyze/test。
- 校验完整 AAR/XCFramework 文件清单、SHA-256、Maven 元数据及依赖图。
- 在导出目录构建 Android Demo APK 和 iOS Demo（关闭代码签名）；不携带本机 License 配置。

## 原生麦克风音频（本地 beta.13）

- Dart 桥接 20 项测试、示例 21 项测试通过，analyze 无问题。覆盖 PCM typed-binary codec 往返、方向正负值/缺失值、麦克风开关参数、低频计数、旧连接隔离和异步结果失效。
- 示例音频统计每 500 毫秒合并刷新，不保存 PCM，不逐帧写入日志。原生负责 LC3 解码与默认 App 音频处理，Flutter 不解码。
- 两端内置沿用 App 的原始解码实现；Android 以隔离 SONAME 打包四 ABI 二进制，iOS 以原始 archive/embedded LLVM IR 重建支持的架构。具体来源和差分边界以 native build_records 与上游验证记录为准，不能将短向量一致性当成所有输入或真机音频验收。
- 此前 beta.13 候选 AAR 在 PHB110、XCFramework 在 arm64 iOS 模拟器上分别与各平台原始 decoder 做 256 帧差分（静音、双音和固定种子噪声）；每端 40,960 个 PCM 样本全部一致，最大误差 0。这验证原生库解码兼容性，不代表 G2 麦克风/BLE 实机验收。
- 原生完整测试为 Android 119 项、Swift 80 项通过。最终适配层 Android Debug APK 与未签名 iOS Debug Runner 构建通过；当前独立插件的 58 项交付文件均通过 SHA-256 校验、Maven sidecar、四 ABI 库及 Apple 架构校验。
- 当前 G2 正式固件的 STREAM 收音、方向与角色、关闭/重启后停止旧音频，以及实机音质均待验收。
- 本地 beta.13 的 SwiftPM 和 CocoaPods 选择同批框架。已发布的 beta.12 仍可按相应 tag 获取。

## G2 OTA（本地 beta.12）

- Android standalone SDK 的 109 项单元测试、release lint、AAR 与 Maven 元数据检查通过。
- Swift SDK 的 72 项测试通过，XCFramework 已通过 arm64 真机、arm64 和 x86_64 模拟器消费端链接。
- 独立 Flutter 插件和示例各 19 项测试通过。分析覆盖插件、示例及其测试源码。Android Debug APK 与未签名 iOS Debug Runner 构建通过。
- Android 和 iOS 真机仍需按正式固件完成双腿升级、传输中断恢复、取消及重连后的目标版本读回。

## EvenHub

既有 beta.11 原生构建记录包含 Android 92 项测试、Swift 60 项测试及链接检查。Flutter Demo 的 18 项测试包含上次连接记录的校验、串行存储、模拟重启恢复、手动重连、namespace 隔离与存储失败处理。

beta.9 的 iOS 用户真机反馈为 37 次原生心跳确认；本轮连续 ACK 原始日志存在采集缺口。Android 真机、主动关闭后停止续期、完整图片与菜单交互等仍待正式固件验收，自动化测试不能代替这些验收。

## TimeSync

beta.10 的 iOS 原始日志观察到固件将请求 magic 回填为低 8 位，导致等待超时。beta.11 两端原生分配统一使用 1–255 非零值，保留完整应答匹配、generation 身份校验和现有超时；Swift 复用业务 AUTH 的分配器。

beta.11 修复后的真实眼镜时间同步结果仍待用户触发验证。

## 连接记录

仅原生整机 READY 更新记录。重启恢复、清除、namespace 切换与存储异常已由自动化测试覆盖；真实眼镜成功连接后跨重启恢复仍待验证。记录不包含 License 或签名。

Demo 首次使用需自行提供合法 License 并手动初始化。iOS 真机运行前请在 Xcode 设置自己的开发团队；上传仓库不包含签名证书或本机 License。
