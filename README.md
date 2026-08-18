# NetEmu — Android 弱网模拟工具

真正可用的 Android 网络条件模拟器（非代理软件）。

## 架构

```
Flutter UI
    ↓
NetworkController (MethodChannel)
    ↓
Backend Manager
  ├── VPN  → VpnService → TUN → TcpProxy / UdpProxy → NetworkEmulator → Internet
  ├── Root → su -c "tc netem / tbf"
  ├── Shizuku → shell tc（需授权）
  └── ADB → 导出 adb shell 命令（不伪造 in-app 执行）
```

### NetworkEmulator（独立模块）

所有后端共用：

- 延迟 / 抖动
- 随机丢包
- 连续丢包状态机
- Token-bucket 带宽

运行中修改参数可立即生效（无需重启 VPN）。

### VPN 模式

- **TCP**：用户态握手 + 双向中继（protect Socket）
- **UDP**：会话映射 + 双向 DatagramSocket
- **DNS**：经 UDP 代理
- delay=0 时不引入额外固定延迟

## 参数范围

| 参数 | 范围 |
|------|------|
| 延迟 | 0–3000 ms |
| 抖动 | 0–1000 ms |
| 带宽 | 不限 / 64K–50M 档位 |
| 随机丢包 | 0–100% |
| 连续丢包 | 放行/丢包各 0–100 |

预设：正常 / 4G / 3G / 高延迟 / 极差网络

## 构建（仅 arm64-v8a）

```bash
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

GitHub Actions 输出：`NetEMU-arm64-v8a.apk`

## 权限说明

- VPN：系统 VPN 授权
- Root：su + tc
- Shizuku：安装并授权后可执行 shell tc
- ADB：日志中导出命令，在 PC 执行

## 安全

不进行 HTTPS 解密 / MITM / 内容抓取，只控制网络条件。
