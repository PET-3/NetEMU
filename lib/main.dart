import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/network_controller.dart';
import 'services/app_prefs.dart';
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

class NetEmuApp extends StatefulWidget {
  const NetEmuApp({super.key});

  @override
  State<NetEmuApp> createState() => _NetEmuAppState();
}

class _NetEmuAppState extends State<NetEmuApp> {
  bool _en = false;
  UiStyle _ui = UiStyle.materialYou;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final en = await AppPrefs.isEnglish();
    final ui = await AppPrefs.uiStyle();
    if (mounted) {
      setState(() {
        _en = en;
        _ui = ui;
        _ready = true;
      });
    }
  }

  void updateLocale(bool en) async {
    await AppPrefs.setEnglish(en);
    setState(() => _en = en);
  }

  void updateUiStyle(UiStyle style) async {
    await AppPrefs.setUiStyle(style);
    setState(() => _ui = style);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NetworkController()..initialize()),
        Provider<S>.value(value: S.of(_en)),
        Provider<AppShellAccess>.value(
          value: AppShellAccess(
            setEnglish: updateLocale,
            setUiStyle: updateUiStyle,
            isEnglish: _en,
            uiStyle: _ui,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'NetEmu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(_ui),
        darkTheme: AppTheme.dark(_ui),
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
    final s = context.watch<S>();
    final showTest = ctrl.isTestMode;

    final pages = <Widget>[
      const HomeScreen(),
      if (showTest) const TestScreen(),
      const ProfilesScreen(),
      const SettingsScreen(),
    ];

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: s.home,
      ),
      if (showTest)
        NavigationDestination(
          icon: const Icon(Icons.science_outlined),
          selectedIcon: const Icon(Icons.science),
          label: s.test,
        ),
      NavigationDestination(
        icon: const Icon(Icons.folder_outlined),
        selectedIcon: const Icon(Icons.folder),
        label: s.profiles,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: s.settings,
      ),
    ];

    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey('${showTest}_$safeIndex'),
          child: pages[safeIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}


/// 设置页访问语言/主题切换
class AppShellAccess {
  final void Function(bool en) setEnglish;
  final void Function(UiStyle style) setUiStyle;
  final bool isEnglish;
  final UiStyle uiStyle;
  AppShellAccess({
    required this.setEnglish,
    required this.setUiStyle,
    required this.isEnglish,
    required this.uiStyle,
  });

  static AppShellAccess? of(BuildContext context) {
    try {
      return Provider.of<AppShellAccess>(context, listen: true);
    } catch (_) {
      return null;
    }
  }
}
