// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航系统
// 模块名称: 全景脱网多图层交互式地图组件 (Interactive Map View)
// 文件职责:
//   1. 多点手势交互 (单指拖拽平移、双指捏合缩放、双击缩放、平滑惯性)
//   2. 瓦片切片渲染 (动态本地磁盘与网络混合加载、脱网地形网格保底)
//   3. 矢量图层渲染 (规划路书红线、实走航迹蓝线、途经航点兴趣标)
//   4. 自身定位与朝向指示 (基站粗定位光圈、高精卫星点、罗盘/COG车头指向)
//   5. 状态 HUD (比例尺、图层切换、一键回正居中跟踪锁)
// ==============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/offline_tile_service.dart';
import '../core/sensor_fusion.dart';
import '../core/track_recorder_service.dart';
import '../models/roadbook.dart';
import '../models/waypoint.dart';

class InteractiveMapView extends StatefulWidget {
  final NavigationState? navState;
  final bool isDark;

  const InteractiveMapView({
    super.key,
    required this.navState,
    this.isDark = true,
  });

  @override
  State<InteractiveMapView> createState() => _InteractiveMapViewState();
}

class _InteractiveMapViewState extends State<InteractiveMapView> {
  /// 当前地图中心经纬度
  double _centerLat = 39.9042;
  double _centerLon = 116.4074;

  /// 当前缩放级别 (3.0 ~ 18.0)
  double _zoom = 13.0;

  /// 当前所选图层
  String _currentLayer = 'topo'; // topo (等高线) / satellite (卫星) / osm (标准道路)

  /// 是否锁定自定位居中 (点击拖动地图后自动解除锁定，点击居中键恢复锁定)
  bool _lockToUserLocation = true;

  /// 上次手势更新时的缩放和焦点记录
  double _baseZoom = 13.0;
  Offset? _lastFocalPoint;

  /// 瓦片内存缓存 (key: "z_x_y" -> Uint8List)
  final Map<String, Uint8List?> _tileImages = {};

