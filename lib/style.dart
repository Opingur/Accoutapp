import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:piggybank/services/locale-service.dart';
import 'package:piggybank/settings/constants/preferences-keys.dart';
import 'package:piggybank/settings/preferences-utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';

import 'helpers/records-utility-functions.dart';

const String FontNameDefault = 'Montserrat';

/// Returns the CJK font fallback matching the given locale, so that localized
/// glyph variants (Japanese vs Simplified Chinese) are rendered with the
/// appropriate font. Returns null when the locale needs no special CJK font.
List<String>? getFontFamilyFallbackForLocale(Locale locale) {
  switch (locale.languageCode) {
    case 'ja':
      return ['Noto Sans JP'];
    case 'zh':
      return ['Noto Sans SC'];
    default:
      return null;
  }
}

class MaterialThemeInstance {
  static ThemeData? lightTheme;
  static ThemeData? darkTheme;
  static ThemeData? currentTheme;
  static ThemeMode? themeMode;
  static Color defaultSeedColor = Color.fromARGB(255, 255, 214, 91);

  static getDefaultColorScheme(Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: defaultSeedColor,
      brightness: brightness,
    );
  }

  static Future<ColorScheme> getColorScheme(Brightness brightness) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? dynamicColorScheme = PreferencesUtils.getOrDefault<int>(
      prefs,
      PreferencesKeys.themeColor,
    );

    switch (dynamicColorScheme) {
      case 1:
        {
          log("Using system colors");
          await SystemTheme.accentColor.load();
          SystemTheme.fallbackColor = defaultSeedColor;
          final accentColor = SystemTheme.accentColor.accent;
          if (accentColor == defaultSeedColor) {
            log("Failed to retrieve system color, using default instead");
          }
          return ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: brightness,
          );
        }

      case 2:
        {
          log("Using dynamic colors");
          ImageProvider backgroundImage = getBackgroundImage(
            DateTime.now().month,
          );
          try {
            ColorScheme colorScheme = await ColorScheme.fromImageProvider(
              provider: backgroundImage,
              brightness: brightness,
            );
            return colorScheme;
          } catch (e) {
            log("Failed to derive colors from the banner image: $e");
            return getDefaultColorScheme(brightness);
          }
        }

      default:
        {
          return getDefaultColorScheme(brightness);
        }
    }
  }

  static Future<ThemeData> getMaterialThemeData(Brightness brightness) async {
    final generatedScheme = await getColorScheme(brightness);
    final isDark = brightness == Brightness.dark;

    // Keep the familiar yellow accent, but use deliberately calm surfaces in
    // dark mode.  This lets all Material controls share one semantic palette
    // instead of each page choosing its own near-black or white background.
    final colorScheme = generatedScheme.copyWith(
      primary: isDark ? const Color(0xFFFFCC4D) : const Color(0xFFFFD21F),
      onPrimary: const Color(0xFF252525),
      secondary: isDark ? const Color(0xFFFFCC4D) : const Color(0xFF765800),
      surface: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
      onSurface: isDark ? const Color(0xFFF2F2F2) : const Color(0xFF282828),
      surfaceContainer: isDark
          ? const Color(0xFF272727)
          : const Color(0xFFF3F3F3),
      surfaceContainerHighest: isDark
          ? const Color(0xFF333333)
          : const Color(0xFFE8E8E8),
      outline: isDark ? const Color(0xFF4A4A4A) : const Color(0xFFDDDDDD),
      outlineVariant: isDark
          ? const Color(0xFF333333)
          : const Color(0xFFE8E8E8),
    );
    final locale = LocaleService.resolveLanguageLocale();
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamilyFallback: getFontFamilyFallbackForLocale(locale),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.5,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: colorScheme.surface,
                systemNavigationBarColor: colorScheme.surface,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: colorScheme.surface,
                systemNavigationBarColor: colorScheme.surface,
              ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF303030)
            : const Color(0xFF303030),
        contentTextStyle: const TextStyle(color: Color(0xFFF2F2F2)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF272727) : const Color(0xFFF7F7F7),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static Future<ThemeMode> getThemeMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? themeModeIndex = PreferencesUtils.getOrDefault<int>(
      prefs,
      PreferencesKeys.themeMode,
    );
    themeMode = ThemeMode.values[themeModeIndex!];
    return themeMode!;
  }

  static Future<ThemeData> getLightTheme() async {
    if (lightTheme == null) {
      lightTheme = await getMaterialThemeData(Brightness.light);
    }
    return lightTheme!;
  }

  static Future<ThemeData> getDarkTheme() async {
    if (darkTheme == null) {
      darkTheme = await getMaterialThemeData(Brightness.dark);
    }
    return darkTheme!;
  }
}
