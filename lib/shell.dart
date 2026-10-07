import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:piggybank/comms/announcement-dialog.dart';
import 'package:piggybank/helpers/amount-input-utils.dart';
import 'package:piggybank/i18n.dart';
import 'package:piggybank/records/records-page.dart';
import 'package:piggybank/records/components/home_compact_metrics.dart';
import 'package:piggybank/settings/constants/preferences-keys.dart';
import 'package:piggybank/settings/preferences-utils.dart';
import 'package:piggybank/settings/settings-page.dart';
import 'package:piggybank/style.dart';
import 'package:piggybank/budgets/budgets-page.dart';
import 'package:piggybank/categories/categories-tab-page-view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'categories/categories-tab-page-edit.dart';
import 'wallets/wallets-tab-page.dart';

class Shell extends StatefulWidget {
  @override
  ShellState createState() => ShellState();
}

class ShellState extends State<Shell> {
  static const MethodChannel _widgetActionChannel = MethodChannel(
    'oinkoin/widget_action',
  );

  /// Singleton-like access for external refresh calls (e.g., quick actions).
  static ShellState? _instance;

  /// Returns the current ShellState instance, if mounted.
  static ShellState? get instance => _instance;

  int _currentIndex = 0;
  final LocalAuthentication auth = LocalAuthentication();
  Future<bool>? authFuture = null;

  /// Ensures the startup announcement dialog is checked only once per app run,
  /// after authentication has succeeded and the main UI is on screen.
  bool _announcementDialogChecked = false;

  final GlobalKey<TabRecordsState> _tabRecordsKey = GlobalKey();
  final GlobalKey<TabCategoriesState> _tabCategoriesKey = GlobalKey();
  final GlobalKey<WalletsTabPageState> _tabWalletsKey = GlobalKey();
  final GlobalKey<BudgetsPageState> _tabBudgetsKey = GlobalKey();

  final GlobalKey<NavigatorState> _homeNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _categoriesNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _walletsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _budgetsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _settingsNavigatorKey =
      GlobalKey<NavigatorState>();

  Future<bool> _authenticate() async {
    // Skip biometric authentication on desktop platforms
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }

    var pref = await SharedPreferences.getInstance();
    var enableAppLock = PreferencesUtils.getOrDefault<bool>(
      pref,
      PreferencesKeys.enableAppLock,
    )!;
    if (enableAppLock) {
      try {
        final authResult = await auth.authenticate(
          localizedReason: 'Authenticate to access the app'.i18n,
          persistAcrossBackgrounding: true,
        );
        return authResult;
      } on LocalAuthException catch (e) {
        print('Authentication error: ${e.code}');
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    authFuture = _authenticate();
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  /// Shows the pending startup announcement dialog (if any) once the main UI
  /// has been laid out. Runs a single time per app launch and only after the
  /// user has passed authentication.
  void _scheduleAnnouncementDialog() {
    if (_announcementDialogChecked) return;
    _announcementDialogChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowAnnouncementDialog(context);
    });
  }

