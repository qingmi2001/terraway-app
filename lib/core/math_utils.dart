// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 纯离线大地测量与导航数学算法库 (Math Utils)
// 文件职责: 提供 WGS-84 球面大圆直线距离 (Haversine)、目标绝对方位角 (BRG)、
//          相对导向夹角、到达用时 (ETE)、度分秒 (DMS) 双向高精度转换与风向解析
// ==============================================================================

import 'dart:math' as math;

/// 度分秒 (DMS) 标准结构体
/// 专为资深越野驴友、纸质等高线地图、驻军防火图与民间应急救援通联规范设计
class DmsValue {
  final String direction; // 半球方位代号: N (北纬), S (南纬), E (东经), W (西经)
  final int degrees;       // 度 (0° ~ 180°)
  final int minutes;       // 分 (0' ~ 59')
  final double seconds;    // 秒 (0.0" ~ 59.9")

  const DmsValue({
    required this.direction,
    required this.degrees,
    required this.minutes,
    required this.seconds,
  });

  /// 转换为规范格式化字符串，如: N 40°04'55.9"
  String toFormattedString() {
    return "$direction $degrees°${minutes.toString().padLeft(2, '0')}'${seconds.toStringAsFixed(1)}\"";
  }

  /// 换算为十进制浮点度数 (WGS-84 Decimal Degrees)
  double toDecimal() {
    double val = degrees + (minutes / 60.0) + (seconds / 3600.0);
    if (direction == "S" || direction == "W") {
      val = -val;
    }
    return val;
  }
}

/// 纯离线大地测量与导航数学计算库
class MathUtils {
  /// 地球平均半径 (米)
  static const double earthRadiusMeters = 6371000.0;

  /// 计算两点间 Haversine 球面大地直线距离 (米)
  /// 输入为两点的十进制经纬度坐标
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final rLat1 = _degreesToRadians(lat1);
    final rLat2 = _degreesToRadians(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) * math.cos(rLat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// 计算目标绝对方位角 (BRG / Bearing, 0° ~ 360° 正北参考)
  /// 从当前车辆坐标指向目标坐标的正北夹角
  static double calculateBearing(
    double currentLat,
    double currentLon,
    double targetLat,
    double targetLon,
  ) {
    final dLon = _degreesToRadians(targetLon - currentLon);
    final rLat1 = _degreesToRadians(currentLat);
    final rLat2 = _degreesToRadians(targetLat);

    final y = math.sin(dLon) * math.cos(rLat2);
    final x = math.cos(rLat1) * math.sin(rLat2) -
        math.sin(rLat1) * math.cos(rLat2) * math.cos(dLon);

    final initialBearingRad = math.atan2(y, x);
    final initialBearingDeg = _radiansToDegrees(initialBearingRad);

    return (initialBearingDeg + 360.0) % 360.0;
  }

  /// 计算罗盘中心导向大箭头的相对偏向夹角 (-180° ~ +180°)
  /// 导向指针直观显示“箭头指哪、方向盘往哪打”
  static double calculateRelativeBearing(double targetBearing, double currentHeading) {
    var diff = targetBearing - currentHeading;
    while (diff > 180.0) diff -= 360.0;
    while (diff < -180.0) diff += 360.0;
    return diff;
  }

  /// 估算到达用时 (ETE, Estimated Time Enroute)
  /// 当速度低于 0.8 m/s (约 3 km/h 蠕行/驻车) 时返回 null 显示占位符
  static Duration? calculateETE(double distanceMeters, double speedMps) {
    if (speedMps <= 0.8) return null;
    final seconds = (distanceMeters / speedMps).round();
    return Duration(seconds: seconds);
  }

  /// 格式化 ETE 显示为 HH:MM:SS
  static String formatDuration(Duration? duration) {
    if (duration == null) return "--:--:--";
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  /// 格式化经纬度浮点数为度分秒规范字符串
  static String formatCoordinate(double value, bool isLatitude) {
    final dms = decimalToDms(value, isLatitude);
    return dms.toFormattedString();
  }

  /// 十进制浮点度数转为度分秒结构体 (DmsValue)
  static DmsValue decimalToDms(double value, bool isLatitude) {
    final dir = isLatitude
        ? (value >= 0 ? "N" : "S")
        : (value >= 0 ? "E" : "W");
    final absVal = value.abs();
    final degrees = absVal.floor();
    final minutesDouble = (absVal - degrees) * 60;
    final minutes = minutesDouble.floor();
    final seconds = (minutesDouble - minutes) * 60;

    return DmsValue(
      direction: dir,
      degrees: degrees,
      minutes: minutes,
      seconds: seconds,
    );
  }

  /// 度分秒各分量换算为十进制浮点度数
  static double dmsToDecimal(String direction, int degrees, int minutes, double seconds) {
    double dec = degrees + (minutes / 60.0) + (seconds / 3600.0);
    if (direction == "S" || direction == "W") {
      dec = -dec;
    }
    return dec;
  }

  /// 将角度值 (0°~360°) 映射为八面风向字符串 (如: 045° 东北 NE)
  static String degreesToCompassDirection(double degrees) {
    final deg = (degrees.round() % 360 + 360) % 360;
    if (deg >= 338 || deg < 23) return "正北 N";
    if (deg >= 23 && deg < 68) return "东北 NE";
    if (deg >= 68 && deg < 113) return "正东 E";
    if (deg >= 113 && deg < 158) return "东南 SE";
    if (deg >= 158 && deg < 203) return "正南 S";
    if (deg >= 203 && deg < 248) return "西南 SW";
    if (deg >= 248 && deg < 293) return "正西 W";
    return "西北 NW";
  }

  static double _degreesToRadians(double degrees) => degrees * (math.pi / 180.0);
  static double _radiansToDegrees(double radians) => radians * (180.0 / math.pi);
}
