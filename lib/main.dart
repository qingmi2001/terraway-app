// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 应用启动主入口 (Application Entry Point)
// 文件职责: 初始化全局单例、注入白天/暗夜高反差主题与中英双语多语言控制器
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme_controller.dart';
import 'core/locale_controller.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NmlyzxApp());
}

/// 应用程序根组件
class NmlyzxApp extends StatefulWidget {
  const NmlyzxApp({super.key});

  @override
  State<NmlyzxApp> createState() => _NmlyzxAppState();
}

class _NmlyzxAppState extends State<NmlyzxApp> {
  final ThemeController _themeCtrl = ThemeController.instance;
  final LocaleController _localeCtrl = LocaleController.instance;

  @override
  void initState() {
    super.initState();
    _themeCtrl.addListener(_onStateChanged);
    _localeCtrl.addListener(_onStateChanged);
    _localeCtrl.loadSavedLanguage();
  }

  @override
  void dispose() {
    _themeCtrl.removeListener(_onStateChanged);
    _localeCtrl.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: I18n.appTitle,
      locale: _localeCtrl.locale,
      debugShowCheckedModeBanner: false,
      themeMode: _themeCtrl.flutterThemeMode,

      // 白天高光高反差主题 (沙漠戈壁强日光直射高可视)
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        cardColor: const Color(0xFFFFFFFF),
        dividerColor: const Color(0xFFD6D9E0),
        primaryColor: const Color(0xFF007733),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF111111),
          elevation: 0,
        ),
        fontFamily: 'monospace',
      ),

      // 暗夜防眩目主题 (纯黑底色配合荧光绿，夜间越野防刺眼保护暗视力)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        cardColor: const Color(0xFF0D0D0D),
        dividerColor: const Color(0xFF262626),
        primaryColor: const Color(0xFF00FF66),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        fontFamily: 'monospace',
      ),

      // 启动默认进入 HomeScreen (卫星遥测待机与当前物理经纬度首页)
      home: const HomeScreen(),
    );
  }
}
