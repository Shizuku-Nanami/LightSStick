import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ensemble_icons/remixicon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ble_service.dart';
import 'services/color_api_service.dart';
import 'screens/device_screen.dart';
import 'screens/color_library_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HikariStickApp());
}

class HikariStickApp extends StatefulWidget {
  const HikariStickApp({super.key});

  @override
  HikariStickAppState createState() => HikariStickAppState();

  static HikariStickAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<HikariStickAppState>();
}

class HikariStickAppState extends State<HikariStickApp> {
  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF6C63FF);

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  HikariStickAppState();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    // 主题模式
    final modeIndex = prefs.getInt(_themeModeKey);
    if (modeIndex != null && modeIndex >= 0 && modeIndex <= 2) {
      _themeMode = ThemeMode.values[modeIndex];
    }
    // 主题色
    final colorValue = prefs.getInt(_seedColorKey);
    if (colorValue != null) {
      _seedColor = Color(colorValue);
    }
    setState(() {});
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<void> setSeedColor(Color color) async {
    setState(() => _seedColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => ColorApiService()),
      ],
      child: MaterialApp(
        title: 'HikariStick',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        home: const MainNavigation(),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _isMultiSelectActive = false;
  Widget? _multiSelectBottomBar;
  DateTime? _lastBackPress;

  void _onMultiSelectChanged(bool active, {Widget? bottomBar}) {
    setState(() {
      _isMultiSelectActive = active;
      _multiSelectBottomBar = bottomBar;
    });
  }

  Future<bool> _onWillPop() async {
    if (_isMultiSelectActive) {
      colorLibraryKey.currentState?.exitMultiSelect();
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('再次返回退出应用'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DeviceScreen(),
      ColorLibraryScreen(
        key: colorLibraryKey,
        onMultiSelectChanged: _onMultiSelectChanged,
      ),
      const SettingsScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onWillPop().then((canPop) {
            if (canPop) SystemNavigator.pop();
          });
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            final offsetAnim =
                Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
            return ClipRect(
              child: SlideTransition(position: offsetAnim, child: child),
            );
          },
          child: _isMultiSelectActive && _multiSelectBottomBar != null
              ? KeyedSubtree(
                  key: const ValueKey('multiselect_bar'),
                  child: _multiSelectBottomBar!,
                )
              : NavigationBar(
                  key: const ValueKey('nav_bar'),
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    setState(() => _currentIndex = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Remix.flashlight_line),
                      selectedIcon: Icon(Remix.flashlight_fill),
                      label: '设备',
                    ),
                    NavigationDestination(
                      icon: Icon(Remix.palette_line),
                      selectedIcon: Icon(Remix.palette_fill),
                      label: '颜色库',
                    ),
                    NavigationDestination(
                      icon: Icon(Remix.settings_3_line),
                      selectedIcon: Icon(Remix.settings_3_fill),
                      label: '设置',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
