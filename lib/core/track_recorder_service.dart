// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 导航轨迹同步录制与持久化仓储服务 (Track Recorder Service)
// 文件职责: 开始导航时同步启动轨迹记录，结束导航时提示保存或丢弃
//          保存后永久存储于本手机历史库中，后续在地图模式下呈现线路图，联网版可上传账户
// ==============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'math_utils.dart';
import 'navigation_mode.dart';
import '../models/track.dart';

/// 全局户外轨迹同步录制与持久化仓储服务 (单例模式)
class TrackRecorderService with ChangeNotifier {
  static final TrackRecorderService instance = TrackRecorderService._internal();
  factory TrackRecorderService() => instance;
  TrackRecorderService._internal() {
    _initStorage();
  }

  Track? _activeTrack;
  Timer? _durationTimer;
  StreamSubscription<Position>? _positionSub;

  DateTime? _lastSampleTime;
  double? _lastRecordedLat;
  double? _lastRecordedLon;
  double? _lastHeading;

  // 高程平滑滑动窗口 (5点中值滤波)
  final List<double> _altitudeWindow = [];

  final List<Track> _savedTracks = [];
  bool _isStoreLoaded = false;

  Track? get activeTrack => _activeTrack;
  bool get isRecording => _activeTrack != null && _activeTrack!.isRecording;
  List<Track> get savedTracks => List.unmodifiable(_savedTracks);
  double get currentRecordedDistanceMeters => _activeTrack?.totalDistanceMeters ?? 0.0;
  int get currentPointCount => _activeTrack?.points.length ?? 0;

  /// 启动时载入本地历史轨迹库，并清空上次未保存的临时草稿
  Future<void> _initStorage() async {
    await _loadSavedTracks();
    // 规则：如果不保存，下次打开就没有了（清空上次未主动保存的残留）
    await _deleteTempFile();
    _activeTrack = null;
    notifyListeners();
  }

  /// 开始导航时同步启动轨迹记录 (由 DashboardScreen 启动时调用)
  
  /// 开启无导航自由盲走轨迹录制 (用户不加载路书、随性越野或徒步漫步)
  Future<void> startFreeRecording({OutdoorSportMode? mode, String? customName}) async {
    final navMode = mode ?? NavigationModeController.instance.currentMode;
    final now = DateTime.now();
    final defaultTitle = "自由轨迹_${DateFormat('MMdd_HHmm').format(now)}";
    await startNavigationRecording(mode: navMode, customName: customName ?? defaultTitle);
  }

  /// 结束自由盲走录制并返回完整轨迹实体
    /// 结束并保存当前轨迹
  Future<Track?> stopAndSaveTrack({String? name}) async => saveCurrentSession(name: name);

Future<Track?> stopFreeRecording() async {
    return saveCurrentSession();
  }

  Future<void> startNavigationRecording({OutdoorSportMode? mode, String? customName}) async {
    // 若当前已在记录同一会话则不重复初始化
    if (_activeTrack != null && _activeTrack!.isRecording) return;

    final navMode = mode ?? NavigationModeController.instance.currentMode;
    final now = DateTime.now();
    final defaultTitle = "导航轨迹_${DateFormat('MMdd_HHmm').format(now)}";

    _activeTrack = Track(
      id: 'trk_${now.millisecondsSinceEpoch}',
      name: customName?.trim().isNotEmpty == true ? customName!.trim() : defaultTitle,
      mode: navMode,
      startTime: now,
      isRecording: true,
      isPaused: false,
      isSynced: false,
    );

    _lastSampleTime = null;
    _lastRecordedLat = null;
    _lastRecordedLon = null;
    _lastHeading = null;
    _altitudeWindow.clear();

    // 开启秒级计时器
    _startDurationTimer();

    // 监听 GPS 高精度位置流
    _startGpsListener();

    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeTrack != null && !_activeTrack!.isPaused) {
        _activeTrack!.totalDuration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }

  void _startGpsListener() {
    _positionSub?.cancel();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // 移动 2 米触发位置流
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (err) {
        debugPrint("导航轨迹记录 GPS 监听异常: $err");
      },
    );
  }

  /// 核心防漂移与自适应采样过滤算法
  void _onPositionUpdate(Position position) {
    if (_activeTrack == null || _activeTrack!.isPaused || !_activeTrack!.isRecording) return;

    final now = DateTime.now();
    final profile = NavigationModeProfile.profiles[_activeTrack!.mode]!;

    final lat = position.latitude;
    final lon = position.longitude;
    final speedKmh = math.max(0.0, position.speed * 3.6);
    final altitude = position.altitude;
    final heading = position.heading >= 0 ? position.heading : (_lastHeading ?? 0.0);
    final accuracy = position.accuracy;

    // 1. 高精度 5 点中值滤波平滑海拔
    _altitudeWindow.add(altitude);
    if (_altitudeWindow.length > 5) _altitudeWindow.removeAt(0);
    final smoothAlt = _calculateMedianAltitude();

    if (_lastRecordedLat != null && _lastRecordedLon != null) {
      final distanceMoved = MathUtils.haversineDistance(
        _lastRecordedLat!,
        _lastRecordedLon!,
        lat,
        lon,
      );

      // 2. 原地驻车/静止死区过滤 (速度过低且未发生实质位移强制丢弃，防止驻车乱晃)
      if (speedKmh < profile.deadbandSpeedKmh && distanceMoved < profile.deadbandDistanceMeters) {
        return;
      }

      // 3. 动态触发条件：时间间隔达到 或 位移达到 或 航向突变(>15°)
      final timeSinceLast = _lastSampleTime != null
          ? now.difference(_lastSampleTime!).inSeconds
          : 999;
      final headingDiff = _lastHeading != null
          ? ((heading - _lastHeading!).abs() % 360)
          : 0.0;
      final bool isSignificantTurn = headingDiff > 15.0 && headingDiff < 345.0 && distanceMoved > 5.0;

      final bool shouldRecord = distanceMoved >= profile.trackSamplingDistanceMeters ||
          timeSinceLast >= profile.trackSamplingIntervalSeconds ||
          isSignificantTurn;

      if (!shouldRecord) return;

      // 4. 统计更新
      _activeTrack!.totalDistanceMeters += distanceMoved;
      _activeTrack!.movingDuration += Duration(seconds: math.max(1, timeSinceLast));

      // 累计爬升与累计下降
      final altDiff = smoothAlt - _activeTrack!.points.last.altitude;
      if (altDiff > 1.5) {
        _activeTrack!.totalAscent += altDiff;
      } else if (altDiff < -1.5) {
        _activeTrack!.totalDescent += altDiff.abs();
      }
    } else {
      _activeTrack!.minAltitude = smoothAlt;
      _activeTrack!.maxAltitude = smoothAlt;
    }

    if (speedKmh > _activeTrack!.maxSpeedKmh) {
      _activeTrack!.maxSpeedKmh = speedKmh;
    }
    if (smoothAlt < _activeTrack!.minAltitude) {
      _activeTrack!.minAltitude = smoothAlt;
    }
    if (smoothAlt > _activeTrack!.maxAltitude) {
      _activeTrack!.maxAltitude = smoothAlt;
    }

    if (_activeTrack!.movingDuration.inSeconds > 0) {
      final hours = _activeTrack!.movingDuration.inSeconds / 3600.0;
      _activeTrack!.avgSpeedKmh = (_activeTrack!.totalDistanceMeters / 1000.0) / hours;
    }

    final newPoint = TrackPoint(
      lat: lat,
      lon: lon,
      altitude: smoothAlt,
      speedKmh: speedKmh,
      heading: heading,
      time: now,
      accuracy: accuracy,
    );

    _activeTrack!.points.add(newPoint);
    _lastRecordedLat = lat;
    _lastRecordedLon = lon;
    _lastSampleTime = now;
    _lastHeading = heading;

    notifyListeners();
  }

  double _calculateMedianAltitude() {
    if (_altitudeWindow.isEmpty) return 0.0;
    final sorted = List<double>.from(_altitudeWindow)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
  }

  /// 结束导航行程：选择【保存】（永久保存至本手机历史库，后续地图可加载线路图，联网可同步账户）
  Future<Track?> saveCurrentSession({String? name}) async {
    if (_activeTrack == null) return null;

    _durationTimer?.cancel();
    _positionSub?.cancel();

    final finished = _activeTrack!;
    finished.endTime = DateTime.now();
    finished.isRecording = false;
    finished.isPaused = false;
    finished.isSynced = false; // 初始未同步，留待后续联网版上传账户

    if (name != null && name.trim().isNotEmpty) {
      finished.name = name.trim();
    }

    // 仅当实际产生有效航迹点时才入库
    if (finished.points.isNotEmpty) {
      _savedTracks.insert(0, finished);
      await _saveTracksToDisk();
    }

    await _deleteTempFile();
    _activeTrack = null;

    notifyListeners();
    return finished;
  }

  /// 结束导航行程：选择【不保存】（立即丢弃，下次打开绝无残留）
  Future<void> discardCurrentSession() async {
    _durationTimer?.cancel();
    _positionSub?.cancel();
    await _deleteTempFile();
    _activeTrack = null;
    notifyListeners();
  }

  /// 途经重要路标现场打点 (POI Marker)
  void addPoiMarker(String markerName, String desc) {
    if (_activeTrack == null || _activeTrack!.points.isEmpty) return;
    final last = _activeTrack!.points.last;
    final poi = TrackPoint(
      lat: last.lat,
      lon: last.lon,
      altitude: last.altitude,
      speedKmh: last.speedKmh,
      heading: last.heading,
      time: DateTime.now(),
      accuracy: last.accuracy,
    );
    _activeTrack!.points.add(poi);
    notifyListeners();
  }

  /// 删除某条已存历史轨迹
  Future<void> deleteTrack(String id) async {
    _savedTracks.removeWhere((t) => t.id == id);
    await _saveTracksToDisk();
    notifyListeners();
  }

  /// 合并从云端保险箱恢复的历史轨迹列表 (按 id 去重，绝不丢失本地轨迹)
  Future<int> mergeCloudTracks(List<Track> cloudTracks) async {
    int added = 0;
    for (final ct in cloudTracks) {
      final exists = _savedTracks.any((t) => t.id == ct.id);
      if (!exists) {
        ct.isSynced = true;
        _savedTracks.add(ct);
        added++;
      }
    }
    if (added > 0) {
      _savedTracks.sort((a, b) => b.startTime.compareTo(a.startTime));
      await _saveTracksToDisk();
      notifyListeners();
    }
    return added;
  }

  /// 更新轨迹名称 (别名方法)
  Future<void> updateTrackName(String id, String newName) => renameTrack(id, newName);

  /// 重命名某条已存历史轨迹
  Future<void> renameTrack(String id, String newName) async {
    final idx = _savedTracks.indexWhere((t) => t.id == id);
    if (idx != -1 && newName.trim().isNotEmpty) {
      _savedTracks[idx].name = newName.trim();
      await _saveTracksToDisk();
      notifyListeners();
    }
  }

  // ================= 历史轨迹库物理持久化 (永久存储于本机) =================

  Future<void> _saveTracksToDisk() async {
    try {
      final list = _savedTracks.map((t) => t.toJson()).toList();
      final jsonStr = jsonEncode(list);

      // 1. SharedPreferences 主存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('terraway_saved_tracks_v1', jsonStr);

      // 2. 本机私有物理沙盒 JSON 双重持久化
      final file = _getLibraryFile();
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
      }
      debugPrint("轨迹已永久保存至本手机存储: 数量 ${_savedTracks.length}");
    } catch (e) {
      debugPrint("轨迹库持久化异常: $e");
    }
  }

  Future<void> _loadSavedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('terraway_saved_tracks_v1');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> raw = jsonDecode(jsonStr);
        _savedTracks.clear();
        _savedTracks.addAll(raw.map((m) => Track.fromJson(m as Map<String, dynamic>)));
        _isStoreLoaded = true;
        notifyListeners();
        return;
      }

      final file = _getLibraryFile();
      if (file != null && await file.exists()) {
        final fJson = await file.readAsString();
        if (fJson.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(fJson);
          _savedTracks.clear();
          _savedTracks.addAll(raw.map((m) => Track.fromJson(m as Map<String, dynamic>)));
          _isStoreLoaded = true;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("读取历史轨迹库失败: $e");
    }
  }

  Future<void> _deleteTempFile() async {
    try {
      final paths = [
        '/data/user/0/com.nmlyzx.gps/files/active_track_temp.jsonl',
        '/data/data/com.nmlyzx.gps/files/active_track_temp.jsonl',
      ];
      for (final p in paths) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  File? _getLibraryFile() {
    try {
      final paths = [
        '/data/user/0/com.nmlyzx.gps/files',
        '/data/data/com.nmlyzx.gps/files',
      ];
      for (final p in paths) {
        final d = Directory(p);
        if (d.existsSync()) return File('$p/tracks_library_v1.json');
      }
      return File('/data/data/com.nmlyzx.gps/files/tracks_library_v1.json');
    } catch (_) {
      return null;
    }
  }
}
