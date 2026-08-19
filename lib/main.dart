import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/network_controller.dart';
import 'theme/app_theme.dart';
import 'l10n/app_strings.dart';
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
      child: Provider<S>.value(
        value: const S(false),
        child: MaterialApp(
          title: 'NetEmu',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          home: const DisclaimerGate(child: MainShell()),
        ),
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
  late PageController _pageController;
  int _index = 0;
  /// When true, horizontal page swipe is disabled (param pages with horizontal sliders).
  bool _blockSwipe = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    MainShellSwitch.switchTab = (i) {
      if (!mounted) return;
      final ctrl = context.read<NetworkController>();
      final showAdjust = ctrl.runSource != RunSource.none;
      final pagesLen = showAdjust ? 4 : 3;
      final target = i.clamp(0, pagesLen - 1);
      setState(() => _index = target);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    };
    MainShellSwitch.setBlockSwipe = (v) {
      if (mounted) setState(() => _blockSwipe = v);
    };
  }

  @override
  void dispose() {
    MainShellSwitch.switchTab = null;
    MainShellSwitch.setBlockSwipe = null;
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final showAdjust = ctrl.runSource != RunSource.none;

    // Map visual index when adjust tab appears/disappears
    final pages = <Widget>[
      const HomeScreen(),
      if (showAdjust) const TestScreen(),
      const ProfilesScreen(),
      const SettingsScreen(),
    ];

    final adjustLabel = ctrl.runSource == RunSource.test
        ? '临时'
        : (ctrl.selectedProfileName ?? '调节');

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '首页',
      ),
      if (showAdjust)
        NavigationDestination(
          icon: const Icon(Icons.tune_outlined),
          selectedIcon: const Icon(Icons.tune),
          label: adjustLabel.length > 4
              ? '${adjustLabel.substring(0, 4)}…'
              : adjustLabel,
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

    final safeIndex = _index.clamp(0, pages.length - 1);
    if (safeIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = safeIndex);
      });
    }

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: _blockSwipe
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          _pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        destinations: destinations,
      ),
    );
  }
}

/// Global tab switch helpers used by Home / Profiles.
class MainShellSwitch {
  static void Function(int index)? switchTab;
  static void Function(bool block)? setBlockSwipe;

  static void toHome() => switchTab?.call(0);

  static void toAdjust() => switchTab?.call(1);

  static void toProfiles({bool showAdjust = true}) =>
      switchTab?.call(showAdjust ? 2 : 1);

  static void toSettings({bool showAdjust = true}) =>
      switchTab?.call(showAdjust ? 3 : 2);

  /// @deprecated use toAdjust
  static void toTest(BuildContext context) => toAdjust();
}

/// 首次启动免责声明
class DisclaimerGate extends StatefulWidget {
  final Widget child;
  const DisclaimerGate({super.key, required this.child});

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    if (ctrl.initialized && !ctrl.disclaimerAccepted && !_shown) {
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(context, ctrl));
    }
    return widget.child;
  }

  Future<void> _show(BuildContext context, NetworkController ctrl) async {
    const body = '''本应用（NetEmu）用于在受控环境中模拟弱网条件，辅助开发与测试。

一、合法用途
• 仅可在您拥有管理权的设备上，对自有或已获授权的应用/服务做网络条件测试。
• 不得用于干扰公共网络、攻击他人服务、规避安全或风控、或任何违法违规用途。

二、风险提示
• VPN / Root / Shizuku 模式会改变本机网络路径或队列，可能导致部分应用异常、耗电增加或连接中断。
• 错误参数（极高延迟、高丢包、极低带宽）可能导致系统卡顿、无法上网，请预留恢复手段。
• Root 与特权操作存在设备变砖、保修失效等风险，请自行评估。

三、隐私与数据
• 本应用不要求账号登录；配置与日志默认仅存于本机。
• 分享/导出配置由您主动触发，请勿泄露含敏感信息的内容。

四、无担保
• 软件按「现状」提供，作者不对测试结果准确性、业务损失或数据损坏承担责任。
• 第三方应用在弱网下的行为由其自身决定，与本工具无必然因果关系。

五、接受
点击「同意并继续」即表示您已阅读并接受上述条款；若不同意，请卸载并停止使用。''';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('使用前须知与免责声明'),
        content: const SingleChildScrollView(child: Text(body)),
        actions: [
          FilledButton(
            onPressed: () async {
              await ctrl.acceptDisclaimer();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
  }
}