  @override
  void initState() {
    super.initState();
    // 初始化自定位中心点
    final pos = widget.navState?.position;
    if (pos != null && pos.latitude != 0 && pos.longitude != 0) {
      _centerLat = pos.latitude;
      _centerLon = pos.longitude;
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当自定位锁开启且收到新定位时，自动平移镜头
    if (_lockToUserLocation) {
      final pos = widget.navState?.position;
      if (pos != null && pos.latitude != 0 && pos.longitude != 0) {
        if ((_centerLat - pos.latitude).abs() > 0.00005 ||
            (_centerLon - pos.longitude).abs() > 0.00005) {
          _centerLat = pos.latitude;
          _centerLon = pos.longitude;
        }
      }
    }
  }

  /// 居中并重新锁定到自身当前位置
  void _centerToCurrentLocation() {
    final pos = widget.navState?.position;
    if (pos != null && pos.latitude != 0 && pos.longitude != 0) {
      setState(() {
        _centerLat = pos.latitude;
        _centerLon = pos.longitude;
        _lockToUserLocation = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("正在搜星等待定位坐标，暂未锁定位置..."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 手势处理: 开始缩放平移
  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _zoom;
    _lastFocalPoint = details.localFocalPoint;
    // 用户手动拖拽地图时，解除居中跟踪锁定
    if (_lockToUserLocation) {
      setState(() => _lockToUserLocation = false);
    }
  }

  /// 手势处理: 拖动与捏合更新
  void _onScaleUpdate(ScaleUpdateDetails details, Size viewSize) {
    setState(() {
      // 1. 缩放更新
      if (details.scale != 1.0) {
        final newZoom = (_baseZoom + math.log(details.scale) / math.ln2)
            .clamp(3.0, 18.0);
        _zoom = newZoom;
      }

      // 2. 拖拽平移更新
      if (_lastFocalPoint != null) {
        final dx = details.localFocalPoint.dx - _lastFocalPoint!.dx;
        final dy = details.localFocalPoint.dy - _lastFocalPoint!.dy;

        final centerPixel = OfflineTileService.latLonToWorldPixel(_centerLat, _centerLon, _zoom);
        final newPixelX = centerPixel.x - dx;
        final newPixelY = centerPixel.y - dy;

        final newCenter = OfflineTileService.worldPixelToLatLon(newPixelX, newPixelY, _zoom);
        _centerLat = newCenter.x.clamp(-85.0, 85.0);
        _centerLon = (newCenter.y + 180.0) % 360.0 - 180.0;

        _lastFocalPoint = details.localFocalPoint;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
  }

  /// 切换底图图层
  void _switchLayer(String layer) {
    setState(() {
      _currentLayer = layer;
      _tileImages.clear(); // 切换图层时清空视图切片缓存
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: (details) => _onScaleUpdate(details, viewSize),
          onScaleEnd: _onScaleEnd,
          onDoubleTap: () {
            setState(() {
              _zoom = (_zoom + 1.0).clamp(3.0, 18.0);
            });
          },
          child: Stack(
            children: [
              // 1. 底图层: 瓦片网格
              _buildTileLayer(viewSize),

              // 2. 矢量图层: 轨迹、路书、航点与自身定位
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapVectorPainter(
                    centerLat: _centerLat,
                    centerLon: _centerLon,
                    zoom: _zoom,
                    viewSize: viewSize,
                    navState: widget.navState,
                    activeRoadbook: RoadbookStore.instance.activeRoadbook,
                    recordedPoints: TrackRecorderService.instance.currentPoints,
                    isDark: widget.isDark,
                  ),
                ),
              ),

              // 3. 顶部 HUD: 比例尺与当前状态
              Positioned(
                top: 12,
                left: 12,
                child: _buildScaleAndZoomHud(),
              ),

              // 4. 右上角悬浮操作条: 图层选择与回正锁
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  children: [
                    _buildLayerSelector(),
                    const SizedBox(height: 8),
                    _buildLocationTrackingFab(),
                  ],
                ),
              ),

              // 5. 右下侧缩放按钮
              Positioned(
                bottom: 80,
                right: 12,
                child: Column(
                  children: [
                    _buildZoomButton(Icons.add, () {
                      setState(() => _zoom = (_zoom + 1.0).clamp(3.0, 18.0));
                    }),
                    const SizedBox(height: 6),
                    _buildZoomButton(Icons.remove, () {
                      setState(() => _zoom = (_zoom - 1.0).clamp(3.0, 18.0));
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 绘制瓦片层
  Widget _buildTileLayer(Size viewSize) {
    final int z = _zoom.floor().clamp(3, 18);
    final centerWorld = OfflineTileService.latLonToWorldPixel(_centerLat, _centerLon, _zoom);
    final scaleFactor = math.pow(2.0, _zoom - z).toDouble();
    final tileSize = 256.0 * scaleFactor;

    final halfW = viewSize.width / 2;
    final halfH = viewSize.height / 2;

    // 计算视口四角对应的世界坐标
    final leftWorld = centerWorld.x - halfW;
    final rightWorld = centerWorld.x + halfW;
    final topWorld = centerWorld.y - halfH;
    final bottomWorld = centerWorld.y + halfH;

    final zScale = 256.0 * math.pow(2.0, z);
    final minTileX = (leftWorld / zScale * (1 << z)).floor();
    final maxTileX = (rightWorld / zScale * (1 << z)).floor();
    final minTileY = (topWorld / zScale * (1 << z)).floor();
    final maxTileY = (bottomWorld / zScale * (1 << z)).floor();

    final maxTileIndex = (1 << z) - 1;
    final tileWidgets = <Widget>[];

    for (int tx = minTileX; tx <= maxTileX; tx++) {
      for (int ty = minTileY; ty <= maxTileY; ty++) {
        final wrappedX = (tx % (1 << z) + (1 << z)) % (1 << z);
        if (ty < 0 || ty > maxTileIndex) continue;

        // 计算该瓦片在屏幕上的绝对偏移
        final tileWorldX = (tx * 256.0) * scaleFactor;
        final tileWorldY = (ty * 256.0) * scaleFactor;

        final screenX = tileWorldX - (centerWorld.x - halfW);
        final screenY = tileWorldY - (centerWorld.y - halfH);

        tileWidgets.add(
          Positioned(
            left: screenX,
            top: screenY,
            width: tileSize + 0.5,
            height: tileSize + 0.5,
            child: _TileItemWidget(
              layer: _currentLayer,
              z: z,
              x: wrappedX,
              y: ty,
              isDark: widget.isDark,
            ),
          ),
        );
      }
    }

    return Container(
      color: widget.isDark ? const Color(0xFF0D1117) : const Color(0xFFE5E7EB),
      child: Stack(children: tileWidgets),
    );
  }

  /// 比例尺与 Zoom 显示
  Widget _buildScaleAndZoomHud() {
    final scaleDistMeters = (1000.0 / math.pow(2, _zoom - 10)).clamp(50.0, 50000.0);
    String distText = scaleDistMeters >= 1000
        ? "${(scaleDistMeters / 1000).toStringAsFixed(1)} km"
        : "${scaleDistMeters.toInt()} m";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 3,
            color: const Color(0xFF00FF66),
          ),
          const SizedBox(width: 6),
          Text(
            "$distText · Z${_zoom.toStringAsFixed(1)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 图层切换菜单
  Widget _buildLayerSelector() {
    return PopupMenuButton<String>(
      onSelected: _switchLayer,
      color: const Color(0xFF161616),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF333333)),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'topo',
          child: Row(
            children: [
              Icon(Icons.terrain, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text("🏔️ 户外等高线 (Topo)", style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'satellite',
          child: Row(
            children: [
              Icon(Icons.satellite, color: Colors.cyan, size: 18),
              SizedBox(width: 8),
              Text("🛰️ 卫星影像 (Satellite)", style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'osm',
          child: Row(
            children: [
              Icon(Icons.map, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text("🗺️ 标准道路 (OSM)", style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: const Icon(Icons.layers_outlined, color: Colors.white, size: 20),
      ),
    );
  }

  /// 居中跟踪锁定按钮
  Widget _buildLocationTrackingFab() {
    return InkWell(
      onTap: _centerToCurrentLocation,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _lockToUserLocation
              ? const Color(0xFF003311)
              : Colors.black.withOpacity(0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: _lockToUserLocation
                ? const Color(0xFF00FF66)
                : const Color(0xFF333333),
            width: 1.5,
          ),
        ),
        child: Icon(
          _lockToUserLocation ? Icons.my_location : Icons.location_searching,
          color: _lockToUserLocation ? const Color(0xFF00FF66) : Colors.white70,
          size: 20,
        ),
      ),
    );
  }

  /// 缩放微调按钮
  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// 单个瓦片展示与自动加载组件
class _TileItemWidget extends StatefulWidget {
  final String layer;
  final int z;
  final int x;
  final int y;
  final bool isDark;

  const _TileItemWidget({
    required this.layer,
    required this.z,
    required this.x,
    required this.y,
    required this.isDark,
  });

  @override
  State<_TileItemWidget> createState() => _TileItemWidgetState();
}

class _TileItemWidgetState extends State<_TileItemWidget> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadTile();
  }

  @override
  void didUpdateWidget(covariant _TileItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer != widget.layer ||
        oldWidget.z != widget.z ||
        oldWidget.x != widget.x ||
        oldWidget.y != widget.y) {
      _loadTile();
    }
  }

  Future<void> _loadTile() async {
    final b = await OfflineTileService.instance.getTileBytes(
      widget.layer,
      widget.z,
      widget.x,
      widget.y,
    );
    if (mounted) {
      setState(() => _bytes = b);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      );
    }

    // 脱网未缓存保底: 极简等高线/网格背景
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF141922) : const Color(0xFFF3F4F6),
        border: Border.all(
          color: widget.isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          "${widget.z}/${widget.x}/${widget.y}",
          style: TextStyle(
            color: widget.isDark ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// 地图矢量图层绘制器 (轨迹、路书、航点与自身定位)
class _MapVectorPainter extends CustomPainter {
  final double centerLat;
  final double centerLon;
  final double zoom;
  final Size viewSize;
  final NavigationState? navState;
  final Roadbook? activeRoadbook;
  final List<dynamic>? recordedPoints;
  final bool isDark;

  _MapVectorPainter({
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.viewSize,
    required this.navState,
    required this.activeRoadbook,
    required this.recordedPoints,
    required this.isDark,
  });

  /// 经纬度转屏幕坐标
  Offset _toScreenOffset(double lat, double lon) {
    final centerWorld = OfflineTileService.latLonToWorldPixel(centerLat, centerLon, zoom);
    final targetWorld = OfflineTileService.latLonToWorldPixel(lat, lon, zoom);

    final screenX = (targetWorld.x - centerWorld.x) + (viewSize.width / 2);
    final screenY = (targetWorld.y - centerWorld.y) + (viewSize.height / 2);
    return Offset(screenX, screenY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制规划路书线 (激活路线: 橙红高亮带光晕)
    if (activeRoadbook != null && activeRoadbook!.waypoints.isNotEmpty) {
      final wpts = activeRoadbook!.waypoints;
      final path = Path();
      for (int i = 0; i < wpts.length; i++) {
        final offset = _toScreenOffset(wpts[i].lat, wpts[i].lon);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }

      // 底层光晕
      final glowPaint = Paint()
        ..color = Colors.deepOrangeAccent.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, glowPaint);

      // 主线
      final rbPaint = Paint()
        ..color = const Color(0xFFFF5500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, rbPaint);

      // 绘制路书航点 Marker
      for (int i = 0; i < wpts.length; i++) {
        final wp = wpts[i];
        final offset = _toScreenOffset(wp.lat, wp.lon);
        if (offset.dx >= -20 && offset.dx <= size.width + 20 &&
            offset.dy >= -20 && offset.dy <= size.height + 20) {
          _drawWaypointMarker(canvas, offset, wp, i, wpts.length);
        }
      }
    }

    // 2. 绘制实走录制轨迹线 (青蓝高亮)
    if (recordedPoints != null && recordedPoints!.isNotEmpty) {
      final trkPath = Path();
      bool first = true;
      for (final p in recordedPoints!) {
        final lat = p.lat is double ? p.lat as double : (p.lat as num).toDouble();
        final lon = p.lon is double ? p.lon as double : (p.lon as num).toDouble();
        final offset = _toScreenOffset(lat, lon);
        if (first) {
          trkPath.moveTo(offset.dx, offset.dy);
          first = false;
        } else {
          trkPath.lineTo(offset.dx, offset.dy);
        }
      }

      final trkPaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(trkPath, trkPaint);
    }

    // 3. 绘制自身定位 (基站粗定位光圈 + 卫星高精点 + 车头朝向箭头)
    final pos = navState?.position;
    if (pos != null && pos.latitude != 0 && pos.longitude != 0) {
      final userOffset = _toScreenOffset(pos.latitude, pos.longitude);

      // (1) 基站/网络粗定位精度圈 (当精度 > 15m 时渲染半透明蓝圈)
      final accuracy = pos.accuracy;
      if (accuracy > 15.0) {
        final metersPerPixel = (156543.03392 * math.cos(pos.latitude * math.pi / 180) / math.pow(2, zoom));
        final radiusPixels = (accuracy / metersPerPixel).clamp(12.0, 180.0);

        final circlePaint = Paint()
          ..color = const Color(0xFF38BDF8).withOpacity(0.18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(userOffset, radiusPixels, circlePaint);

        final circleBorder = Paint()
          ..color = const Color(0xFF38BDF8).withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(userOffset, radiusPixels, circleBorder);
      }

      // (2) 高精度自身点 (绿色外环 + 脉动光圈)
      final outerGlow = Paint()
        ..color = const Color(0xFF00FF66).withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, 12, outerGlow);

      final innerDot = Paint()
        ..color = const Color(0xFF00FF66)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, 6, innerDot);

      final whiteCore = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, 2.5, whiteCore);

      // (3) 车头朝向指针 (根据 Heading 旋转三角形)
      final heading = navState?.smoothedHeading ?? 0.0;
      _drawHeadingCone(canvas, userOffset, heading);
    }
  }

  /// 绘制车头航向锥形/箭头
  void _drawHeadingCone(Canvas canvas, Offset center, double headingDeg) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(headingDeg * math.pi / 180.0);

    // 绘制车头朝向航向扇面
    final conePath = Path()
      ..moveTo(0, -22) // 箭头尖端
      ..lineTo(8, -8)
      ..lineTo(0, -12)
      ..lineTo(-8, -8)
      ..close();

    final conePaint = Paint()
      ..color = const Color(0xFF00FF66)
      ..style = PaintingStyle.fill;
    canvas.drawPath(conePath, conePaint);

    canvas.restore();
  }

  /// 绘制路书航点 Marker
  void _drawWaypointMarker(Canvas canvas, Offset offset, Waypoint wp, int index, int total) {
    Color pinColor = Colors.orange;
    String label = "${index + 1}";
    if (index == 0) {
      pinColor = const Color(0xFF00FF66);
      label = "起";
    } else if (index == total - 1) {
      pinColor = const Color(0xFFFF3333);
      label = "终";
    }

    // 绘制带阴影图钉
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.5);
    canvas.drawCircle(offset.translate(1, 2), 9, shadowPaint);

    final pinPaint = Paint()..color = pinColor;
    canvas.drawCircle(offset, 8, pinPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(offset, 8, borderPaint);

    // 文字标注
    final textSpan = TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(offset.dx - textPainter.width / 2, offset.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MapVectorPainter oldDelegate) {
    return oldDelegate.centerLat != centerLat ||
        oldDelegate.centerLon != centerLon ||
        oldDelegate.zoom != zoom ||
        oldDelegate.navState?.position != navState?.position ||
        oldDelegate.navState?.smoothedHeading != navState?.smoothedHeading ||
        oldDelegate.activeRoadbook != activeRoadbook ||
        oldDelegate.recordedPoints?.length != recordedPoints?.length;
  }
}
