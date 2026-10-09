import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybank/settings/constants/preferences-keys.dart';
import 'package:piggybank/services/service-config.dart';
import 'package:piggybank/style.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> setTestPreferences(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues({
    PreferencesKeys.languageLocale: 'system',
    ...values,
  });
  ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MaterialThemeInstance.lightTheme = null;
    MaterialThemeInstance.darkTheme = null;
    MaterialThemeInstance.themeMode = null;
  });

  tearDown(() {
    MaterialThemeInstance.lightTheme = null;
    MaterialThemeInstance.darkTheme = null;
    MaterialThemeInstance.themeMode = null;
  });

  test('theme mode defaults to following the system', () async {
    await setTestPreferences({});

    expect(await MaterialThemeInstance.getThemeMode(), ThemeMode.system);
  });

  test('theme mode persists the explicit light and dark selections', () async {
    await setTestPreferences({PreferencesKeys.themeMode: ThemeMode.dark.index});
    expect(await MaterialThemeInstance.getThemeMode(), ThemeMode.dark);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(PreferencesKeys.themeMode, ThemeMode.light.index);
    MaterialThemeInstance.themeMode = null;

    expect(await MaterialThemeInstance.getThemeMode(), ThemeMode.light);
  });

  test(
    'dark theme uses semantic dark surfaces and readable foregrounds',
    () async {
      await setTestPreferences({});

      final darkTheme = await MaterialThemeInstance.getDarkTheme();

      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF1E1E1E));
      expect(darkTheme.colorScheme.onSurface, const Color(0xFFF2F2F2));
      expect(darkTheme.colorScheme.outlineVariant, const Color(0xFF333333));
    },
  );

  testWidgets('system theme mode follows the platform brightness', (
    tester,
  ) async {
    await setTestPreferences({});
    final lightTheme = await MaterialThemeInstance.getLightTheme();
    final darkTheme = await MaterialThemeInstance.getDarkTheme();

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) => Text(Theme.of(context).brightness.name),
        ),
      ),
    );

    expect(find.text('dark'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
  });
}
