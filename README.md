# NetEmu 补丁 v2 — 完整可替换文件

所有文件均为**完整源码**，按路径直接覆盖项目中对应文件即可，无需再手动合并。

## 新增能力

| 能力 | 说明 |
|------|------|
| 连续丢包双模式 | 包数模式 + 时间模式（参考暮雪辞） |
| 协议过滤 | 全部 / 仅 TCP / 仅 UDP |
| 控制悬浮窗 | 可拖动，快速切换延迟/丢包预设 |
| 信息悬浮窗 | 实时上下行速度 + 丢包统计 |
| 实时速度 | 滑动窗口计算 |
| tc 规则 | HTB 优先，失败回退 TBF |

## 覆盖文件列表

```
lib/models/network_config.dart
lib/models/backend_status.dart
lib/services/native_bridge.dart
lib/services/config_service.dart
lib/services/network_controller.dart
lib/screens/home_screen.dart
lib/widgets/direction_card.dart
lib/widgets/protocol_and_float_section.dart
lib/widgets/stat_tile.dart

android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/netemu/netemu/MainActivity.kt
android/app/src/main/kotlin/com/netemu/netemu/backend/ShellBackend.kt
android/app/src/main/kotlin/com/netemu/netemu/emulator/EmulatorConfig.kt
android/app/src/main/kotlin/com/netemu/netemu/emulator/EmulatorStats.kt
android/app/src/main/kotlin/com/netemu/netemu/emulator/NetworkEmulator.kt
android/app/src/main/kotlin/com/netemu/netemu/float/FloatWindowService.kt
android/app/src/main/kotlin/com/netemu/netemu/vpn/NetEmuVpnService.kt
android/app/src/main/kotlin/com/netemu/netemu/vpn/PacketUtil.kt
android/app/src/main/kotlin/com/netemu/netemu/vpn/TcpProxy.kt
android/app/src/main/kotlin/com/netemu/netemu/vpn/UdpProxy.kt
```

## 使用步骤

1. 解压本补丁
2. 将上述文件按相对路径覆盖到你的 NetEMU 工程
3. 执行：
   ```bash
   flutter pub get
   flutter analyze
   flutter build apk --release --target-platform android-arm64
   ```

## 权限说明

- VPN：系统授权弹窗
- 悬浮窗：需授予「显示在其他应用上层」
- Root / Shizuku：按设备能力自动或手动选择

## 注意

- Root 模式主要影响上行（egress）；完整上下行推荐 VPN 模式
- Shizuku 当前为安装检测 + shell 回退，完整 API 需自行接入官方库
- 参数热更新：运行中修改延迟/丢包/带宽会立即生效（VPN 与 Root 均支持）
