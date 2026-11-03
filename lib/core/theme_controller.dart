// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 昼夜色彩主题控制器 (Theme Controller)
// 文件职责: 提供“跟随系统”、“白天高光防直射”与“暗夜防眩目纯黑”三种视觉模式管理
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system, // 跟随系统
  light,  // 白天高光模式 (沙漠白底)
  dark,   // 暗夜防眩模式 (戈壁纯黑)
}

/// 全局昼夜高反差色彩控制器 (单例模式)
class ThemeController with ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  factory ThemeController() => instance;
  ThemeController._internal() {
    _loadSavedTheme();
  }

  static const String _prefKey = 'app_theme_mode';
  AppThemeMode _mode = AppThemeMode.dark; // 默认户外纯黑防眩

  AppThemeMode get mode => _mode;

  ThemeMode get flutterThemeMode {
    switch (_mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  /// 判断当前上下文是否为暗黑防眩模式
  bool isDarkMode(BuildContext context) {
    switch (_mode) {
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.light:
        return false;
      case AppThemeMode.system:
        return Theme.of(context).brightness == Brightness.dark;
    }
  }

  /// 顺序轮转切换下一个主题
  void toggleNext() {
    switch (_mode) {
      case AppThemeMode.system:
        _mode = AppThemeMode.light;
        break;
      case AppThemeMode.light:
        _mode = AppThemeMode.dark;
        break;
      case AppThemeMode.dark:
        _mode = AppThemeMode.system;
        break;
    }
    notifyListeners();
  }

  String get modeName {
    switch (_mode) {
      case AppThemeMode.system:
        return '跟随系统';
      case AppThemeMode.light:
        return '白天高光 (沙漠防直射)';
      case AppThemeMode.dark:
        return '暗夜防眩 (戈壁黑底)';
    }
  }

  IconData get modeIcon {
    switch (_mode) {
      case AppThemeMode.system:
        return Icons.brightness_auto;
      case AppThemeMode.light:
        return Icons.wb_sunny;
      case AppThemeMode.dark:
        return Icons.nightlight_round;
    }
  }

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _mode = AppThemeMode.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => AppThemeMode.dark,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setMode(AppThemeMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newMode.name);
    } catch (_) {}
  }
}
