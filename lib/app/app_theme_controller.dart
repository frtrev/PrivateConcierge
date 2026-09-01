import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController(this._preferences)
    : _mode = _preferences.getBool(_darkModeKey) ?? true
          ? ThemeMode.dark
          : ThemeMode.light;

  static const _darkModeKey = 'appearance_dark_mode';
  final SharedPreferences _preferences;
  ThemeMode _mode;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> setDark(bool value) async {
    final next = value ? ThemeMode.dark : ThemeMode.light;
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
    await _preferences.setBool(_darkModeKey, value);
  }
}

class PrivateConciergeThemes {
  static const gold = Color(0xffd7ad55);
  static const paleGold = Color(0xffffdda0);

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: gold,
      onPrimary: Color(0xff211700),
      secondary: paleGold,
      onSecondary: Color(0xff241900),
      surface: Color(0xff191a1d),
      onSurface: Color(0xfff2eee5),
      error: Color(0xffffb4ab),
      onError: Color(0xff690005),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xff101114),
      cardTheme: const CardThemeData(
        color: Color(0xff1b1c20),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Color(0xff403721)),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      dividerColor: const Color(0xff3a3428),
    );
  }

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: Color(0xff795900),
      onPrimary: Colors.white,
      secondary: Color(0xff6c5630),
      onSecondary: Colors.white,
      surface: Color(0xfffffbf3),
      onSurface: Color(0xff242018),
      error: Color(0xffba1a1a),
      onError: Colors.white,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xfff3eee3),
      cardTheme: const CardThemeData(
        color: Color(0xfffffbf3),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Color(0xffd9c9a6)),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      dividerColor: const Color(0xffd8ccb5),
    );
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4,
      ),
      systemOverlayStyle: scheme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        side: BorderSide(color: scheme.primary.withValues(alpha: .65)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.primary.withValues(alpha: .45)),
      selectedColor: scheme.primaryContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}
