// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 轨迹数据实体模型 (Track & TrackPoint Model)
// 文件职责: 封装单点高精度经纬度/高程/速度/航向实体 (TrackPoint) 与完整轨迹 (Track)
//          实现标准 GPX 1.1 导出与遇险保命“一键原路返航”倒序抽稀转路书算法
// ==============================================================================

import 'dart:convert';
import 'dart:math' as math;
import '../core/navigation_mode.dart';
import 'waypoint.dart';
import 'roadbook.dart';

/// 轨迹单点实体 (TrackPoint)
/// 包含经纬度、高程、瞬时速度、航向角、时间戳与定位精度全要素数据
class TrackPoint {
  final double lat;        // 纬度 (WGS-84, 十进制双精度)
  final double lon;        // 经度 (WGS-84, 十进制双精度)
  final double altitude;   // 海拔高程 (米，经滑动中值滤波平滑)
  final double speedKmh;    // 瞬时速度 (km/h)
  final double heading;     // 航向角 (0°~360° 正北参考)
  final DateTime time;     // 采集时间戳 (UTC/Local)
  final double accuracy;   // 水平定位精度偏差 (±米)

  TrackPoint({
    required this.lat,
    required this.lon,
    required this.altitude,
    required this.speedKmh,
    required this.heading,
    required this.time,
    required this.accuracy,
  });

  /// 序列化为轻量 JSON 字典 (优化键名减少本地存储开销)
  Map<String, dynamic> toJson() => {
        "lat": lat,
        "lon": lon,
        "alt": altitude,
        "spd": speedKmh,
        "hdg": heading,
        "t": time.toIso8601String(),
        "acc": accuracy,
      };

  /// 从 JSON 字典反序列化生成轨迹单点
  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        lat: (json["lat"] as num).toDouble(),
        lon: (json["lon"] as num).toDouble(),
        altitude: (json["alt"] as num?)?.toDouble() ?? 0.0,
        speedKmh: (json["spd"] as num?)?.toDouble() ?? 0.0,
        heading: (json["hdg"] as num?)?.toDouble() ?? 0.0,
        time: DateTime.tryParse(json["t"] as String? ?? "") ?? DateTime.now(),
        accuracy: (json["acc"] as num?)?.toDouble() ?? 0.0,
      );
}

/// 户外实测轨迹完整实体 (Track)
/// 包含行程宏观统计指标、航迹点序列、本地持久化与格式转换算法
class Track {
  final String id;                  // 轨迹唯一 UUID 标识
  String name;                      // 轨迹名称 (如: 山海轨迹_1030_1835)
  final OutdoorSportMode mode;       // 录制时的运动模式 (自驾/徒步/骑行/搜救)
  final DateTime startTime;         // 开始录制时间
  DateTime? endTime;                // 结束录制时间
  double totalDistanceMeters;       // 累计总里程 (米，经 Haversine 积分累加)
  Duration movingDuration;          // 有效运动耗时 (剔除静止驻车时间)
  Duration totalDuration;           // 行程总耗时 (含中途停顿)
  double maxSpeedKmh;               // 行程最高时速 (km/h)
  double avgSpeedKmh;               // 行程平均运动时速 (km/h)
  double minAltitude;               // 最低海拔 (米)
  double maxAltitude;               // 最高海拔 (米)
  double totalAscent;               // 累计爬升拔高 (米)
  double totalDescent;              // 累计下降海拔 (米)
  final List<TrackPoint> points;    // 完整航迹采样点序列
  bool isRecording;                 // 是否处于录制中状态
  bool isPaused;                    // 是否处于暂停状态
  bool isSynced;                    // 是否已同步至云端用户账户 (预留后续联网版本)