  /// Handles home screen widget quick-add taps (add expense/income). The
  /// action arrives either pushed while running or stashed for cold starts;
  /// both run only after authentication, like the announcement dialog.
  void _handleWidgetQuickAction() {
    _widgetActionChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAddFlow') {
        _openAddFlow(call.arguments as String?);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      String? action;
      try {
        action = await _widgetActionChannel.invokeMethod<String>(
          'getInitialAction',
        );
      } catch (_) {
        return;
      }
      if (action != null && mounted) _openAddFlow(action);
    });
  }

  /// Opens the add-record flow on the expense (0) or income (1) tab.
  void _openAddFlow(String? action) {
    final tabIndex = action == 'add_income' ? 1 : 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryTabPageView(
          goToEditMovementPage: true,
          initialTabIndex: tabIndex,
        ),
      ),
    );
  }

  /// Refreshes the home tab's records list (e.g., after a quick action added a record).
  void refreshHomeTab() {
    _tabRecordsKey.currentState?.onTabChange();
  }

  Future<void> _showRecords() async {
    if (_currentIndex != 0) setState(() => _currentIndex = 0);
    await _tabRecordsKey.currentState?.onTabChange();
  }

  void _openPrimaryAddFlow() {
    if (_currentIndex != 0) setState(() => _currentIndex = 0);
    _tabRecordsKey.currentState?.openAddRecord();
  }

  void _openStatistics() {
    if (_currentIndex != 0) setState(() => _currentIndex = 0);
    _tabRecordsKey.currentState?.openStatistics();
  }

  void _showSettings() {
    if (_currentIndex != 4) setState(() => _currentIndex = 4);
  }

  void _showDiscoverPlaceholder() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('发现功能即将推出')));
  }

  @override
  Widget build(BuildContext context) {
    print("Shell build called");
    return FutureBuilder<bool>(
      future: authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a loading spinner while authenticating
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError || !(snapshot.data ?? false)) {
          // Show lock icon with a retry button if authentication failed
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    "Authentication Failed",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Trigger a new authentication attempt
                        authFuture = _authenticate();
                      });
                    },
                    child: Text("Retry"),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Authentication successful, build the main UI
          _scheduleAnnouncementDialog();
          _handleWidgetQuickAction();
          return _buildMainUI(context);
        }
      },
    );
  }

  Widget _buildMainUI(BuildContext context) {
    ThemeData themeData = Theme.of(context);
    MaterialThemeInstance.currentTheme = themeData;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }

        // Get the current tab's navigator
        NavigatorState? currentNavigator;
        switch (_currentIndex) {
          case 0:
            currentNavigator = _homeNavigatorKey.currentState;
            break;
          case 1:
            currentNavigator = _walletsNavigatorKey.currentState;
            break;
          case 2:
            currentNavigator = _categoriesNavigatorKey.currentState;
            break;
          case 3:
            currentNavigator = _budgetsNavigatorKey.currentState;
            break;
          case 4:
            currentNavigator = _settingsNavigatorKey.currentState;
            break;
        }

        // Check if the current tab's navigator can pop.
        // Use maybePop so inner PopScopes (e.g., in-app keyboard) can intercept first.
        if (currentNavigator != null && currentNavigator.canPop()) {
          await currentNavigator.maybePop();
          return;
        }

        // At the root of the current tab's navigator.
        // Use maybePop to respect inner PopScopes (e.g., select mode in records).
        if (currentNavigator != null) {
          final bool handled = await currentNavigator.maybePop();
          if (handled) return;
        }

        if (_currentIndex != 0) {
          // If we're at the root of a non-Home tab, navigate to Home
          setState(() {
            _currentIndex = 0;
          });
        } else {
          // We're at the root of Home tab - exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          // In landscape the system navigation bar (3-button mode) sits on the
          // side of the screen. Pad horizontally so body content never extends
          // behind it. The top inset is handled by each page's app bar and the
          // bottom inset by the NavigationBar below.
          top: false,
          bottom: false,
          child: Stack(
            children: <Widget>[
              Offstage(
                offstage: _currentIndex != 0,
                child: TickerMode(
                  enabled: _currentIndex == 0,
                  child: Navigator(
                    key: _homeNavigatorKey,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(
                        builder: (_) => TabRecords(key: _tabRecordsKey),
                      );
                    },
                  ),
                ),
              ),
              Offstage(
                offstage: _currentIndex != 1,
                child: TickerMode(
                  enabled: _currentIndex == 1,
                  child: Navigator(
                    key: _walletsNavigatorKey,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(
                        builder: (_) => WalletsTabPage(key: _tabWalletsKey),
                      );
                    },
                  ),
                ),
              ),
              Offstage(
                offstage: _currentIndex != 2,
                child: TickerMode(
                  enabled: _currentIndex == 2,
                  child: Navigator(
                    key: _categoriesNavigatorKey,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(
                        builder: (_) => TabCategories(key: _tabCategoriesKey),
                      );
                    },
                  ),
                ),
              ),
              Offstage(
                offstage: _currentIndex != 3,
                child: TickerMode(
                  enabled: _currentIndex == 3,
                  child: Navigator(
                    key: _budgetsNavigatorKey,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(
                        builder: (_) => BudgetsPage(key: _tabBudgetsKey),
                      );
                    },
                  ),
                ),
              ),
              Offstage(
                offstage: _currentIndex != 4,
                child: TickerMode(
                  enabled: _currentIndex == 4,
                  child: Navigator(
                    key: _settingsNavigatorKey,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(builder: (_) => TabSettings());
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: inAppKeyboardOpen,
          builder: (context, isOpen, _) => AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: isOpen
                ? SizedBox(height: MediaQuery.paddingOf(context).bottom)
                : _HomeBottomBar(
                    selectedIndex: _currentIndex,
                    onRecordsPressed: _showRecords,
                    onAddPressed: _openPrimaryAddFlow,
                    onStatisticsPressed: _openStatistics,
                    onDiscoverPressed: _showDiscoverPlaceholder,
                    onProfilePressed: _showSettings,
                  ),
          ),
        ),
      ),
    );
  }
}

class _HomeBottomBar extends StatelessWidget {
  const _HomeBottomBar({
    required this.selectedIndex,
    required this.onRecordsPressed,
    required this.onAddPressed,
    required this.onStatisticsPressed,
    required this.onDiscoverPressed,
    required this.onProfilePressed,
  });

  final int selectedIndex;
  final VoidCallback onRecordsPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onStatisticsPressed;
  final VoidCallback onDiscoverPressed;
  final VoidCallback onProfilePressed;

  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFFFD21F);
    const ink = Color(0xFF242424);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      elevation: 0,
      child: SizedBox(
        height: HomeCompactMetrics.bottomBarHeight + bottomInset,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFEFEFEF))),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 0 + bottomInset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomAction(
                  icon: Icons.receipt_long_outlined,
                  label: '明细',
                  selected: selectedIndex == 0,
                  onTap: onRecordsPressed,
                ),
                _BottomAction(
                  icon: Icons.query_stats_outlined,
                  label: '图表',
                  onTap: onStatisticsPressed,
                ),
                Semantics(
                  identifier: 'add-record',
                  button: true,
                  label: '记账',
                  child: _PrimaryBottomAction(
                    color: yellow,
                    ink: ink,
                    onTap: onAddPressed,
                  ),
                ),
                _BottomAction(
                  icon: Icons.explore_outlined,
                  label: '发现',
                  onTap: onDiscoverPressed,
                ),
                _BottomAction(
                  icon: Icons.person_outline,
                  label: '我的',
                  selected: selectedIndex == 4,
                  onTap: onProfilePressed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryBottomAction extends StatelessWidget {
  const _PrimaryBottomAction({
    required this.color,
    required this.ink,
    required this.onTap,
  });

  final Color color;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    height: 60,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          top: -17,
          child: InkResponse(
            onTap: onTap,
            radius: 34,
            child: Container(
              width: HomeCompactMetrics.primaryActionSize,
              height: HomeCompactMetrics.primaryActionSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.add_rounded,
                size: HomeCompactMetrics.primaryActionIcon,
                color: ink,
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: 0,
          child: Text(
            '记账',
            style: TextStyle(
              color: Color(0xFF242424),
              fontSize: HomeCompactMetrics.bottomLabel,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF242424);
    final color = selected ? ink : const Color(0xFF8C8C8C);
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: HomeCompactMetrics.bottomIcon),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: HomeCompactMetrics.bottomLabel,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
