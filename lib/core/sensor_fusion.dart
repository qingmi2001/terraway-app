// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 传感器融合中枢 (Sensor Fusion Manager)
// 文件职责: 融合底层物理 GNSS 卫星定位、对地真航向 (COG) 与地磁罗盘
//          搭载环形一阶低通抗颠簸滤波与车机无地磁罗盘静默平滑降级算法
// ==============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'math_utils.dart';
import 'navigation_mode.dart';

/// 导航综合状态数据包 (NavigationState)
/// 承载当前单帧的位姿、速度、精度、航向与到站距离数据
class NavigationState {
  final double currentLat;          // 当前车辆物理纬度 (WGS-84)
  final double currentLon;          // 当前车辆物理经度 (WGS-84)
  final double altitude;            // 当前高程海拔 (米)
  final double speedKmh;            // 瞬时对地速度 (km/h)
  final double accuracy;            // 定位水平精度偏差 (±米)
  final double currentHeading;      // 0°~360° 当前平滑车头航向
  final double targetBearing;       // 0°~360° 当前导引目标绝对方位角
  final double relativeBearing;     // -180°~+180° 罗盘导向大箭头相对夹角
  final double distanceMeters;      // 到达当前导引目标的直线大地距离 (米)
  final Duration? ete;              // 预估到达用时
  final bool isGpsCourseActive;     // 当前是否由 GPS 对地航向接管 (true 为卫星 COG，false 为地磁)
  final bool hasMagnetometer;       // 底层硬件是否存在地磁传感器

  /// 构造位置数据包快捷访问
  Position get position => Position(
    longitude: currentLon,
    latitude: currentLat,
    timestamp: DateTime.now(),
    accuracy: accuracy,
    altitude: altitude,
    altitudeAccuracy: 0.0,
    heading: currentHeading,
    headingAccuracy: 0.0,
    speed: speedKmh / 3.6,
    speedAccuracy: 0.0,
  );

  double get smoothedHeading => currentHeading;

  NavigationState({
    required this.currentLat,
    required this.currentLon,
    required this.altitude,
    required this.speedKmh,
    required this.accuracy,
    required this.currentHeading,
    required this.targetBearing,
    required this.relativeBearing,
    required this.distanceMeters,
    required this.ete,
    required this.isGpsCourseActive,
    this.hasMagnetometer = true,
  });
}

/// 环形一阶低通滤波器 (Circular Low-Pass Filter)
/// 算法原理：利用二维三角矢量 (cos theta, sin theta) 进行加权滑动累加
/// 解决角度在 0° 与 360° 拓扑跨越断裂时传统线性滤波引起的指针倒转 360 度倒抽问题
class CircularLowPassFilter {
  double alpha; // 平滑加权因子 (0.0 ~ 1.0)
  double? _cosSum;
  double? _sinSum;

  CircularLowPassFilter({this.alpha = 0.25});

  /// 对输入的即时原始角度进行环形平滑滤波
  double filter(double currentDegrees) {
    final rad = currentDegrees * (math.pi / 180.0);
    final curCos = math.cos(rad);
    final curSin = math.sin(rad);

    if (_cosSum == null || _sinSum == null) {
      _cosSum = curCos;
      _sinSum = curSin;
      return currentDegrees;
    }

    _cosSum = (1 - alpha) * _cosSum! + alpha * curCos;
    _sinSum = (1 - alpha) * _sinSum! + alpha * curSin;

    final avgRad = math.atan2(_sinSum!, _cosSum!);
    final avgDeg = avgRad * (180.0 / math.pi);
    return (avgDeg + 360.0) % 360.0;
  }

  /// 重置滤波器内部积分状态
  void reset() {
    _cosSum = null;
    _sinSum = null;
  }
}

/// 传感器融合中枢管理器 (SensorFusionManager)
class SensorFusionManager {
  final CircularLowPassFilter _filter = CircularLowPassFilter(alpha: 0.25);
  final StreamController<NavigationState> _stateController =
      StreamController<NavigationState>.broadcast();

  /// 供 UI 仪表盘订阅的导航综合状态流
  Stream<NavigationState> get stateStream => _stateController.stream;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  Position? _lastPosition;
  double _lastRawCompassHeading = 0.0;
  double _smoothHeading = 0.0;
  double _lastValidHeading = 0.0;
  bool _hasMagnetometer = true;

  // 当前导引目标点坐标 (默认库布齐夜鸣沙大本营，实际由路书动态注入)
  double _targetLat = 40.0822;
  double _targetLon = 108.6511;

