import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class AppPrefs {
  static const _kLang = 'netemu_lang_en';
  static const _kUi = 'netemu_ui_style';

  static Future<bool> isEnglish() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kLang) ?? false;
  }

  static Future<void> setEnglish(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLang, v);
  }

  static Future<UiStyle> uiStyle() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kUi);
    if (s == 'salt') return UiStyle.salt;
    return UiStyle.materialYou;
  }

  static Future<void> setUiStyle(UiStyle style) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kUi, style == UiStyle.salt ? 'salt' : 'materialYou');
  }
}
