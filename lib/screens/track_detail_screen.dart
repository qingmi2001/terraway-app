// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 轨迹全貌地图与多功能详情页面 (Track Detail & Vector Map Screen)
// 文件职责: 
// 1. 离线纯矢量渲染轨迹全貌路线图 (包含起终点标、行进方向标、经纬度拓扑网格与罗盘)；
// 2. 呈现全程海拔剖面起伏曲线与全要素遥测统计矩阵；
// 3. 提供一键原路反向循迹返航、转正向路书、标准 GPX 1.1 导出与云端备份等标准操作。
// ==============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../core/locale_controller.dart';
import '../core/navigation_mode.dart';
import '../core/app_style.dart';
import '../core/track_recorder_service.dart';
import '../core/cloud_sync_service.dart';
import '../models/roadbook.dart';
import '../models/track.dart';
import 'dashboard_screen.dart';

class TrackDetailScreen extends StatefulWidget {
  final Track track;
  const TrackDetailScreen({super.key, required this.track});

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  final TrackRecorderService _recorder = TrackRecorderService.instance;
  final RoadbookStore _roadbookStore = RoadbookStore.instance;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = widget.track;
    final profile = NavigationModeProfile.profiles[track.mode]!;

    final distKm = (track.totalDistanceMeters / 1000.0).toStringAsFixed(2);
    final movingHours = track.movingDuration.inHours;
    final movingMins = track.movingDuration.inMinutes % 60;
    final movingSecs = track.movingDuration.inSeconds % 60;
    final durationStr = movingHours > 0
        ? "${movingHours}h ${movingMins}m"
        : "${movingMins}m ${movingSecs}s";

    final totalHours = track.totalDuration.inHours;
    final totalMins = track.totalDuration.inMinutes % 60;
    final totalDurationStr = totalHours > 0
        ? "${totalHours}h ${totalMins}m"
        : "${totalMins}m ${track.totalDuration.inSeconds % 60}s";