  /// 动态更新当前导引的目标经纬度
  void setTarget(double lat, double lon) {
    _targetLat = lat;
    _targetLon = lon;
    _emitState();
  }

  /// 启动传感器监听通道
  Future<void> start() async {
    // 0. 启动时优先尝试读取系统最后已知位置或基站粗定位 (实现毫秒级秒开)
    try {
      final cachedPos = await Geolocator.getLastKnownPosition();
      if (cachedPos != null && _lastPosition == null) {
        _lastPosition = cachedPos;
        _emitState();
      }
    } catch (_) {}

    // 1. 监听地磁罗盘 (内置车机无磁力传感器的异常捕获保护)
    try {
      if (FlutterCompass.events != null) {
        _compassSub = FlutterCompass.events!.listen(
          (event) {
            if (event.heading != null) {
              _hasMagnetometer = true;
              _lastRawCompassHeading = (event.heading! + 360.0) % 360.0;
              _evaluateHeading();
            } else {
              _hasMagnetometer = false;
            }
          },
          onError: (err) {
            _hasMagnetometer = false;
            debugPrint("检测到设备无地磁传感器，平滑降级为纯 GPS COG 航向: $err");
          },
        );
      } else {
        _hasMagnetometer = false;
      }
    } catch (e) {
      _hasMagnetometer = false;
      debugPrint("地磁罗盘通道初始化安全降级: $e");
    }

    // 2. 监听 GPS 高精度位置与对地航向
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // 移动 1 米即刻触发解算
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _lastPosition = position;
      _evaluateHeading();
    });
  }

  /// 核心航向源仲裁与滤波平滑
  void _evaluateHeading() {
    if (_lastPosition == null) return;

    final profile = NavigationModeController.instance.currentProfile;
    final speedKmh = _lastPosition!.speed * 3.6;
    _filter.alpha = profile.filterAlpha;

    // 航向源仲裁规则：
    // 当车速大于当前运动模式门限，或硬件无地磁传感器时，完全信赖 GPS COG 航向
    final bool useGpsCourse = !_hasMagnetometer ||
        (speedKmh >= profile.cogSpeedThresholdKmh && _lastPosition!.heading >= 0);

    double rawTargetHeading;
    if (useGpsCourse) {
      if (_lastPosition!.heading >= 0) {
        rawTargetHeading = _lastPosition!.heading;
        _lastValidHeading = rawTargetHeading;
      } else {
        rawTargetHeading = _lastValidHeading;
      }
    } else {
      rawTargetHeading = _lastRawCompassHeading;
      _lastValidHeading = rawTargetHeading;
    }

    _smoothHeading = _filter.filter(rawTargetHeading);
    _emitState();
  }

  /// 广播解算完毕的导航状态数据帧
  void _emitState() {
    if (_lastPosition == null) return;

    final curLat = _lastPosition!.latitude;
    final curLon = _lastPosition!.longitude;
    final speedKmh = math.max(0.0, _lastPosition!.speed * 3.6);
    final profile = NavigationModeController.instance.currentProfile;
    final bool isGpsCourseActive = !_hasMagnetometer || speedKmh >= profile.cogSpeedThresholdKmh;

    final distanceMeters = MathUtils.haversineDistance(
      curLat,
      curLon,
      _targetLat,
      _targetLon,
    );

    final targetBearing = MathUtils.calculateBearing(
      curLat,
      curLon,
      _targetLat,
      _targetLon,
    );

    final relativeBearing = MathUtils.calculateRelativeBearing(
      targetBearing,
      _smoothHeading,
    );

    final ete = MathUtils.calculateETE(distanceMeters, _lastPosition!.speed);

    _stateController.add(
      NavigationState(
        currentLat: curLat,
        currentLon: curLon,
        altitude: _lastPosition!.altitude,
        speedKmh: speedKmh,
        accuracy: _lastPosition!.accuracy,
        currentHeading: _smoothHeading,
        targetBearing: targetBearing,
        relativeBearing: relativeBearing,
        distanceMeters: distanceMeters,
        ete: ete,
        isGpsCourseActive: isGpsCourseActive,
        hasMagnetometer: _hasMagnetometer,
      ),
    );
  }

  /// 暂停或停止传感器与位置流监听
  void stop() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _positionSub = null;
    _compassSub = null;
  }

  /// 释放资源
  void dispose() {
    stop();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
