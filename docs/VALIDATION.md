# 验证记录

当前适配层内置原生 SDK `0.1.0-beta.11`。来源、源码摘要、原生构建工具及既有检查结果分别保存在 [PROVENANCE.md](../PROVENANCE.md) 和 [build_records](../build_records)。原始构建记录保留了父工程 commit 与 dirty-source 状态，不能视为干净的正式 tag 构建。

独立仓库上传前检查：

- 从待上传 Git 文件重新导出，在独立目录运行 pub get、插件和 Demo 的 analyze/test。
- 校验完整 AAR/XCFramework 文件清单、SHA-256、Maven 元数据及依赖图。
- 在导出目录构建 Android Demo APK 和 iOS Demo（关闭代码签名）；不携带本机 License 配置。

## EvenHub

既有 beta.11 原生构建记录包含 Android 92 项测试、Swift 60 项测试及链接检查。Flutter Demo 的 18 项测试包含上次连接记录的校验、串行存储、模拟重启恢复、手动重连、namespace 隔离与存储失败处理。

beta.9 的 iOS 用户真机反馈为 37 次原生心跳确认；本轮连续 ACK 原始日志存在采集缺口。Android 真机、主动关闭后停止续期、完整图片与菜单交互等仍待正式固件验收，自动化测试不能代替这些验收。

## TimeSync

beta.10 的 iOS 原始日志观察到固件将请求 magic 回填为低 8 位，导致等待超时。beta.11 两端原生分配统一使用 1–255 非零值，保留完整应答匹配、generation 身份校验和现有超时；Swift 复用业务 AUTH 的分配器。

beta.11 修复后的真实眼镜时间同步结果仍待用户触发验证。

## 连接记录

仅原生整机 READY 更新记录。重启恢复、清除、namespace 切换与存储异常已由自动化测试覆盖；真实眼镜成功连接后跨重启恢复仍待验证。记录不包含 License 或签名。

Demo 首次使用需自行提供合法 License 并手动初始化。iOS 真机运行前请在 Xcode 设置自己的开发团队；上传仓库不包含签名证书或本机 License。
