// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 多运动导航模式状态中枢 (Navigation Mode Controller)
// 文件职责: 定义四大户外运动模式 (越野自驾 / 山林徒步 / 骑行探险 / 应急搜救)
//          针对不同场景差异化配置到达半径、GPS COG 门限、滤波系数与采样策略
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_controller.dart';

/// 户外运动细分模式枚举
enum OutdoorSportMode {
  offroad, // 越野自驾 (高时速、强电磁干扰、大到达判定圆)
  hiking,  // 山林徒步 (低时速、地磁罗盘优先、小到达判定圆)
  cycling, // 骑行探险 (中速行进、车把颠簸抑制、坡度偏重)
  rescue,  // 应急搜救 (米级精细判定、高精度 DMS 物理坐标直出)
}

/// 各运动模式专属技术配置 Profile
/// 为底层传感器融合算法、路书自动换向引擎与轨迹记录器提供参数输入
class NavigationModeProfile {
  final OutdoorSportMode mode;
  final String zhName;
  final String enName;
  final String zhDesc;
  final String enDesc;
  final IconData icon;

  /// 到达判定圆半径 (米)
  /// 车辆/人员与当前航点直线距离小于该阈值时，自动触发到达并指向下一站
  final double defaultArrivalRadius;

  /// 启用 GPS 对地真航向 (COG) 的速度门限 (km/h)
  /// 超过该速度时强制屏蔽易受干扰的地磁计，完全信赖卫星位移解算出的航向
  final double cogSpeedThresholdKmh;

  /// 环形一阶低通滤波平滑因子 alpha (0.0 ~ 1.0)
  /// 数值越小滤波越强（更平滑抗颠簸），数值越大响应越敏捷
  final double filterAlpha;

  /// 轨迹记录：原地驻车/静止死区过滤时速 (km/h)
  /// 低于此速度且位移极小时判定为静止，强制不记点，防止营地画乱麻伪轨迹
  final double deadbandSpeedKmh;

  /// 轨迹记录：原地驻车死区过滤位移 (米)
  final double deadbandDistanceMeters;

  /// 轨迹记录：动态采样时间触发间隔 (秒)
  final int trackSamplingIntervalSeconds;

  /// 轨迹记录：动态采样位移触发间隔 (米)
  final double trackSamplingDistanceMeters;

  const NavigationModeProfile({
    required this.mode,
    required this.zhName,
    required this.enName,
    required this.zhDesc,
    required this.enDesc,
    required this.icon,
    required this.defaultArrivalRadius,
    required this.cogSpeedThresholdKmh,
    required this.filterAlpha,
    required this.deadbandSpeedKmh,
    required this.deadbandDistanceMeters,
    required this.trackSamplingIntervalSeconds,
    required this.trackSamplingDistanceMeters,
  });

  /// 响应当前系统语言的多语言名称
  String get name => LocaleController.instance.isZh ? zhName : enName;

  /// 响应当前系统语言的多语言简要描述
  String get desc => LocaleController.instance.isZh ? zhDesc : enDesc;

