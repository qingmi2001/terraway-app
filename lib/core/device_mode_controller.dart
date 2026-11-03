// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 车机/手持设备形态自适应控制器 (Device Mode Controller)
// 文件职责: 智能识别当前运行环境是手机还是安卓车载大屏 (车机)
//          提供横竖屏交互判定、大触控热区管理与车机到达蜂鸣提示音服务 (BeeperService)
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_controller.dart';

/// 设备交互形态偏好枚举
enum DeviceFormFactor {
  auto,      // 智能全自动推断 (根据横竖屏、屏幕物理尺寸动态切换)
  carUnit,   // 强制车机大屏交互 (左右双栏、大字体、蜂鸣提示)
  handheld,  // 强制手持模式 (紧凑单手流式仪表盘)
}

/// 全局车机/手持设备形态控制器 (单例模式)
class DeviceModeController with ChangeNotifier {
  static final DeviceModeController instance = DeviceModeController._internal();
  factory DeviceModeController() => instance;
  DeviceModeController._internal() {
    loadSettings();
  }

  static const String _prefKey = "device_form_factor_setting_v1";
  DeviceFormFactor _setting = DeviceFormFactor.auto;

  /// 用户配置的设备形态模式
  DeviceFormFactor get setting => _setting;

  /// 多语言显示的设置标题
  String get formFactorTitle {
    final isZh = LocaleController.instance.isZh;
    switch (_setting) {
      case DeviceFormFactor.auto:
        return isZh ? "自动识别设备" : "Auto Detect";
      case DeviceFormFactor.carUnit:
        return isZh ? "车载大屏模式" : "Car Cockpit";
      case DeviceFormFactor.handheld:
        return isZh ? "户外手持模式" : "Handheld GPS";
    }
  }

  /// 启动时从本地读取用户的设备形态偏好
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_prefKey);
      if (val != null) {
        _setting = DeviceFormFactor.values.firstWhere(
          (e) => e.name == val,
          orElse: () => DeviceFormFactor.auto,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 切换设备形态并落盘持久化
  Future<void> setFormFactor(DeviceFormFactor formFactor) async {
    if (_setting == formFactor) return;
    _setting = formFactor;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, formFactor.name);
    } catch (_) {}
  }

  /// 动态识别当前运行环境是否处于“车机大屏交互模式”
  /// 判定规则：若强制指定则遵从配置；若为自动，则当屏幕为横屏或最短边 >= 500dp (中控大屏) 时判定为车机
  bool isCarUnit(BuildContext context) {
    if (_setting == DeviceFormFactor.carUnit) return true;
    if (_setting == DeviceFormFactor.handheld) return false;

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isWideScreen = media.size.shortestSide >= 500;

    return isLandscape || isWideScreen;
  }
}

/// 车机/户外声光反馈服务 (BeeperService)
/// 核心解决安卓车机普遍缺乏物理振动马达的短板，在到达航点时提供双保险提示
class BeeperService {
  /// 到达航点时播放清脆、高穿透力的系统级警报蜂鸣音，并同时触发手机物理重度触觉震动
  static void playArrivalBeep() {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// 按钮操作轻触反馈音
  static void playClickFeedback() {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}
