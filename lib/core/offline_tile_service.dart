// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航系统
// 模块名称: 离线切片地图与多级缓存引擎 (Offline Tile Service)
// 文件职责: 
//   1. Slippy Map (Web Mercator) 投影数学计算 (经纬度与像素、瓦片行列号互转)
//   2. 动态多级瓦片缓存 (内存/本地磁盘/网络异步抓取并自动落盘)
//   3. 路线沿线走廊 (Corridor Bounding Box) 离线瓦片批量预下载引擎
//   4. 离线缓存空间统计、清理与纯脱网应急保全
// ==============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/waypoint.dart';
import '../models/roadbook.dart';

/// 地图图层类型
enum MapLayerType {
  topo,      // 户外等高线地形图 (OpenTopoMap)
  satellite, // 高清卫星影像 (ArcGIS Satellite)
  osm,       // 标准街道与道路图 (OpenStreetMap)
}

class OfflineTileService {
  OfflineTileService._internal();
  static final OfflineTileService instance = OfflineTileService._internal();

  /// 本地切片缓存主目录
  Directory? _cacheDir;

  /// 内存中最近访问瓦片缓存 (LRU)
  final Map<String, Uint8List> _memCache = {};
  static const int _maxMemCacheEntries = 120;

  /// 初始化瓦片存储目录
  Future<void> init() async {
    try {
      final candidatePaths = [
        '/data/data/com.nmlyzx.gps/files/offline_tiles',
        '/data/user/0/com.nmlyzx.gps/files/offline_tiles',
      ];

      for (final p in candidatePaths) {
        try {
          final d = Directory(p);
          if (!d.existsSync()) d.createSync(recursive: true);
          _cacheDir = d;
          break;
        } catch (_) {}
      }

      if (_cacheDir == null) {
        final d = Directory.systemTemp.createTempSync('terraway_tiles');
        _cacheDir = d;
      }
    } catch (e) {
      debugPrint("OfflineTileService init warning: $e");
    }
  }

  /// 获取切片文件本地保存路径: {layer}/{z}/{x}/{y}.png
  File _getTileFile(String layer, int z, int x, int y) {
    final basePath = _cacheDir?.path ?? '/data/data/com.nmlyzx.gps/files/offline_tiles';
    return File('$basePath/$layer/$z/$x/$y.png');
  }

  /// 检查切片是否已经缓存在手机本地
  bool isTileCached(String layer, int z, int x, int y) {
    final key = '$layer/$z/$x/$y';
    if (_memCache.containsKey(key)) return true;
    final file = _getTileFile(layer, z, x, y);
    return file.existsSync();
  }

  /// 获取瓦片图片字节流 (优先级: 内存缓存 -> 本地文件缓存 -> 在线网络下载并缓存)
  Future<Uint8List?> getTileBytes(String layer, int z, int x, int y) async {
    final key = '$layer/$z/$x/$y';

    // 1. 内存缓存命中
    if (_memCache.containsKey(key)) {
      return _memCache[key];
    }

    // 2. 本地磁盘缓存命中
    final file = _getTileFile(layer, z, x, y);
    if (file.existsSync()) {
      try {
        final bytes = await file.readAsBytes();
        _putMemCache(key, bytes);
        return bytes;
      } catch (e) {
        debugPrint("读取本地切片失败: $e");
      }
    }

    // 3. 在线下载并异步缓存到本地 (自定位实时下载并缓存)
    try {
      final bytes = await _downloadTileOnline(layer, z, x, y);
      if (bytes != null && bytes.isNotEmpty) {
        _putMemCache(key, bytes);
        // 异步写入磁盘
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(bytes);
        return bytes;
      }
    } catch (e) {
      // 离线无网络时静默处理
    }

    return null;
  }

  void _putMemCache(String key, Uint8List bytes) {
    if (_memCache.length >= _maxMemCacheEntries) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = bytes;
  }