    return Scaffold(
      appBar: AppBar(
        title: Text(
          track.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, size: 22),
            tooltip: I18n.isZh ? "重命名" : "Rename",
            onPressed: () => _showRenameDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
            tooltip: I18n.isZh ? "删除轨迹" : "Delete",
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 离线航迹全貌矢量地图渲染卡片 (Vector Track Map)
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0A0E14) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: TrackMapPainter(
                              points: track.points,
                              isDark: isDark,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withOpacity(0.75)
                                  : Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(profile.icon, size: 13, color: AppStyle.primaryGreen(isDark)),
                                const SizedBox(width: 4),
                                Text(
                                  "${profile.name} · ${track.points.length} 采样点",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withOpacity(0.75)
                                  : Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.navigation, size: 12, color: Colors.redAccent),
                                const SizedBox(width: 2),
                                Text(
                                  "正北 (N)",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 10,
                          child: Text(
                            "WGS-84 纯离线矢量拓扑",
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2. 海拔剖面起伏曲线 (Elevation Profile Visualizer)
                  if (track.points.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: AppStyle.cardDecoration(isDark: isDark),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "全程海拔高程剖面",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              Text(
                                "最高 ${track.maxAltitude.toStringAsFixed(0)}m / 最低 ${track.minAltitude.toStringAsFixed(0)}m",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppStyle.telemetryColor(isDark),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 60,
                            child: CustomPaint(
                              painter: ElevationProfilePainter(
                                points: track.points,
                                minAlt: track.minAltitude,
                                maxAlt: track.maxAltitude,
                                isDark: isDark,
                              ),
                              child: Container(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 3. 全要素遥测数据统计网格 (4x2 Grid Metrics)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: AppStyle.cardDecoration(isDark: isDark),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "行程关键遥测统计",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.phone_android, size: 10, color: AppStyle.primaryGreen(isDark)),
                                  const SizedBox(width: 3),
                                  Text(
                                    track.isSynced ? I18n.cloudSyncedBadge : I18n.localSavedBadge,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppStyle.primaryGreen(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GridView.count(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 1.25,
                          children: [
                            _buildStatBox("总里程", "$distKm km", isDark, highlight: true),
                            _buildStatBox("运动用时", durationStr, isDark),
                            _buildStatBox("平均时速", "${track.avgSpeedKmh.toStringAsFixed(1)} km/h", isDark),
                            _buildStatBox("最高时速", "${track.maxSpeedKmh.toStringAsFixed(1)} km/h", isDark),
                            _buildStatBox("累计拔高", "+${track.totalAscent.toStringAsFixed(0)} m", isDark),
                            _buildStatBox("累计下降", "-${track.totalDescent.toStringAsFixed(0)} m", isDark),
                            _buildStatBox("全程耗时", totalDurationStr, isDark),
                            _buildStatBox("航迹点数", "${track.points.length} 点", isDark),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 16, color: Theme.of(context).dividerColor),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "采集起止时间",
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                            ),
                            Text(
                              "${DateFormat('yyyy-MM-dd HH:mm').format(track.startTime)} ~ ${track.endTime != null ? DateFormat('HH:mm').format(track.endTime!) : '完成'}",
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // 4. 底部标准操作按钮区 (返航、转路书、导出、上传)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF080808) : Colors.white,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 36,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.replay, size: 16),
                    label: Text(
                      I18n.retraceBtnShort,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _launchRetraceNav(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 24,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _convertToStandardRoadbook(context),
                    child: Text(
                      I18n.roadbookBtnShort,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 20,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _exportGpx(context),
                    child: Text(
                      I18n.exportBtnShort,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 20,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        width: 1.2,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _showUploadDialog(context, isDark),
                    child: Text(
                      I18n.uploadBtnShort,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, bool isDark, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight
              ? (isDark ? const Color(0xFF00FF66).withOpacity(0.4) : const Color(0xFF008833).withOpacity(0.4))
              : (isDark ? const Color(0xFF222222) : const Color(0xFFE2E4E8)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: highlight
                  ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                  : (isDark ? Colors.white : Colors.black87),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  void _launchRetraceNav(BuildContext context) {
    final track = widget.track;
    if (track.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("当前轨迹无采样点，无法生成返程路书")),
      );
      return;
    }

    final retraceRoadbook = track.toRoadbook(reverse: true);
    _roadbookStore.addCustomRoadbook(retraceRoadbook);
    final idx = _roadbookStore.roadbooks.indexOf(retraceRoadbook);
    if (idx != -1) {
      _roadbookStore.selectRoadbook(idx);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.retraceLaunchedToast),
        backgroundColor: const Color(0xFF00AA44),
        duration: const Duration(seconds: 3),
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => const DashboardScreen()),
    );
  }

  void _convertToStandardRoadbook(BuildContext context) {
    final track = widget.track;
    if (track.points.isEmpty) return;

    final rb = track.toRoadbook(reverse: false);
    _roadbookStore.addCustomRoadbook(rb);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("已成功将轨迹转换为穿越路书：【${rb.name}】！可在路线列表中查看。"),
        backgroundColor: const Color(0xFF00AA44),
      ),
    );
  }

  void _exportGpx(BuildContext context) {
    final gpxXml = widget.track.toGpxXml();
    Clipboard.setData(ClipboardData(text: gpxXml));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.trackExportSuccess),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF00AA44),
      ),
    );
  }

  void _showUploadDialog(BuildContext context, bool isDark) {
    final cloud = CloudSyncService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            const Icon(Icons.cloud_upload_outlined, color: Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(I18n.uploadCloudTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          cloud.isLoggedIn
              ? "${I18n.uploadCloudDesc}\n\n当前云端账户：${cloud.userNickname}"
              : "${I18n.uploadCloudDesc}\n\n提示：尚未登录云端账户，点击下方按钮可先标记本机待同步，或在首页右上角探险者头像中登录云端保险箱。",
          style: TextStyle(fontSize: 13, height: 1.5, color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (cloud.isLoggedIn) {
                final res = await cloud.syncTracksToCloud(singleTrack: widget.track);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.message)),
                  );
                }
              } else {
                setState(() {
                  widget.track.isSynced = true;
                });
                await _recorder.updateTrackName(widget.track.id, widget.track.name);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("已标记为待云端备份，连接云端保险箱后将自动同步")),
                  );
                }
              }
            },
            child: Text(cloud.isLoggedIn ? "立即上传备份" : "标记待同步"),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.track.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.isZh ? "重命名轨迹" : "Rename Track"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: I18n.isZh ? "轨迹名称" : "Track Name",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(I18n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                await _recorder.updateTrackName(widget.track.id, newName);
                setState(() => widget.track.name = newName);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(I18n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.isZh ? "删除此轨迹？" : "Delete Track?"),
        content: Text(
          I18n.isZh
              ? "确定删除【${widget.track.name}】吗？删除后手机本地历史数据将永久清空，无法找回。"
              : "Delete \"${widget.track.name}\"? Local data cannot be recovered.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(I18n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _recorder.deleteTrack(widget.track.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(I18n.isZh ? "确认删除" : "Delete"),
          ),
        ],
      ),
    );
  }
}

