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
          home: const MainShell(),
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
