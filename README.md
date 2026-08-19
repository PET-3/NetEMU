# NetEmu

Android 弱网模拟工具（Flutter + 原生 VPN 用户态代理 / Root tc / Shizuku）。

项目地址：https://github.com/PET-3/NetEMU

版本：**1.1.0**

## 功能概览

- **多后端自动选择**：Root (tc) > Shizuku > ADB 命令导出 > VPN（无 Root）
- **统一 BackendManager**：检测、选择、启停、热更新、健康检查、模式切换
- **VPN 用户态完整双向链路**：
  - 应用 → TUN → TCP/UDP/ICMP 代理 → 网络出口
  - 网络出口 → 代理 → TUN → 应用
  - TCP 连接跟踪（SYN/SYN-ACK/ACK/FIN/RST）、UDP NAT、ICMP Echo（ping）
  - 上传 / 下载独立延迟、丢包、限速
- **弱网参数**：
  - 固定延迟 + 抖动（均匀 / 近似正态分布）
  - 随机丢包、连续丢包（包数模式 / 时间窗口模式）
  - Token Bucket 限速（稳定平均速率，避免硬丢弃突刺）
- **协议过滤**：全部 / TCP / UDP
- **配置管理**：新建、修改、删除、JSON 导入导出
- **预设**：正常 / 2G / 3G / 4G / 4G弱网 / 5G高延迟 / 地铁 / 电梯 / 丢包严重 / 间歇断网 / 限速512K / 仅UDP
- **实时统计**：上下行速度与字节、丢包计数、TCP/UDP 会话数
- **悬浮窗 / 常驻通知**：启停、速度摘要
- **界面**：Material 3，支持系统深浅色

## 后端说明

| 后端 | 权限 | 能力 | 说明 |
|------|------|------|------|
| Root | su | tc netem + HTB/TBF | 真实内核队列，推荐有 Root 设备 |
| Shizuku | 用户授权 | 同 Root（经 Shizuku API） | 需安装并启动 Shizuku，在设置页点「授权 Shizuku」 |
| ADB | PC 侧 adb shell | 导出 tc 命令 | 普通应用无法直接执行 adb；复制命令到电脑执行 |
| VPN | 系统 VPN 授权 | 用户态代理模拟 | 无需 Root，支持真实 TCP/UDP 应用与 ping |

自动优先级：`Root > Shizuku > VPN`（ADB 不作为自动运行后端）。

## 底部导航

| 页 | 说明 |
|----|------|
| 首页 | 启停、选测试/配置、参数图、流量与丢包/会话统计、浮窗与通知开关 |
| 测试 | 仅在首页选择「测试」后出现；可调参数并保存到配置 |
| 配置 | 管理已有配置与预设 |
| 设置 | 后端锁定、Shizuku 授权、ADB 导出、接口、日志、关于 |

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

GitHub Actions：push / PR / workflow_dispatch 自动构建 arm64-v8a APK。

## 权限说明

- **VPN**：系统授权弹窗
- **悬浮窗**：显示在其他应用上层
- **Shizuku**：设置页发起授权，需 Shizuku 应用已启动
- **Root**：`su` 可用时自动优先

## 架构要点

### VPN

1. `NetEmuVpnService` 建立 TUN，读包分发。
2. `TcpProxy`：完成与客户端握手，`protect()` 后连接远端，双向中继。
3. `UdpProxy`：会话映射 + 双向 DatagramSocket。
4. ICMP：Echo Request 本地生成 Echo Reply。
5. `NetworkEmulator`：独立方向实例，Token Bucket + 延迟抖动 + 丢包模型。

### Backend

- `Backend` 接口 + `RootBackend` / `ShizukuBackend` / `AdbBackend` / `VpnBackend`
- `BackendManager`：选择、启停、切换、健康检查、退出清理 qdisc

## 已知限制与后续方向

- Root/Shizuku 路径主要塑造 egress；ingress（下载）在无 ifb 时受限。
- 完整 TCP 选项/分片可进一步评估 lwIP / gVisor netstack。
- 预留按应用限速、CLI/CI 自动化接口。

## 关于

- 项目：https://github.com/PET-3/NetEMU
- 作者邮箱：yyx3307022@gmail.com
- 微信：yyx307022

## 许可

以仓库内 LICENSE 为准。