class TrackMapPainter extends CustomPainter {
  final List<TrackPoint> points;
  final bool isDark;

  TrackMapPainter({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF161F2E) : const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(w * i / 4, 0), Offset(w * i / 4, h), gridPaint);
      canvas.drawLine(Offset(0, h * i / 4), Offset(w, h * i / 4), gridPaint);
    }

    if (points.isEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: "暂无记录坐标点",
          style: TextStyle(color: isDark ? Colors.white30 : Colors.black26, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2));
      return;
    }

    double minLat = points.first.lat;
    double maxLat = points.first.lat;
    double minLon = points.first.lon;
    double maxLon = points.first.lon;

    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    final latSpan = math.max(0.0005, maxLat - minLat);
    final lonSpan = math.max(0.0005, maxLon - minLon);

    const pad = 24.0;
    final usableW = w - pad * 2;
    final usableH = h - pad * 2;

    final scale = math.min(usableW / lonSpan, usableH / latSpan);
    final offsetX = pad + (usableW - lonSpan * scale) / 2;
    final offsetY = pad + (usableH - latSpan * scale) / 2;

    Offset toPixel(double lat, double lon) {
      final x = offsetX + (lon - minLon) * scale;
      final y = offsetY + (maxLat - lat) * scale;
      return Offset(x, y);
    }

    final path = Path();
    final firstPixel = toPixel(points.first.lat, points.first.lon);
    path.moveTo(firstPixel.dx, firstPixel.dy);

    for (int i = 1; i < points.length; i++) {
      final pix = toPixel(points[i].lat, points[i].lon);
      path.lineTo(pix.dx, pix.dy);
    }

    final shadowPaint = Paint()
      ..color = (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)).withOpacity(0.3)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, shadowPaint);

    final trackPaint = Paint()
      ..color = isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, trackPaint);

    if (points.length >= 8) {
      final arrowPaint = Paint()
        ..color = isDark ? Colors.black : Colors.white
        ..style = PaintingStyle.fill;
      final arrowBorder = Paint()
        ..color = isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      for (int i = (points.length * 0.25).round(); i < points.length; i += (points.length * 0.25).round()) {
        final p0 = toPixel(points[i - 1].lat, points[i - 1].lon);
        final p1 = toPixel(points[i].lat, points[i].lon);
        final angle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);

        canvas.save();
        canvas.translate(p1.dx, p1.dy);
        canvas.rotate(angle);

        final arrowPath = Path()
          ..moveTo(6, 0)
          ..lineTo(-4, -4)
          ..lineTo(-2, 0)
          ..lineTo(-4, 4)
          ..close();
        canvas.drawPath(arrowPath, arrowPaint);
        canvas.drawPath(arrowPath, arrowBorder);
        canvas.restore();
      }
    }

    final startPixel = toPixel(points.first.lat, points.first.lon);
    canvas.drawCircle(startPixel, 8, Paint()..color = const Color(0xFF00FF66));
    canvas.drawCircle(startPixel, 8, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawCircle(startPixel, 3, Paint()..color = Colors.black);

    final endPixel = toPixel(points.last.lat, points.last.lon);
    canvas.drawCircle(endPixel, 8, Paint()..color = const Color(0xFFFF3333));
    canvas.drawCircle(endPixel, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawCircle(endPixel, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant TrackMapPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.isDark != isDark;
}

class ElevationProfilePainter extends CustomPainter {
  final List<TrackPoint> points;
  final double minAlt;
  final double maxAlt;
  final bool isDark;

  ElevationProfilePainter({
    required this.points,
    required this.minAlt,
    required this.maxAlt,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final w = size.width;
    final h = size.height;

    final altSpan = math.max(10.0, maxAlt - minAlt);
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * w;
      final y = h - ((points[i].altitude - minAlt) / altSpan) * (h - 8) - 4;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(w, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)).withOpacity(0.25),
          (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant ElevationProfilePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.isDark != isDark;
}