  Track({
    required this.id,
    required this.name,
    this.mode = OutdoorSportMode.offroad,
    required this.startTime,
    this.endTime,
    this.totalDistanceMeters = 0.0,
    this.movingDuration = Duration.zero,
    this.totalDuration = Duration.zero,
    this.maxSpeedKmh = 0.0,
    this.avgSpeedKmh = 0.0,
    this.minAltitude = 0.0,
    this.maxAltitude = 0.0,
    this.totalAscent = 0.0,
    this.totalDescent = 0.0,
    List<TrackPoint>? points,
    this.isRecording = false,
    this.isPaused = false,
    this.isSynced = false,
  }) : points = points ?? [];

  /// 生成国际标准 GPX 1.1 交换格式 XML 字符串
  /// 兼容主流 GIS 软件、专业手持仪 (GPSMAP 系列) 与户外开放平台
  String toGpxXml() => toGpxString();

  String toGpxString() {
    final buffer = StringBuffer();
    buffer.writeln("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
    buffer.writeln("<gpx version=\"1.1\" creator=\"TerraWay ShanHaiXing GPS\"");
    buffer.writeln("  xmlns=\"http://www.topografix.com/GPX/1/1\"");
    buffer.writeln("  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"");
    buffer.writeln("  xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">");
    buffer.writeln("  <metadata>");
    buffer.writeln("    <name><![CDATA[$name]]></name>");
    buffer.writeln("    <desc><![CDATA[Recorded by 山海行 (TerraWay) All-Terrain Handheld GPS]]></desc>");
    buffer.writeln("    <time>${startTime.toUtc().toIso8601String()}</time>");
    buffer.writeln("  </metadata>");
    buffer.writeln("  <trk>");
    buffer.writeln("    <name><![CDATA[$name]]></name>");
    buffer.writeln("    <type>${mode.name}</type>");
    buffer.writeln("    <trkseg>");
    for (final pt in points) {
      buffer.writeln("      <trkpt lat=\"${pt.lat.toStringAsFixed(6)}\" lon=\"${pt.lon.toStringAsFixed(6)}\">");
      buffer.writeln("        <ele>${pt.altitude.toStringAsFixed(1)}</ele>");
      buffer.writeln("        <time>${pt.time.toUtc().toIso8601String()}</time>");
      buffer.writeln("        <speed>${(pt.speedKmh / 3.6).toStringAsFixed(2)}</speed>");
      buffer.writeln("      </trkpt>");
    }
    buffer.writeln("    </trkseg>");
    buffer.writeln("  </trk>");
    buffer.writeln("</gpx>");
    return buffer.toString();
  }

  /// 一键将轨迹转换为可导航的多点连续路书 (Roadbook)
  /// [customName]: 自定义路书标题
  /// [reverse]: 是否倒序（true 为极其重要的“一键原路返航脱困”算法，带领迷路车队原路安全撤出）
  /// [maxPoints]: 最大航点抽稀上限（默认 50 点，符合人类驾驶与换向反应最佳视距）
  Roadbook toRoadbook({String? customName, bool reverse = false, int maxPoints = 50}) {
    if (points.isEmpty) {
      return Roadbook(id: "rb_${DateTime.now().millisecondsSinceEpoch}", name: customName ?? "空白路线");
    }

    // 等步长多边形特征抽稀算法
    List<TrackPoint> sampled = [];
    if (points.length <= maxPoints) {
      sampled = List.from(points);
    } else {
      final step = points.length / (maxPoints - 1);
      for (int i = 0; i < maxPoints - 1; i++) {
        sampled.add(points[(i * step).floor().clamp(0, points.length - 1)]);
      }
      sampled.add(points.last);
    }

    // 倒序原路返航处理
    if (reverse) {
      sampled = sampled.reversed.toList();
    }

    final targetName = customName ?? (reverse ? "循迹返航·$name" : "路书·$name");
    final waypoints = <Waypoint>[];
    for (int i = 0; i < sampled.length; i++) {
      final p = sampled[i];
      final prefix = reverse ? "R" : "T";
      final wpName = i == 0
          ? (reverse ? "R0·返航脱困起点" : "T1·起点")
          : (i == sampled.length - 1
              ? (reverse ? "R${i}·大本营安全终点" : "T${i + 1}·终点")
              : "$prefix${i + 1}·途经点");
      waypoints.add(Waypoint(
        id: "wp_${DateTime.now().millisecondsSinceEpoch}_$i",
        name: wpName,
        lat: p.lat,
        lon: p.lon,
        desc: "海拔 ${p.altitude.toStringAsFixed(0)}m · 时速 ${p.speedKmh.toStringAsFixed(1)}km/h",
      ));
    }

    return Roadbook(
      id: "rb_${DateTime.now().millisecondsSinceEpoch}",
      name: targetName,
      desc: reverse
          ? "由实测轨迹一键倒序生成的保命返航路书，全长 ${(totalDistanceMeters / 1000).toStringAsFixed(1)}km"
          : "由实测轨迹转换的自驾/徒步路书，全长 ${(totalDistanceMeters / 1000).toStringAsFixed(1)}km",
      points: waypoints,
      arrivalRadiusMeters: mode == OutdoorSportMode.offroad ? 120.0 : 30.0,
    );
  }

  /// 序列化为完整 JSON 字典，用于持久化落盘至手机本地私有沙盒
  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "mode": mode.name,
        "startTime": startTime.toIso8601String(),
        "endTime": endTime?.toIso8601String(),
        "dist": totalDistanceMeters,
        "movSec": movingDuration.inSeconds,
        "totSec": totalDuration.inSeconds,
        "maxSpd": maxSpeedKmh,
        "avgSpd": avgSpeedKmh,
        "minAlt": minAltitude,
        "maxAlt": maxAltitude,
        "ascent": totalAscent,
        "descent": totalDescent,
        "synced": isSynced,
        "pts": points.map((p) => p.toJson()).toList(),
      };

  /// 从持久化 JSON 字典反序列化恢复轨迹实体
  factory Track.fromJson(Map<String, dynamic> json) {
    final modeName = json["mode"] as String? ?? "offroad";
    final mode = OutdoorSportMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => OutdoorSportMode.offroad,
    );
    return Track(
      id: json["id"] as String? ?? "trk_${DateTime.now().millisecondsSinceEpoch}",
      name: json["name"] as String? ?? "未命名轨迹",
      mode: mode,
      startTime: DateTime.tryParse(json["startTime"] as String? ?? "") ?? DateTime.now(),
      endTime: json["endTime"] != null ? DateTime.tryParse(json["endTime"] as String) : null,
      totalDistanceMeters: (json["dist"] as num?)?.toDouble() ?? 0.0,
      movingDuration: Duration(seconds: json["movSec"] as int? ?? 0),
      totalDuration: Duration(seconds: json["totSec"] as int? ?? 0),
      maxSpeedKmh: (json["maxSpd"] as num?)?.toDouble() ?? 0.0,
      avgSpeedKmh: (json["avgSpd"] as num?)?.toDouble() ?? 0.0,
      minAltitude: (json["minAlt"] as num?)?.toDouble() ?? 0.0,
      maxAltitude: (json["maxAlt"] as num?)?.toDouble() ?? 0.0,
      totalAscent: (json["ascent"] as num?)?.toDouble() ?? 0.0,
      totalDescent: (json["descent"] as num?)?.toDouble() ?? 0.0,
      isSynced: json["synced"] as bool? ?? false,
      points: (json["pts"] as List<dynamic>?)
              ?.map((item) => TrackPoint.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 高级轨迹转路书算法 (智能自适应打点、等距抽稀与关键转弯特征保留)
  /// [customName]: 自定义路书标题
  /// [distanceIntervalMeters]: 自动等距抽稀步长 (如 500m, 1000m, 2000m, 5000m)
  /// [preserveTurns]: 是否开启航向角突变识别 (>35° 关键拐弯自动打点)
  /// [maxPoints]: 最大航点保护上限 (防止过多点位拖垮渲染)
  /// [manualWaypoints]: 用户手动微调或指定的特征点位
  Roadbook toRoadbookAdvanced({
    String? customName,
    double distanceIntervalMeters = 1000.0,
    bool preserveTurns = true,
    int maxPoints = 60,
    List<Waypoint>? manualWaypoints,
  }) {
    if (points.isEmpty) {
      return Roadbook(id: "rb_${DateTime.now().millisecondsSinceEpoch}", name: customName ?? "空白路线");
    }

    if (manualWaypoints != null && manualWaypoints.isNotEmpty) {
      return Roadbook(
        id: "rb_${DateTime.now().millisecondsSinceEpoch}",
        name: customName ?? "路书·$name",
        desc: "自定义指定点位路书，全长 ${(totalDistanceMeters / 1000).toStringAsFixed(1)}km",
        points: manualWaypoints,
        arrivalRadiusMeters: mode == OutdoorSportMode.offroad ? 120.0 : 30.0,
      );
    }

    // 智能萃取关键航迹点
    final List<Map<String, dynamic>> extracted = [];
    
    // 1. 始终包含起点
    extracted.add({
      "point": points.first,
      "type": "start",
      "name": "起点",
      "dist": 0.0,
    });

    double lastSampleDist = 0.0;
    double accumulatedDist = 0.0;
    double? lastHeading;

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // 计算步进距离 (Haversine 粗算)
      final dLat = (curr.lat - prev.lat) * math.pi / 180.0;
      final dLon = (curr.lon - prev.lon) * math.pi / 180.0;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(prev.lat * math.pi / 180.0) *
              math.cos(curr.lat * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      final stepDist = 6371000.0 * c;
      accumulatedDist += stepDist;

      bool shouldAdd = false;
      String ptType = "interval";
      String ptName = "";

      // A. 等距抽稀判定
      if (accumulatedDist - lastSampleDist >= distanceIntervalMeters) {
        shouldAdd = true;
        ptType = "interval";
        final km = accumulatedDist / 1000.0;
        ptName = "P${extracted.length} (${km.toStringAsFixed(1)}km)";
      }
      // B. 航向角突变判定 (转弯特征点)
      else if (preserveTurns && curr.heading > 0 && lastHeading != null && lastHeading! > 0) {
        double diff = (curr.heading - lastHeading!).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff >= 35.0 && (accumulatedDist - lastSampleDist >= 200.0)) {
          shouldAdd = true;
          ptType = "turn";
          final km = accumulatedDist / 1000.0;
          ptName = "转角${extracted.length} (${km.toStringAsFixed(1)}km)";
        }
      }

      if (shouldAdd) {
        extracted.add({
          "point": curr,
          "type": ptType,
          "name": ptName,
          "dist": accumulatedDist,
        });
        lastSampleDist = accumulatedDist;
        if (extracted.length >= maxPoints - 1) break;
      }

      if (curr.heading > 0) lastHeading = curr.heading;
    }

    // 2. 始终包含终点
    extracted.add({
      "point": points.last,
      "type": "finish",
      "name": "终点",
      "dist": totalDistanceMeters,
    });

    final targetName = customName ?? "路书·$name";
    final waypoints = <Waypoint>[];
    for (int i = 0; i < extracted.length; i++) {
      final item = extracted[i];
      final p = item["point"] as TrackPoint;
      final name = item["name"] as String;
      waypoints.add(Waypoint(
        id: "wp_${DateTime.now().millisecondsSinceEpoch}_$i",
        name: name,
        lat: p.lat,
        lon: p.lon,
        desc: "里程 ${((item["dist"] as double) / 1000).toStringAsFixed(1)}km · 海拔 ${p.altitude.toStringAsFixed(0)}m",
      ));
    }

    return Roadbook(
      id: "rb_${DateTime.now().millisecondsSinceEpoch}",
      name: targetName,
      desc: "实测轨迹自适应萃取路书，全长 ${(totalDistanceMeters / 1000).toStringAsFixed(1)}km，共 ${waypoints.length} 个特征航点",
      points: waypoints,
      arrivalRadiusMeters: mode == OutdoorSportMode.offroad ? 120.0 : 30.0,
    );
  }

}
