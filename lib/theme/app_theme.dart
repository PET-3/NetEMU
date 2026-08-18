import 'package:flutter/material.dart';

enum UiStyle { materialYou, salt }

class AppTheme {
  static ThemeData light(UiStyle style) {
    final seed = style == UiStyle.salt
        ? const Color(0xFF1A73E8)
        : const Color(0xFF1565C0);
    return _build(
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      style,
    );
  }

  static ThemeData dark(UiStyle style) {
    final seed = style == UiStyle.salt
        ? const Color(0xFF8AB4F8)
        : const Color(0xFF90CAF9);
    return _build(
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      style,
    );
  }

  static ThemeData _build(ColorScheme cs, UiStyle style) {
    final isSalt = style == UiStyle.salt;
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: isSalt ? 0 : 0.5,
        margin: EdgeInsets.symmetric(
          horizontal: isSalt ? 12 : 0,
          vertical: isSalt ? 4 : 6,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isSalt ? 10 : 16),
          side: isSalt
              ? BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))
              : BorderSide.none,
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: isSalt,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isSalt ? 12 : 16,
          vertical: isSalt ? 0 : 4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: isSalt ? 64 : 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isSalt ? 8 : 16),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: isSalt,
        elevation: 0,
        scrolledUnderElevation: isSalt ? 0 : 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

class ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ScaleTap({super.key, required this.child, this.onTap});

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.96,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.reverse(),
      onTapUp: (_) {
        _c.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _c.forward(),
      child: ScaleTransition(scale: _c, child: widget.child),
    );
  }
}
