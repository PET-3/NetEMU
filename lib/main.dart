import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/network_controller.dart';
import 'screens/home_screen.dart';
import 'screens/test_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NetEmuApp());
}

class NetEmuApp extends StatelessWidget {
  const NetEmuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkController()..initialize(),
      child: MaterialApp(
        title: 'NetEmu',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF90CAF9),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    MainShellSwitch.switchTab = (i) {
      if (mounted) setState(() => _index = i);
    };
  }

  @override
  void dispose() {
    MainShellSwitch.switchTab = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    // 测试页：仅在「测试模式」或未选配置时显示入口；选中配置后底部不显示测试
    final showTest = ctrl.isTestMode; // 仅首页选择「测试」后显示测试页

    final pages = <Widget>[
      const HomeScreen(),
      if (showTest) const TestScreen(),
      const ProfilesScreen(),
      const SettingsScreen(),
    ];

    // 映射：首页 0；若有测试则 1 为测试，否则 1 为配置…
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '首页',
      ),
      if (showTest)
        const NavigationDestination(
          icon: Icon(Icons.science_outlined),
          selectedIcon: Icon(Icons.science),
          label: '测试',
        ),
      const NavigationDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder),
        label: '配置',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];

    // 修正 index 越界（从显示测试切到不显示时）
    if (_index >= pages.length) {
      _index = 0;
    }
    // 若当前在测试页但测试被隐藏，回到首页
    if (!showTest && _index == 1 && pages.length == 3) {
      // 当 showTest 为 false 时 pages = [home, profiles, settings]
      // 若之前 index 指向旧的测试，需钳制
    }
    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