  /// 在线下载瓦片切片
  Future<Uint8List?> _downloadTileOnline(String layer, int z, int x, int y) async {
    String url;
    if (layer == 'satellite') {
      url = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x';
    } else if (layer == 'topo') {
      url = 'https://tile.opentopomap.org/$z/$x/$y.png';
    } else {
      url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'TerraWay-GPS/0.7.8 (Offline Navigation Engine)');
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        return bytes;
      }
    } catch (_) {
      // 离线环境超时忽略
    } finally {
      client.close();
    }
    return null;
  }

  // ============================================================================
  // Web Mercator (EPSG:3857) 投影数学算法
  // ============================================================================

  /// 经度转瓦片 X 坐标
  static int lon2TileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  /// 纬度转瓦片 Y 坐标
  static int lat2TileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * (1 << zoom)).floor();
  }

  /// 瓦片 X 转经度 (度)
  static double tileX2Lon(int x, int zoom) {
    return x / (1 << zoom) * 360.0 - 180.0;
  }

  /// 瓦片 Y 转纬度 (度)
  static double tileY2Lat(int y, int zoom) {
    final n = math.pi - 2.0 * math.pi * y / (1 << zoom);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  /// 经纬度转绝对像素坐标 (基于指定 zoom)
  static math.Point<double> latLonToWorldPixel(double lat, double lon, double zoom) {
    final scale = 256.0 * math.pow(2.0, zoom);
    final x = (lon + 180.0) / 360.0 * scale;
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
    return math.Point<double>(x, y);
  }

  /// 绝对像素坐标转经纬度
  static math.Point<double> worldPixelToLatLon(double px, double py, double zoom) {
    final scale = 256.0 * math.pow(2.0, zoom);
    final lon = px / scale * 360.0 - 180.0;
    final n = math.pi - 2.0 * math.pi * py / scale;
    final lat = 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return math.Point<double>(lat, lon);
  }

  // ============================================================================
  // 路线沿线走廊 (Corridor Bounding Box) 离线瓦片批量预下载
  // ============================================================================

  /// 沿路线走廊批量预下载切片
  Future<void> downloadRouteCorridorTiles({
    required List<Waypoint> waypoints,
    required String layer,
    int minZoom = 10,
    int maxZoom = 14,
    required Function(double progress, int downloaded, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (waypoints.isEmpty) return;

    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;

    for (final wp in waypoints) {
      if (wp.lat < minLat) minLat = wp.lat;
      if (wp.lat > maxLat) maxLat = wp.lat;
      if (wp.lon < minLon) minLon = wp.lon;
      if (wp.lon > maxLon) maxLon = wp.lon;
    }

    // 添加 5 公里左右安全走廊缓冲 (约 0.05 度)
    const buffer = 0.05;
    minLat = (minLat - buffer).clamp(-85.0, 85.0);
    maxLat = (maxLat + buffer).clamp(-85.0, 85.0);
    minLon = (minLon - buffer).clamp(-180.0, 180.0);
    maxLon = (maxLon + buffer).clamp(-180.0, 180.0);

    // 统计所有需要下载的瓦片列表
    final tilesToFetch = <List<int>>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = lon2TileX(minLon, z);
      final maxX = lon2TileX(maxLon, z);
      final minY = lat2TileY(maxLat, z);
      final maxY = lat2TileY(minLat, z);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tilesToFetch.add([z, x, y]);
        }
      }
    }

    final total = tilesToFetch.length;
    int done = 0;

    for (final t in tilesToFetch) {
      if (isCancelled != null && isCancelled()) break;

      final z = t[0];
      final x = t[1];
      final y = t[2];

      // 若已缓存则直接计数
      if (!isTileCached(layer, z, x, y)) {
        await getTileBytes(layer, z, x, y);
      }
      done++;
      onProgress(done / total, done, total);
    }
  }

  /// 获取本地离线切片统计 (总张数与占用空间)
  Future<Map<String, dynamic>> getCacheStats() async {
    int totalCount = 0;
    int totalBytes = 0;

    final dir = _cacheDir;
    if (dir != null && dir.existsSync()) {
      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final e in entities) {
          if (e is File && e.path.endsWith('.png')) {
            totalCount++;
            totalBytes += e.lengthSync();
          }
        }
      } catch (e) {
        debugPrint("获取缓存统计失败: $e");
      }
    }

    final mb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    return {
      'count': totalCount,
      'size_bytes': totalBytes,
      'size_mb': mb,
    };
  }

  /// 一键清空离线切片缓存
  Future<void> clearAllCache() async {
    _memCache.clear();
    final dir = _cacheDir;
    if (dir != null && dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
      } catch (e) {
        debugPrint("清空切片缓存失败: $e");
      }
    }
  }
}
