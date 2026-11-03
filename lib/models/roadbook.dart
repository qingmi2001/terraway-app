// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 连续多点路书模型与本地持久化仓储 (Roadbook Model & Store)
// 文件职责: 承载 1~200 点连续多点越野穿越路书、到达半径自动换向判定、
//          折线剩余总里程算法以及应用私有物理沙盒 JSON 双重容灾落盘
// ==============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/math_utils.dart';
import 'waypoint.dart';

/// 扩展 Waypoint 模型支持 JSON 序列化
extension WaypointSerialization on Waypoint {
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'desc': desc,
        'isPreset': isPreset,
      };

  static Waypoint fromJsonMap(Map<String, dynamic> json) => Waypoint(
        id: json['id'] as String? ?? 'wp_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? '未命名航点',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
        desc: json['desc'] as String? ?? '',
        isPreset: json['isPreset'] as bool? ?? false,
      );
}

/// 连续多点穿越路书模型 (支持 1~200 个航点与本地存储)
class Roadbook {
  static const int maxPointsLimit = 200; // 点位上限 200 个

  final String id;
  String name;
  String desc;
  final List<Waypoint> points;
  int currentTargetIndex; // 当前导引目标点索引 (0 ~ points.length - 1)
  double arrivalRadiusMeters; // 到达判定半径 (默认 100 米)

  Roadbook({
    required this.id,
    required this.name,
    this.desc = '',
    List<Waypoint>? points,
    this.currentTargetIndex = 0,
    this.arrivalRadiusMeters = 100.0,
  }) : points = points ?? [];

  /// 当前导向的目标点
  Waypoint? get currentTarget {
    if (points.isEmpty) return null;
    return points[currentTargetIndex.clamp(0, points.length - 1)];
  }

  /// 是否还有下一站
  bool get hasNext => currentTargetIndex < points.length - 1;

  /// 是否有上一站
  bool get hasPrevious => currentTargetIndex > 0;

  /// 前往下一站 (手动跳点)
  bool nextPoint() {
    if (hasNext) {
      currentTargetIndex++;
      return true;
    }
    return false;
  }

  /// 返回上一站
  bool previousPoint() {
    if (hasPrevious) {
      currentTargetIndex--;
      return true;
    }
    return false;
  }

  /// 跳至指定点
  void jumpToPoint(int index) {
    if (index >= 0 && index < points.length) {
      currentTargetIndex = index;
    }
  }

  /// 自动到达判定与步进检测
  bool checkAndAutoAdvance(double distanceToCurrentTargetMeters) {
    if (distanceToCurrentTargetMeters <= arrivalRadiusMeters && hasNext) {
      currentTargetIndex++;
      return true; // 触发自动步进
    }
    return false;
  }

