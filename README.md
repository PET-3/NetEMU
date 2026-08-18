# NetEmu

Android 弱网模拟工具（Flutter + 原生 VPN / Root tc）。

项目地址：https://github.com/PET-3/NetEMU

## 功能概览

- **多后端**：VPN（无 Root）、Root（tc）、ADB 命令导出
- **参数**：延迟、抖动、带宽、随机丢包、连续丢包（包数 / 时间）
- **协议过滤**：全部 / TCP / UDP（VPN 路径）
- **配置管理**：新建、修改（不新增同名）、删除、导入导出
- **测试模式**：独立可调参数，可保存为配置
- **悬浮窗**：控制（模式 / 配置 / 快捷延迟）、信息（速度与丢包）
- **常驻通知**：运行状态、速度摘要、开始 / 暂停
- **界面**：Material 3，支持系统深浅色

## 底部导航

| 页 | 说明 |
|----|------|
| 首页 | 启停、选测试/配置、参数图、流量与丢包统计、浮窗与通知开关 |
| 测试 | 仅在首页选择「测试」后出现；可调参数并保存到配置 |
| 配置 | 管理已有配置 |
| 设置 | 后端锁定、接口、日志、备份、关于 |

## 构建

```bash
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

## 权限说明

- **VPN**：系统授权弹窗
- **悬浮窗**：显示在其他应用上层
- **Root / ADB**：按设备能力在设置中锁定后端

## 关于

- 项目：https://github.com/PET-3/NetEMU
- 作者邮箱：yyx3307022@gmail.com
- 微信：yyx307022

## 许可

以仓库内 LICENSE 为准。
