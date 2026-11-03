// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 全局视觉设计规范与风格基础代码 (App Style & Design System Tokens)
// 文件职责: 固化全应用统一的工业级高反差配色、等宽排版、卡片与按钮组件规范，
//          防止后续迭代或新人介入开发时风格突变、破坏硬派户外手持仪质感。
// ==============================================================================

import 'package:flutter/material.dart';

/// ============================================================================
/// 一、 核心设计哲学与三大铁律 (Core Philosophy)
/// ============================================================================
/// 1. 【0.5 秒高反差扫视原则】:
///    所有界面专为强颠簸越野车机、烈日直射沙漠与纯黑无光荒野调校。
///    拒绝低对比度浅灰渐变，文字与背景对比度必须 >= 7:1。
/// 2. 【等宽数字防抖动锁相原则】:
///    所有瞬时时速、直线距离、度分秒坐标、高程海拔、航向角必须严格锁死
///    fontFamily: 'monospace'，避免数据毫秒级跳动时宽度伸缩导致界面晃动。
/// 3. 【去商业化极简工业仪器风】:
///    界面定位为“专业三防手持机/航海航空级仪表盘”，坚决禁止引入圆润泡泡风、
///    过度花哨的阴影动效、电商卡片风或互联网消费软件的多余元素。
/// ============================================================================

class AppStyle {
  AppStyle._();

  // --------------------------------------------------------------------------
  // 1. 颜色系统 (Color Tokens)
  // --------------------------------------------------------------------------

  // 1.1 核心画布底色 (Background & Surface)
  static const Color darkCanvas = Color(0xFF000000);         // 暗夜纯黑基底 (OLED 零发光省电)
  static const Color darkSurface = Color(0xFF0D0D0D);        // 暗夜一级容器底色
  static const Color darkSurfaceElevated = Color(0xFF141414);// 暗夜高层卡片底色
  static const Color darkSurfaceHighlight = Color(0xFF1A1A1A); // 暗夜高亮选中底色

  static const Color lightCanvas = Color(0xFFF8F9FA);        // 沙漠白昼抗直射基底
  static const Color lightSurface = Color(0xFFFFFFFF);       // 白昼卡片底色
  static const Color lightSurfaceAlt = Color(0xFFF1F5F9);     // 白昼次级灰底

  // 1.2 核心主导向电光绿 (Primary High-Vis Green)
  // 专用于：导向大指针、开始导航按钮、当前活跃航线指示、卫星锁定状态
  static const Color neonGreen = Color(0xFF00FF66);          // 暗夜超高亮荧光电光绿
  static const Color neonGreenShade = Color(0xFF00DD55);     // 暗夜指针受阴侧深绿
  static const Color neonGreenStroke = Color(0xFF003311);    // 暗夜指针边缘硬核描边
  static const Color neonGreenContainer = Color(0xFF0D2214); // 暗夜微透绿容器背景

  static const Color desertGreen = Color(0xFF008833);        // 白昼抗强光烈日纯绿
  static const Color desertGreenHighlight = Color(0xFF00AA33);// 白昼指针高光侧绿
  static const Color desertGreenShade = Color(0xFF007722);   // 白昼指针受阴侧绿
  static const Color desertGreenStroke = Color(0xFF00220A);  // 白昼纯深绿描边
  static const Color desertGreenContainer = Color(0xFFE8F7ED);// 白昼微绿容器背景

  // 1.3 遥测与坐标青蓝 (Telemetry & Coordinate Cyan/Sky Blue)
  // 专用于：度分秒 DMS 坐标分段、点位数统计徽标、卫星信噪比 C/N0 优秀柱体
  static const Color cyanTelemetryDark = Color(0xFF00FFFF);  // 暗夜电光青
  static const Color skyBlueDark = Color(0xFF38BDF8);        // 暗夜天蓝标签色
  static const Color cyanTelemetryLight = Color(0xFF0066CC); // 白昼深海蓝
  static const Color skyBlueLight = Color(0xFF0284C7);       // 白昼标牌蓝

  // 1.4 方位角与航向琥珀金 (Heading Amber / Compass Gold)
  // 专用于：目标航向 BRG、车头真航向 COG、备忘避险卡片高亮边框
  static const Color amberDark = Color(0xFFFFCC00);          // 暗夜战术明黄
  static const Color amberOrangeDark = Color(0xFFF59E0B);    // 暗夜暖琥珀
  static const Color amberContainerDark = Color(0xFF261D08); // 暗夜警示底色
  static const Color amberLight = Color(0xFFCC6600);         // 白昼深琥珀
  static const Color amberContainerLight = Color(0xFFFEF3C7);// 白昼浅黄警示底色

  // 1.5 严苛险情与正北红 (Danger Alert & True North Red)
  // 专用于：罗盘正北 N 标、重度避险暗坑软沙预警、紧急搜救模式
  static const Color alertRed = Color(0xFFFF3333);           // 高亮战术红
  static const Color alertRedLight = Color(0xFFDC2626);      // 白昼警示红