  /// 计算沿路线折线的剩余总距离 (米)
  double calculateTotalRemainingDistance(double currentLat, double currentLon) {
    if (points.isEmpty) return 0.0;
    final curTarget = currentTarget!;
    double total = MathUtils.haversineDistance(
      currentLat,
      currentLon,
      curTarget.lat,
      curTarget.lon,
    );

    for (int i = currentTargetIndex; i < points.length - 1; i++) {
      total += MathUtils.haversineDistance(
        points[i].lat,
        points[i].lon,
        points[i + 1].lat,
        points[i + 1].lon,
      );
    }
    return total;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'currentTargetIndex': currentTargetIndex,
        'arrivalRadiusMeters': arrivalRadiusMeters,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory Roadbook.fromJson(Map<String, dynamic> json) => Roadbook(
        id: json['id'] as String? ?? 'rb_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? '未命名路线',
        desc: json['desc'] as String? ?? '',
        currentTargetIndex: json['currentTargetIndex'] as int? ?? 0,
        arrivalRadiusMeters: (json['arrivalRadiusMeters'] as num?)?.toDouble() ?? 100.0,
        points: (json['points'] as List<dynamic>?)
                ?.map((item) => WaypointSerialization.fromJsonMap(item as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// 全局路书与本地持久化仓储中枢 (支持手机本地永久保存与重开自恢复)
class RoadbookStore with ChangeNotifier {
  static final RoadbookStore instance = RoadbookStore._internal();
  RoadbookStore._internal() {
    _initAndLoad();
  }

  final List<Roadbook> _roadbooks = [];
  int _activeRoadbookIndex = 0;
  bool _isLoaded = false;

  List<Roadbook> get roadbooks => List.unmodifiable(_roadbooks);

  Roadbook get activeRoadbook {
    if (_roadbooks.isEmpty) {
      final fallback = Roadbook(id: 'default', name: '临时路线');
      _roadbooks.add(fallback);
      return fallback;
    }
    return _roadbooks[_activeRoadbookIndex.clamp(0, _roadbooks.length - 1)];
  }

  int get activeRoadbookIndex => _activeRoadbookIndex;

  Future<void> _initAndLoad() async {
    _initDefaults();
    await _loadFromLocalDisk();
  }

  void _initDefaults() {
    final kubuqiRoute = Roadbook(
      id: 'rb_kubuqi',
      name: "库布齐沙漠穿沙经典全线",
      desc: "穿沙北线入口 ➔ 一号水源 ➔ 大沙山脊 ➔ 刀锋营地 ➔ 穿沙终点 (全长120km连续路书)",
      arrivalRadiusMeters: 100.0,
      points: [
        Waypoint(id: 'p1', name: "S1·北线集结大本营", lat: 40.0822, lon: 108.6511, desc: "放气与旗杆安装处"),
        Waypoint(id: 'p2', name: "S2·一号避坑洼地", lat: 40.0520, lon: 108.6230, desc: "避开南侧暗坑和流沙"),
        Waypoint(id: 'p3', name: "S3·牧民独家水井", lat: 40.0150, lon: 108.5810, desc: "地下泉水补给点"),
        Waypoint(id: 'p4', name: "S4·大梁刀锋观景台", lat: 39.9820, lon: 108.5240, desc: "沙丘最高脊线，视野极佳"),
        Waypoint(id: 'p5', name: "S5·鸡冠梁背风处", lat: 39.9510, lon: 108.4710, desc: "越野单车易陷区，需匀速通过"),
        Waypoint(id: 'p6', name: "S6·核心沙海扎营地", lat: 39.9130, lon: 108.4120, desc: "背风坡平坦硬质沙面"),
        Waypoint(id: 'p7', name: "S7·沙漠穿沙出口指示桩", lat: 39.8720, lon: 108.3560, desc: "见到高压线铁塔向右切入"),
        Waypoint(id: 'p8', name: "S8·穿沙北线终点国道", lat: 39.8350, lon: 108.3020, desc: "充气与铺装路面恢复"),
      ],
    );

    final badanjilinRoute = Roadbook(
      id: 'rb_badanjilin',
      name: "巴丹吉林沙漠珠峰朝圣线",
      desc: "巴丹吉林入口 ➔ 庙海子营地 ➔ 必鲁图峰登顶点 (高难度攀沙多点连贯导引)",
      arrivalRadiusMeters: 120.0,
      points: [
        Waypoint(id: 'b1', name: "B1·沙漠入口地矿站", lat: 39.4210, lon: 102.2150, desc: "登记与通联频点确认"),
        Waypoint(id: 'b2', name: "B2·宝日陶勒盖鸣沙山", lat: 39.5820, lon: 102.3120, desc: "第一道红沙丘"),
        Waypoint(id: 'b3', name: "B3·音德日图神泉湖", lat: 39.7310, lon: 102.3850, desc: "湖心涌泉，绝佳休整点"),
        Waypoint(id: 'b4', name: "B4·苏敏吉林庙海子", lat: 39.8120, lon: 102.4110, desc: "沙漠故宫与牧民补给营地"),
        Waypoint(id: 'b5', name: "B5·必鲁图峰冲顶底坡", lat: 39.8653, lon: 102.4312, desc: "海拔1611m 世界最高沙峰"),
      ],
    );

    _roadbooks.clear();
    _roadbooks.addAll([kubuqiRoute, badanjilinRoute]);
  }

  /// 本地持久化保存 (同时写入 SharedPreferences 与 本地沙盒文件双重保险)
  Future<void> _saveToLocalDisk() async {
    try {
      final listData = _roadbooks.map((r) => r.toJson()).toList();
      final jsonStr = jsonEncode(listData);

      // 1. 写入 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_roadbooks_v2', jsonStr);
      await prefs.setInt('active_roadbook_index_v2', _activeRoadbookIndex);

      // 2. 写入应用私有物理沙盒文件备用
      final file = _getLocalFile();
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
      }
      debugPrint("路线与航点已成功持久化到本手机本地存储");
    } catch (e) {
      debugPrint("持久化保存异常: $e");
    }
  }

  /// 本地持久化读取
  Future<void> _loadFromLocalDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('saved_roadbooks_v2');

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> raw = jsonDecode(jsonStr);
        final loaded = raw
            .map((item) => Roadbook.fromJson(item as Map<String, dynamic>))
            .toList();

        if (loaded.isNotEmpty) {
          _roadbooks.clear();
          _roadbooks.addAll(loaded);
          _activeRoadbookIndex =
              (prefs.getInt('active_roadbook_index_v2') ?? 0).clamp(0, _roadbooks.length - 1);
          _isLoaded = true;
          notifyListeners();
          return;
        }
      }

      // 尝试从备用私有沙盒文件加载
      final file = _getLocalFile();
      if (file != null && await file.exists()) {
        final fJson = await file.readAsString();
        if (fJson.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(fJson);
          final loaded = raw
              .map((item) => Roadbook.fromJson(item as Map<String, dynamic>))
              .toList();
          if (loaded.isNotEmpty) {
            _roadbooks.clear();
            _roadbooks.addAll(loaded);
            _isLoaded = true;
            notifyListeners();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("从本手机读取持久化路线失败: $e");
    }
  }

  File? _getLocalFile() {
    try {
      final paths = [
        '/data/user/0/com.nmlyzx.gps/files',
        '/data/data/com.nmlyzx.gps/files',
      ];
      for (final p in paths) {
        final d = Directory(p);
        if (d.existsSync()) {
          return File('$p/roadbooks_backup.json');
        }
      }
      final fallbackDir = Directory('/data/data/com.nmlyzx.gps/files');
      if (!fallbackDir.existsSync()) {
        fallbackDir.createSync(recursive: true);
      }
      return File('/data/data/com.nmlyzx.gps/files/roadbooks_backup.json');
    } catch (_) {
      return null;
    }
  }

  void addCustomRoadbook(Roadbook roadbook) => addRoadbookDirect(roadbook);

  /// 合并从云端保险箱拉取的路书列表 (按 id 与名称去重，绝不覆盖本地已有路线)
  Future<int> mergeCloudRoadbooks(List<Roadbook> cloudList) async {
    int added = 0;
    for (final crb in cloudList) {
      final exists = _roadbooks.any((r) => r.id == crb.id || r.name == crb.name);
      if (!exists) {
        _roadbooks.add(crb);
        added++;
      }
    }
    if (added > 0) {
      await _saveToLocalDisk();
      notifyListeners();
    }
    return added;
  }

  void saveRoadbook(Roadbook roadbook) => addRoadbookDirect(roadbook);

  void addRoadbookDirect(Roadbook roadbook) {
    _roadbooks.add(roadbook);
    _activeRoadbookIndex = _roadbooks.length - 1;
    _saveToLocalDisk();
    notifyListeners();
  }

  void selectRoadbook(int index) {
    if (index >= 0 && index < _roadbooks.length) {
      _activeRoadbookIndex = index;
      _saveToLocalDisk();
      notifyListeners();
    }
  }

  void addRoadbook(String name, String desc) {
    final rb = Roadbook(
      id: 'rb_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? '自定义穿越路线' : name.trim(),
      desc: desc.trim(),
    );
    _roadbooks.add(rb);
    _activeRoadbookIndex = _roadbooks.length - 1;
    _saveToLocalDisk();
    notifyListeners();
  }

  bool addPointToActiveRoadbook(Waypoint point) {
    final rb = activeRoadbook;
    if (rb.points.length >= Roadbook.maxPointsLimit) {
      return false; // 上限 200 点
    }
    rb.points.add(point);
    _saveToLocalDisk();
    notifyListeners();
    return true;
  }

  void updatePointInActiveRoadbook(int index, String name, double lat, double lon, String desc) {
    final rb = activeRoadbook;
    if (index >= 0 && index < rb.points.length) {
      rb.points[index].name = name.trim();
      rb.points[index].lat = lat;
      rb.points[index].lon = lon;
      rb.points[index].desc = desc.trim();
      _saveToLocalDisk();
      notifyListeners();
    }
  }

  void removePointFromActiveRoadbook(int index) {
    final rb = activeRoadbook;
    if (index >= 0 && index < rb.points.length && rb.points.length > 1) {
      rb.points.removeAt(index);
      if (rb.currentTargetIndex >= rb.points.length) {
        rb.currentTargetIndex = rb.points.length - 1;
      }
      _saveToLocalDisk();
      notifyListeners();
    }
  }

  void setArrivalRadius(double radius) {
    activeRoadbook.arrivalRadiusMeters = radius;
    _saveToLocalDisk();
    notifyListeners();
  }

  bool nextPoint() {
    final res = activeRoadbook.nextPoint();
    if (res) {
      _saveToLocalDisk();
      notifyListeners();
    }
    return res;
  }

  bool previousPoint() {
    final res = activeRoadbook.previousPoint();
    if (res) {
      _saveToLocalDisk();
      notifyListeners();
    }
    return res;
  }

  bool checkArrivalAndAutoAdvance(double distanceMeters) {
    final res = activeRoadbook.checkAndAutoAdvance(distanceMeters);
    if (res) {
      _saveToLocalDisk();
      notifyListeners();
    }
    return res;
  }
}
