# NetEmu

[![Flutter](https://img.shields.io/badge/Flutter-3.32+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Kotlin](https://img.shields.io/badge/Kotlin-Android-7F52FF?logo=kotlin&logoColor=white)](https://kotlinlang.org)
[![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![License](https://img.shields.io/badge/License-See%20repo-lightgrey)](LICENSE)
[![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](../../actions)

**Android 弱网模拟与网络条件测试工具**

在真机上对延迟、抖动、丢包、带宽进行可控模拟，支持 **无 Root（VPN 用户态代理）**、**Root（tc netem）**、**Shizuku** 与 **ADB 命令导出**，面向开发、测试与质量保障场景。

项目地址：https://github.com/PET-3/NetEMU

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 跨端 UI | Flutter 3.32+ / Dart 3.8+ / Material 3 / Provider |
| Android 原生 | Kotlin / VpnService / Foreground Service |
| 用户态网络 | TUN 读写 · TCP/UDP 代理 · ICMP Echo |
| 内核弱网 | Linux `tc` · `netem` · HTB / TBF |
| 特权通道 | Root (`su`) · [Shizuku](https://github.com/RikkaApps/Shizuku) API |
| 工程 | Gradle 8 · GitHub Actions · arm64-v8a Release APK |
| 辅助库 | shared_preferences · path_provider · archive · file_picker · share_plus |

---

## 功能概览

- **多后端**：Root > Shizuku > VPN（自动或手动锁定）；ADB 仅导出命令
- **VPN 双向链路**：应用 ↔ TUN ↔ TCP/UDP/ICMP 代理 ↔ 真实网络
- **弱网参数**（上下行独立）：延迟、抖动、随机/连续丢包、Token Bucket 限速
- **配置体系**：自定义 / JSON 导入 / ZIP 导入；多选分享与批量删除
- **调节页**：热更新参数；保存（替换/另存）；**恢复修改前**
- **统计**：速率、字节、丢包计数、TCP/UDP 会话；可选延迟/丢包曲线
- **日志**：级别与时间戳；导出；自动保留最近 500 条
- **首次启动免责声明**

---

## 截图与主流程（简述）

1. 同意免责声明 → 首页选择 **临时** 或 **配置**
2. 一键启动模拟 → 通知栏 / 可选浮窗查看状态
3. **调节** Tab 修改参数并保存或恢复
4. **配置** 页管理、分享、从 JSON/ZIP 导入

---

## 后端说明

| 后端 | 权限 | 能力 |
|------|------|------|
| Root | `su` | 内核 `tc netem` + HTB/TBF，退出自动清 qdisc |
| Shizuku | 用户授权 | 经 Shizuku 执行同等 shell（无需完整 Root） |
| ADB | PC 侧 | 导出 `adb shell tc ...`，应用内不执行 adb |
| VPN | 系统 VPN 授权 | 用户态代理，无需 Root，支持真实 TCP/UDP 与 ping |

> Root/Shizuku 主要塑造 **egress**；无 ifb 时 ingress（下载）塑造能力有限。

---

## 构建

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release --target-platform android-arm64
```

CI：`.github/workflows/build.yml`（push / PR / workflow_dispatch）。

最低系统：**Android 8.0（API 26）**，当前打包 **arm64-v8a**。

---

## 架构要点

```
Flutter UI ──MethodChannel──▶ MainActivity / BackendManager
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              RootBackend    ShizukuBackend    VpnBackend
                    │               │               │
                 tc netem        tc via          TUN +
                                                 TcpProxy
                                                 UdpProxy
                                                 ICMP
```

- `NetworkEmulator`：每方向独立实例（丢包 / 延迟抖动 / Token Bucket）
- 配置 JSON 可导入导出；ZIP 内多个 `.json` 批量导入

---

## 权限与合规

- VPN、悬浮窗、通知：按系统弹窗授权
- Shizuku：设置页发起授权
- **仅用于合法、授权范围内的测试**；详见应用内免责声明

**已知不可用能力**：无法向应用「伪装未开弱网」的同时仍实施弱网（VPN/tc 机制限制）。

---

## 版本

当前：**1.1.0**

---

## 关于

- 仓库：https://github.com/PET-3/NetEMU
- Email：yyx3307022@gmail.com
- 微信：yyx307022

许可以仓库内 `LICENSE` 为准。