  // 1.6 工业级硬线条描边 (Industrial Borders & Dividers)
  static const Color borderDark = Color(0xFF262626);         // 暗夜标准边框灰
  static const Color borderDarkSubtle = Color(0xFF1E1E1E);   // 暗夜微弱边框
  static const Color borderLight = Color(0xFFE2E4E8);        // 白昼标准边框灰
  static const Color borderLightSubtle = Color(0xFFDCDFE6);  // 白昼浅灰分割线

  // --------------------------------------------------------------------------
  // 2. 动态自适应色彩获取器 (Theme Dynamic Resolvers)
  // --------------------------------------------------------------------------
  static Color primaryGreen(bool isDark) => isDark ? neonGreen : desertGreen;
  static Color primaryGreenContainer(bool isDark) => isDark ? neonGreenContainer : desertGreenContainer;
  static Color cardBackground(bool isDark) => isDark ? darkSurface : lightSurface;
  static Color cardBorder(bool isDark, {bool isActive = false}) {
    if (isActive) return isDark ? neonGreen : desertGreen;
    return isDark ? borderDark : borderLight;
  }
  static Color telemetryColor(bool isDark) => isDark ? cyanTelemetryDark : cyanTelemetryLight;
  static Color headingColor(bool isDark) => isDark ? amberDark : amberLight;
  static Color textPrimary(bool isDark) => isDark ? Colors.white : const Color(0xFF111827);
  static Color textSecondary(bool isDark) => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563);
  static Color textMuted(bool isDark) => isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);

  // --------------------------------------------------------------------------
  // 3. 字体与排版系统 (Typography System)
  // --------------------------------------------------------------------------

  /// 仪表盘核心大数值 (时速、距离、航向角)
  static TextStyle metricValueStyle(bool isDark, {Color? color, double fontSize = 28.0}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontFamily: 'monospace',
      letterSpacing: -0.5,
      color: color ?? textPrimary(isDark),
    );
  }

  /// 仪表盘指标英文简称标头 (DIST, SPEED, ETE, BRG)
  static TextStyle metricLabelStyle(bool isDark) {
    return TextStyle(
      fontSize: 10.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: textSecondary(isDark),
    );
  }

  /// 度分秒坐标规范字 (DMS: N 39°05'22.1")
  static TextStyle dmsCoordinateStyle(bool isDark, {double fontSize = 14.0}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
      letterSpacing: 0.5,
      color: telemetryColor(isDark),
    );
  }

  /// 卡片标题字体
  static TextStyle cardTitleStyle(bool isDark, {double fontSize = 15.0}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: textPrimary(isDark),
    );
  }

  /// 卡片辅助说明单行截断字体
  static TextStyle cardSubtitleStyle(bool isDark, {double fontSize = 11.5}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: textSecondary(isDark),
    );
  }

  // --------------------------------------------------------------------------
  // 4. 组件形制与尺寸规范 (Component Metrics)
  // --------------------------------------------------------------------------

  // 卡片标准外圆角 (拒绝超过 14px 的泡泡风大圆角，恪守 8px~10px 硬核工装感)
  static const double cardRadius = 8.0;
  static const double buttonRadius = 8.0;
  static const double tagRadius = 4.0;

  // 列表行标准高度约束 (单项高度必须锁在 56px~64px 间，确保一屏展示 8~10 行)
  static const double compactListItemHeight = 58.0;

  // 底部主操作条高度
  static const double bottomBarHeight = 50.0;

  // --------------------------------------------------------------------------
  // 5. 常用组件装饰盒子工厂 (Decoration Helpers)
  // --------------------------------------------------------------------------

  /// 高密度紧凑卡片边框修饰
  static BoxDecoration cardDecoration({
    required bool isDark,
    bool isActive = false,
    double radius = cardRadius,
  }) {
    return BoxDecoration(
      color: isActive ? primaryGreenContainer(isDark) : cardBackground(isDark),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: cardBorder(isDark, isActive: isActive),
        width: isActive ? 1.8 : 1.0,
      ),
    );
  }

  /// 微标签装饰 (如 "8点"、"当前"、"越野")
  static BoxDecoration badgeDecoration({
    required Color background,
    Color? borderColor,
    double radius = tagRadius,
  }) {
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: borderColor != null ? Border.all(color: borderColor, width: 0.8) : null,
    );
  }

  /// 搜索框标准装饰
  static InputDecoration searchInputDecoration({
    required bool isDark,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 13,
        color: textMuted(isDark),
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: BorderSide(color: isDark ? borderDark : borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: BorderSide(color: isDark ? borderDark : borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: BorderSide(color: primaryGreen(isDark), width: 1.5),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF161616) : Colors.white,
    );
  }
}
