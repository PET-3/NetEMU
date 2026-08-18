# NetEmu — Android 网络模拟器

专业 Android 弱网环境模拟工具。支持四种后端：

| 后端 | 权限要求 | 原理 |
|------|----------|------|
| **Root** | su | Linux `tc` / `netem` / `tbf` |
| **Shizuku** | Shizuku 授权 | shell 权限执行 `tc` |
| **ADB Shell** | 无线调试 | 导出 adb 命令或 PC 辅助 |
| **VPNService** | 无 Root | TUN + 用户态延迟/丢包/限速 |

## 功能

- 上下行独立控制：延迟、抖动、带宽、随机丢包、连续丢包（状态机）
- 自动检测最佳后端（Root > Shizuku > ADB > VPN）
- 网络接口自动识别与手动选择
- 配置保存 / 导入 / 导出
- 实时统计（流量、包数、丢包计数）
- 前台服务 + 通知
- Material 3 UI

## 架构

```
Flutter UI
    │
NetworkController (MethodChannel / EventChannel)
    │
Backend Manager
    ├── VPN Backend  → VpnService → TUN → Packet Processor → Internet
    ├── Shizuku      → shell → tc/netem
    ├── ADB          → adb shell / 命令导出
    └── Root         → su -c "tc ..."
```

## 安装与权限

1. 安装 APK
2. 首次使用 VPN 模式时授权 VPN 权限
3. （可选）安装 [Shizuku](https://shizuku.rikka.app/) 并授权以获得更好效果
4. Root 设备自动优先使用 tc

### VPN 模式原理

创建 TUN 接口，将设备流量导入用户态。  
对每个包应用：

- 随机丢包 / 连续丢包状态机
- 延迟 + 抖动
- Token-bucket 带宽限制

然后转发到真实网络。  
当前实现重点保证 **UDP 路径可跑通**；完整 TCP 状态机会在后续版本完善。

### Root / Shizuku 模式

直接对当前默认出口（wlan0 / rmnet_data0 等）下发：

```bash
tc qdisc add dev wlan0 root netem delay 100ms 20ms loss 5%
tc qdisc add dev wlan0 root tbf rate 512kbit burst 32kbit latency 400ms
```

## 编译

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### GitHub Actions

推送 `main` 或手动触发即可自动构建并上传 APK Artifact。

## 参数范围

| 参数 | 范围 |
|------|------|
| 延迟 | 0–60000 ms |
| 抖动 | 0–60000 ms |
| 带宽 | 0（不限）–102400 Kbps |
| 随机丢包 | 0–100 % |
| 连续丢包 | 放行 N / 丢包 M 循环 |

## 安全说明

- **不**进行 HTTPS 解密 / MITM
- **不**抓取或保存用户网络内容
- 只控制网络条件参数

## 限制

- VPN 模式下完整双向 TCP 需要更完整的用户态协议栈（当前重点验证 UDP + 控制面）
- ADB 模式在 App 内直接执行受系统限制，推荐导出命令在 PC 上执行
- Shizuku 完整授权需要集成 Shizuku API 库（当前检测安装状态）

## 项目结构

```
netemu/
├── android/          # Kotlin VpnService / MethodChannel
├── lib/
│   ├── backend/
│   ├── models/
│   ├── services/
│   ├── screens/
│   └── widgets/
├── .github/workflows/
└── README.md
```

## License

MIT
