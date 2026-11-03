// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 历史轨迹高密度管理列表 (Track List Screen)
// 文件职责: 
// 1. 采用高密度单行紧凑卡片排版 (高度压至 58px)，单屏直观饱览 8~10 条历史轨迹；
// 2. 核心展示保存时间、关联点数、里程与用时等关键信息，去除卡片外层繁琐冗余按钮；
// 3. 点击任意轨迹直接进入「轨迹全貌地图与详情页面 (TrackDetailScreen)」，并在详情内
//    提供一键返航、导出 GPX、转路书与云端上传等标准架构功能。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/locale_controller.dart';
import '../core/navigation_mode.dart';
import '../core/app_style.dart';
import '../core/track_recorder_service.dart';
import '../models/track.dart';
import 'track_detail_screen.dart';

class TrackListScreen extends StatefulWidget {
  const TrackListScreen({super.key});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  final TrackRecorderService _recorder = TrackRecorderService.instance;

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_onRebuild);
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRebuild);
    super.dispose();
  }

  void _onRebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracks = _recorder.savedTracks;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          I18n.trackListTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        actions: [
          if (_recorder.isRecording)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                  SizedBox(width: 4),
                  Text(
                    "REC",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: tracks.isEmpty
          ? _buildEmptyState(context, isDark)
          : Column(
              children: [
                // 顶部统计信息行
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "共 ${tracks.length} 条已存历史轨迹",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      Text(
                        "点击进入地图全貌与返航",
                        style: TextStyle(
                          fontSize: 11,
                          color: AppStyle.primaryGreen(isDark),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // 高密度紧凑型轨迹列表 (压缩占用高度，一屏饱览更多)
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return _buildCompactTrackTile(context, track, isDark);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timeline,
              size: 56,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 14),
            Text(
              I18n.noTracksYet,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              I18n.noTracksHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 高密度紧凑单行轨迹卡片 (高度约 58px)
  Widget _buildCompactTrackTile(BuildContext context, Track track, bool isDark) {
    final distKm = (track.totalDistanceMeters / 1000.0).toStringAsFixed(1);
    final movingHours = track.movingDuration.inHours;
    final movingMins = track.movingDuration.inMinutes % 60;
    final durationStr = movingHours > 0
        ? "${movingHours}h${movingMins}m"
        : "${movingMins}m";

    final dateStr = DateFormat("MM-dd HH:mm").format(track.startTime);
    final profile = NavigationModeProfile.profiles[track.mode]!;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E4E8),
          width: 1.0,
        ),
      ),
      color: isDark ? const Color(0xFF141414) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          // 点击某一个轨迹，直接进入地图全貌与返航标准详情页
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => TrackDetailScreen(track: track),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // 1. 左侧模式与类型小图标 (32x32)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF162519) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)).withOpacity(0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  profile.icon,
                  size: 17,
                  color: AppStyle.primaryGreen(isDark),
                ),
              ),
              const SizedBox(width: 10),

              // 2. 中间核心信息区 (双行紧凑，一行核心指标)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 第一行：轨迹标题 + 采样点数微标签 + 模式
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            "${track.points.length}点",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 第二行：保存时间 + 里程 + 耗时关键信息 (单行规整排布)
                    Text(
                      "$dateStr · $distKm km · $durationStr · +${track.totalAscent.toStringAsFixed(0)}m",
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // 3. 右侧简洁操作区：进入地图指示箭头 + 更多菜单 (重命名/删除)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onSelected: (val) {
                      if (val == "rename") {
                        _showRenameDialog(context, track);
                      } else if (val == "delete") {
                        _showDeleteDialog(context, track);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: "rename",
                        child: Text(I18n.isZh ? "重命名" : "Rename"),
                      ),
                      PopupMenuItem(
                        value: "delete",
                        child: Text(
                          I18n.isZh ? "删除" : "Delete",
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, Track track) {
    final ctrl = TextEditingController(text: track.name);
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
                await _recorder.updateTrackName(track.id, newName);
                setState(() => track.name = newName);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(I18n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Track track) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.isZh ? "删除此轨迹？" : "Delete Track?"),
        content: Text(
          I18n.isZh
              ? "确定删除【${track.name}】吗？删除后手机本地数据将永久清空，无法找回。"
              : "Delete \"${track.name}\"? Local data cannot be recovered.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(I18n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _recorder.deleteTrack(track.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(I18n.isZh ? "确认删除" : "Delete"),
          ),
        ],
      ),
    );
  }
}
