# NetEMU 补丁 v3

在 v2 基础上：配置只读/自由调节、参数输入框+滑条、备份恢复、Shizuku/ADB/测速说明。

覆盖 `lib/` 与必要的 android 文件后：

```bash
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```
