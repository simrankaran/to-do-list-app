// Named constructor parameters can't be private, so the fields are set in
// the initializer list instead of with `this._field`.
// ignore_for_file: prefer_initializing_formals

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A colour theme the user can pick in Settings.
class AppTheme {
  const AppTheme(this.key, this.name, this.seed, this.accent);

  final String key;
  final String name;

  /// The colour the whole palette is generated from.
  final Color seed;

  /// A second colour for gradients.
  final Color accent;
}

const appThemes = [
  AppTheme('indigo', 'Indigo', Color(0xFF5B5BD6), Color(0xFF9B4FD6)),
  AppTheme('ocean', 'Ocean', Color(0xFF0284C7), Color(0xFF06B6D4)),
  AppTheme('sunset', 'Sunset', Color(0xFFEA580C), Color(0xFFDB2777)),
  AppTheme('forest', 'Forest', Color(0xFF15803D), Color(0xFF65A30D)),
  AppTheme('rose', 'Rose', Color(0xFFE11D48), Color(0xFFF472B6)),
  AppTheme('grape', 'Grape', Color(0xFF7C3AED), Color(0xFFC026D3)),
  AppTheme('midnight', 'Midnight', Color(0xFF334155), Color(0xFF6366F1)),
];

AppTheme themeByKey(String? key) =>
    appThemes.where((t) => t.key == key).firstOrNull ?? appThemes.first;

/// Appearance and feedback choices, saved on this device.
class AppSettings extends ChangeNotifier {
  AppSettings({
    AppTheme? theme,
    ThemeMode themeMode = ThemeMode.system,
    bool sounds = true,
    bool celebrations = true,
    SharedPreferences? prefs,
  }) : _theme = theme ?? appThemes.first,
       _themeMode = themeMode,
       _sounds = sounds,
       _celebrations = celebrations,
       _prefs = prefs;

  /// Loads the saved choices. Falls back to defaults if storage fails.
  static Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppSettings(
        theme: themeByKey(prefs.getString(_themeKey)),
        themeMode:
            ThemeMode.values
                .where((m) => m.name == prefs.getString(_modeKey))
                .firstOrNull ??
            ThemeMode.system,
        sounds: prefs.getBool(_soundsKey) ?? true,
        celebrations: prefs.getBool(_celebrationsKey) ?? true,
        prefs: prefs,
      );
    } catch (e) {
      debugPrint('Could not load settings: $e');
      return AppSettings();
    }
  }

  static const _themeKey = 'theme';
  static const _modeKey = 'theme_mode';
  static const _soundsKey = 'sounds';
  static const _celebrationsKey = 'celebrations';

  final SharedPreferences? _prefs;
  AppTheme _theme;
  ThemeMode _themeMode;
  bool _sounds;
  bool _celebrations;

  AppTheme get theme => _theme;
  set theme(AppTheme value) {
    _theme = value;
    _prefs?.setString(_themeKey, value.key);
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode value) {
    _themeMode = value;
    _prefs?.setString(_modeKey, value.name);
    notifyListeners();
  }

  /// Play sounds when finishing tasks.
  bool get sounds => _sounds;
  set sounds(bool value) {
    _sounds = value;
    _prefs?.setBool(_soundsKey, value);
    notifyListeners();
  }

  /// Show confetti when finishing tasks.
  bool get celebrations => _celebrations;
  set celebrations(bool value) {
    _celebrations = value;
    _prefs?.setBool(_celebrationsKey, value);
    notifyListeners();
  }
}