  /// 预置四大典型户外运动模式配置字典
  static const Map<OutdoorSportMode, NavigationModeProfile> profiles = {
    // 1. 越野自驾：适应沙漠、戈壁高速颠簸与车内强电磁干扰
    OutdoorSportMode.offroad: NavigationModeProfile(
      mode: OutdoorSportMode.offroad,
      zhName: "越野自驾",
      enName: "Off-Road",
      zhDesc: "车速快 / 强电磁干扰 / 150m判定圆",
      enDesc: "High speed, anti-EMI COG lock, 150m radius",
      icon: Icons.directions_car,
      defaultArrivalRadius: 150.0,
      cogSpeedThresholdKmh: 3.0,
      filterAlpha: 0.25,
      deadbandSpeedKmh: 1.5,
      deadbandDistanceMeters: 8.0,
      trackSamplingIntervalSeconds: 3,
      trackSamplingDistanceMeters: 10.0,
    ),

    // 2. 山林徒步：适应密林慢速行进与频繁停步观察
    OutdoorSportMode.hiking: NavigationModeProfile(
      mode: OutdoorSportMode.hiking,
      zhName: "山林徒步",
      enName: "Hiking",
      zhDesc: "低速地磁罗盘优先 / 20m精细判定圆",
      enDesc: "Pedestrian compass-first & 20m tight radius",
      icon: Icons.hiking,
      defaultArrivalRadius: 20.0,
      cogSpeedThresholdKmh: 1.5,
      filterAlpha: 0.35,
      deadbandSpeedKmh: 0.8,
      deadbandDistanceMeters: 4.0,
      trackSamplingIntervalSeconds: 5,
      trackSamplingDistanceMeters: 5.0,
    ),

    // 3. 骑行探险：适应公路与山地车把高频震动
    OutdoorSportMode.cycling: NavigationModeProfile(
      mode: OutdoorSportMode.cycling,
      zhName: "骑行探险",
      enName: "Cycling",
      zhDesc: "中速平滑抗颠簸 / 40m判定圆",
      enDesc: "Medium speed, vibration-damped, 40m radius",
      icon: Icons.pedal_bike,
      defaultArrivalRadius: 40.0,
      cogSpeedThresholdKmh: 5.0,
      filterAlpha: 0.20,
      deadbandSpeedKmh: 1.2,
      deadbandDistanceMeters: 6.0,
      trackSamplingIntervalSeconds: 3,
      trackSamplingDistanceMeters: 8.0,
    ),

    // 4. 应急搜救：适应前线搜救队厘米/米级精准找点与经纬度报送
    OutdoorSportMode.rescue: NavigationModeProfile(
      mode: OutdoorSportMode.rescue,
      zhName: "应急搜救",
      enName: "SAR Rescue",
      zhDesc: "高精度DMS坐标直出 / 10m米级判定圆",
      enDesc: "Exact DMS coordinates & 10m micro radius",
      icon: Icons.emergency,
      defaultArrivalRadius: 10.0,
      cogSpeedThresholdKmh: 2.0,
      filterAlpha: 0.30,
      deadbandSpeedKmh: 0.5,
      deadbandDistanceMeters: 3.0,
      trackSamplingIntervalSeconds: 2,
      trackSamplingDistanceMeters: 4.0,
    ),
  };
}

/// 全局运动模式控制器 (单例模式 + 本地沙盒持久化落盘)
class NavigationModeController with ChangeNotifier {
  static final NavigationModeController instance = NavigationModeController._internal();
  factory NavigationModeController() => instance;
  NavigationModeController._internal() {
    loadSavedMode();
  }

  static const String _prefKey = "active_navigation_mode_v1";
  OutdoorSportMode _currentMode = OutdoorSportMode.offroad;

  /// 当前激活的运动模式
  OutdoorSportMode get currentMode => _currentMode;

  /// 当前激活的运动模式技术参数对象
  NavigationModeProfile get currentProfile => NavigationModeProfile.profiles[_currentMode]!;

  /// 当前激活模式的专属图标
  IconData get currentModeIcon => currentProfile.icon;

  /// 当前激活模式的多语言名称
  String get currentModeName => currentProfile.name;

  /// 当前激活模式的到达换向判定半径 (米)
  double get currentThresholdMeters => currentProfile.defaultArrivalRadius;

  /// 循环切换至下一个运动模式
  void cycleToNextMode() {
    final values = OutdoorSportMode.values;
    final nextIndex = (values.indexOf(_currentMode) + 1) % values.length;
    setMode(values[nextIndex]);
  }

  /// 启动时从本地持久化存储加载用户上次选择的模式
  Future<void> loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _currentMode = OutdoorSportMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => OutdoorSportMode.offroad,
        );
        notifyListeners();
      }
    } catch (_) {
      // 离线容错保持默认越野自驾模式
    }
  }

  /// 切换当前运动模式并原子化持久化落盘
  Future<void> setMode(OutdoorSportMode mode) async {
    if (_currentMode == mode) return;
    _currentMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }
}
