// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 导航仪表盘主页面 (Dashboard Screen)
// 文件职责: 承载自适应车机横屏双栏领航舱与竖屏经典仪表盘、360°旋转罗盘、
//          避险备忘卡片、到达蜂鸣/震动双反馈与全自动行程轨迹结束确认
// ==============================================================================

import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/math_utils.dart';
import '../core/sensor_fusion.dart';
import '../core/theme_controller.dart';
import '../core/locale_controller.dart';
import '../core/navigation_mode.dart';
import '../core/device_mode_controller.dart';
import '../core/track_recorder_service.dart';
import '../models/roadbook.dart';
import 'roadbook_manager_screen.dart';
import 'track_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SensorFusionManager _fusion = SensorFusionManager();
  final ThemeController _themeCtrl = ThemeController.instance;
  final RoadbookStore _roadbookStore = RoadbookStore.instance;
  final LocaleController _localeCtrl = LocaleController.instance;
  final NavigationModeController _modeCtrl = NavigationModeController.instance;
  final DeviceModeController _deviceCtrl = DeviceModeController.instance;
  final TrackRecorderService _recorder = TrackRecorderService.instance;

  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _themeCtrl.addListener(_onRebuild);
    _localeCtrl.addListener(_onRebuild);
    _modeCtrl.addListener(_onRebuild);
    _deviceCtrl.addListener(_onRebuild);
    _recorder.addListener(_onRebuild);
    _roadbookStore.addListener(_onRoadbookChanged);
    _initPermissionsAndStart();
  }

  @override
  void dispose() {
    _themeCtrl.removeListener(_onRebuild);
    _localeCtrl.removeListener(_onRebuild);
    _modeCtrl.removeListener(_onRebuild);
    _deviceCtrl.removeListener(_onRebuild);
    _recorder.removeListener(_onRebuild);
    _roadbookStore.removeListener(_onRoadbookChanged);
    _fusion.dispose();
    super.dispose();
  }

  void _onRebuild() {
    if (mounted) setState(() {});
  }

  void _onRoadbookChanged() {
    final cur = _roadbookStore.activeRoadbook.currentTarget;
    if (cur != null) {
      _fusion.setTarget(cur.lat, cur.lon);
    }
    if (mounted) setState(() {});
  }

  Future<void> _initPermissionsAndStart() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        if (mounted) setState(() => _permissionGranted = true);
        final cur = _roadbookStore.activeRoadbook.currentTarget;
        if (cur != null) {
          _fusion.setTarget(cur.lat, cur.lon);
        }
        await _fusion.start();

        // 核心：开始导航同步开启轨迹记录！
        if (!_recorder.isRecording) {
          final rbName = _roadbookStore.activeRoadbook.name;
          await _recorder.startNavigationRecording(
            mode: _modeCtrl.currentMode,
            customName: "导航轨迹_${rbName}_${DateFormat('MMdd_HHmm').format(DateTime.now())}",
          );
        }
      }
    } catch (e) {
      debugPrint("定位初始化容错: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_permissionGranted) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gps_off, color: Colors.orange, size: 64),
              const SizedBox(height: 16),
              Text(
                I18n.isZh ? "请授予高精度 GPS 定位权限" : "Permission Required",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                I18n.isZh ? "本工具专为无人区纯脱网越野设计，用于离线导航与方位解算" : "Offline GPS tool for off-grid navigation.",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initPermissionsAndStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                  foregroundColor: isDark ? Colors.black : Colors.white,
                ),
                child: Text(I18n.isZh ? "立即授权" : "Authorize"),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExitNavigation(context, isDark);
      },
      child: Scaffold(
        body: SafeArea(
        child: StreamBuilder<NavigationState>(
          stream: _fusion.stateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;

            // 核心自动到达与换向判定逻辑
            if (state != null) {
              final advanced = _roadbookStore.checkArrivalAndAutoAdvance(state.distanceMeters);
              if (advanced) {
                // 触发车机蜂鸣声 + 手机触觉双保险反馈！
                BeeperService.playArrivalBeep();
                final nextTarget = _roadbookStore.activeRoadbook.currentTarget;
                if (nextTarget != null) {
                  _fusion.setTarget(nextTarget.lat, nextTarget.lon);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(I18n.arrivedNextTargetToast(nextTarget.name)),
                      duration: const Duration(seconds: 2),
                      backgroundColor: const Color(0xFF00AA44),
                    ),
                  );
                }
              }
            }

            return OrientationBuilder(
              builder: (context, orientation) {
                final isLandscape = orientation == Orientation.landscape;
                if (isLandscape) {
                  return _buildLandscapeCockpit(context, state, isDark);
                }
                return _buildPortraitCockpit(context, state, isDark);
              },
            );
          },
        ),
      ),
    ),
    );
  }

  void _handleExitNavigation(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)),
            const SizedBox(width: 8),
            Text(I18n.exitNavDialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          I18n.exitNavDialogBody,
          style: TextStyle(fontSize: 13, height: 1.5, color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          // 点“否”：不退出导航，滑动或返回到首页，导航与轨迹记录后台继续运行！
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(I18n.toastNavRunningInBackground),
                  duration: const Duration(seconds: 3),
                  backgroundColor: const Color(0xFF008833),
                ),
              );
            },
            child: Text(I18n.btnKeepBackground),
          ),
          // 点“是”：退出导航，触发行程结束与轨迹保存流程
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
              foregroundColor: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (_recorder.isRecording && _recorder.currentPointCount > 0) {
                _showEndTrackDialog(context, isDark, onExited: () {
                  _fusion.stop();
                  Navigator.of(context).pop();
                });
              } else {
                _recorder.discardCurrentSession();
                _fusion.stop();
                Navigator.of(context).pop();
              }
            },
            child: Text(I18n.btnExitNav),
          ),
        ],
      ),
    );
  }

  /// 手机/车机竖屏经典纵向布局
  Widget _buildPortraitCockpit(BuildContext context, NavigationState? state, bool isDark) {
    return Column(
      children: [
        _buildTopStatusBar(context, state, isDark, isLandscape: false),
        _buildMultiWaypointBanner(context, isDark),
        _buildFourGridMetrics(context, state, isDark),
        Expanded(child: _buildCompassArea(context, state, isDark)),
        _buildWaypointWarningCard(context, isDark),
        _buildBottomRoadbookControlBar(context, state, isDark),
      ],
    );
  }

  /// 车机横屏超宽大屏领航舱 (左右分栏自适应布局)
  Widget _buildLandscapeCockpit(BuildContext context, NavigationState? state, bool isDark) {
    return Row(
      children: [
        // 左半屏：罗盘仪表盘 + 航向方位角 + 状态指示
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              children: [
                _buildLeftLandscapeStatus(context, state, isDark),
                Expanded(child: _buildCompassArea(context, state, isDark)),
                _buildBottomCoordinatesOnly(context, state, isDark),
              ],
            ),
          ),
        ),

        // 右半屏：状态控制条 + 多点横幅 + 四大数据矩阵 + 避坑卡片 + 控制栏
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _buildTopStatusBar(context, state, isDark, isLandscape: true),
              _buildMultiWaypointBanner(context, isDark),
              _buildFourGridMetrics(context, state, isDark),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildWaypointWarningCard(context, isDark),
                    ],
                  ),
                ),
              ),
              _buildBottomRoadbookControlBar(context, state, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftLandscapeStatus(BuildContext context, NavigationState? state, bool isDark) {
    final accu = state?.accuracy.toStringAsFixed(1) ?? "--";
    final alt = state?.altitude.toStringAsFixed(0) ?? "--";
    final isGps = state?.isGpsCourseActive ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark ? const Color(0xFF080808) : const Color(0xFFFFFFFF),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.satellite_alt,
                color: (state != null && state.accuracy <= 15)
                    ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                    : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                "±$accu m",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                I18n.altitudeFormat(alt),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isGps
                  ? (isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA))
                  : (isDark ? const Color(0xFF2B1800) : const Color(0xFFFFF3E0)),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isGps
                    ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                    : Colors.orange,
              ),
            ),
            child: Text(
              isGps ? I18n.headingGps : I18n.headingCompass,
              style: TextStyle(
                color: isGps
                    ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                    : Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCoordinatesOnly(BuildContext context, NavigationState? state, bool isDark) {
    final cur = _roadbookStore.activeRoadbook.currentTarget;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF0F2F5),
      child: Center(
        child: Text(
          cur != null
              ? "${MathUtils.formatCoordinate(cur.lat, true)}  ${MathUtils.formatCoordinate(cur.lon, false)}"
              : I18n.noCoordinates,
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  /// 顶部状态栏：定位精度 + 运动模式切换 + REC录制药丸 + 语言切换 + 主题切换
  Widget _buildTopStatusBar(BuildContext context, NavigationState? state, bool isDark, {required bool isLandscape}) {
    final accu = state?.accuracy.toStringAsFixed(1) ?? "--";
    final alt = state?.altitude.toStringAsFixed(0) ?? "--";
    final isGps = state?.isGpsCourseActive ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF080808) : const Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：退出导航按钮与定位信息
          if (!isLandscape)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: I18n.isZh ? "结束导航" : "Exit Nav",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleExitNavigation(context, isDark),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.satellite_alt,
                  color: (state != null && state.accuracy <= 15)
                      ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                      : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  "±$accu m",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  I18n.altitudeFormat(alt),
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          else
            // 横屏下左侧展示车机形态标识与退出按钮
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: I18n.isZh ? "结束导航" : "Exit Nav",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleExitNavigation(context, isDark),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.directions_car,
                  size: 16,
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                ),
                const SizedBox(width: 4),
                Text(
                  I18n.carLandscapeCockpit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),

          // 右侧：运动模式 + REC 录制 + 中英文 + 主题
          Row(
            children: [
              _buildModeSelector(context, isDark),
              const SizedBox(width: 5),
              _buildRecButton(context, isDark),
              const SizedBox(width: 5),
              // 中英文一键切换按钮
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _localeCtrl.toggleLanguage(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.translate,
                        size: 12,
                        color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _localeCtrl.isZh ? "中" : "EN",
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

              if (!isLandscape) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGps
                        ? (isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA))
                        : (isDark ? const Color(0xFF2B1800) : const Color(0xFFFFF3E0)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isGps
                          ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                          : Colors.orange,
                    ),
                  ),
                  child: Text(
                    isGps ? I18n.headingGps : I18n.headingCompass,
                    style: TextStyle(
                      color: isGps
                          ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                          : Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],

              const SizedBox(width: 4),
              PopupMenuButton<AppThemeMode>(
                icon: Icon(
                  _themeCtrl.modeIcon,
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                  size: 19,
                ),
                tooltip: _themeCtrl.modeName,
                onSelected: (mode) => _themeCtrl.setMode(mode),
                itemBuilder: (ctx) => [
                  _buildThemeMenuItem(AppThemeMode.system, I18n.themeSystem, Icons.brightness_auto),
                  _buildThemeMenuItem(AppThemeMode.light, I18n.themeLight, Icons.wb_sunny),
                  _buildThemeMenuItem(AppThemeMode.dark, I18n.themeDark, Icons.nightlight_round),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 运动模式切换按钮
  Widget _buildModeSelector(BuildContext context, bool isDark) {
    final profile = _modeCtrl.currentProfile;

    return PopupMenuButton<OutdoorSportMode>(
      tooltip: I18n.modeSelectorTitle,
      onSelected: (mode) => _modeCtrl.setMode(mode),
      itemBuilder: (ctx) => OutdoorSportMode.values.map((mode) {
        final p = NavigationModeProfile.profiles[mode]!;
        final isSelected = mode == _modeCtrl.currentMode;
        return PopupMenuItem(
          value: mode,
          child: Row(
            children: [
              Icon(
                p.icon,
                size: 18,
                color: isSelected ? const Color(0xFF00AA44) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF00AA44) : null,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF162519) : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              profile.icon,
              size: 13,
              color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
            ),
            const SizedBox(width: 4),
            Text(
              profile.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全自动轨迹记录状态指示与结束保存入口
  Widget _buildRecButton(BuildContext context, bool isDark) {
    final distKm = (_recorder.currentRecordedDistanceMeters / 1000.0).toStringAsFixed(1);
    final pts = _recorder.currentPointCount;

    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => _showEndTrackDialog(context, isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: pts > 0
              ? (isDark ? const Color(0xFF003311) : const Color(0xFFE8F5E9))
              : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECEFF1)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: pts > 0
                ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                : Colors.grey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fiber_manual_record,
              size: 9,
              color: pts > 0
                  ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                  : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              pts > 0 ? I18n.autoRecordingLive(_recorder.currentRecordedDistanceMeters / 1000.0) : "轨迹记录中",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: pts > 0
                    ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEndTrackDialog(BuildContext context, bool isDark, {VoidCallback? onExited}) {
    final track = _recorder.activeTrack;
    final distKm = track != null ? (track.totalDistanceMeters / 1000.0) : 0.0;
    final timeStr = track != null ? MathUtils.formatDuration(track.totalDuration) : "00:00:00";
    final pts = track != null ? track.points.length : 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_rounded, color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)),
            const SizedBox(width: 8),
            Text(I18n.finishTrackSessionTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              I18n.promptSaveTrackSubtitle(distKm, timeStr, pts),
              style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.history, size: 16),
                label: Text(I18n.trackListTitle),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const TrackListScreen()));
                },
              ),
            ),
          ],
        ),
        actions: [
          // 不保存按钮 (丢弃)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            onPressed: () async {
              Navigator.pop(ctx);
              await _recorder.discardCurrentSession();
              onExited?.call();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(I18n.discardedToast)),
                );
              }
            },
            child: Text(I18n.discardTrackButton),
          ),
          // 保存按钮 (存入本地手机)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _promptSaveNameAndPersist(context, isDark, onExited: onExited);
            },
            child: Text(I18n.saveToHistoryButton),
          ),
        ],
      ),
    );
  }

  void _promptSaveNameAndPersist(BuildContext context, bool isDark, {VoidCallback? onExited}) {
    final defaultName = "山海轨迹_${DateFormat('MMdd_HHmm').format(DateTime.now())}";
    final ctrl = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.isZh ? "保存轨迹至本机" : "Save Track to Phone"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: I18n.isZh ? "轨迹名称" : "Track Name",
            hintText: defaultName,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(I18n.isZh ? "取消" : "Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _recorder.saveCurrentSession(name: ctrl.text.trim());
              onExited?.call();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(I18n.savedToLocalSuccessToast),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            child: Text(I18n.isZh ? "确认保存" : "Confirm Save"),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<AppThemeMode> _buildThemeMenuItem(AppThemeMode mode, String title, IconData icon) {
    final isSelected = _themeCtrl.mode == mode;
    return PopupMenuItem<AppThemeMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? const Color(0xFF00AA44) : Colors.grey),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF00AA44) : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 多点路书进度横幅
  Widget _buildMultiWaypointBanner(BuildContext context, bool isDark) {
    final rb = _roadbookStore.activeRoadbook;
    final totalPoints = rb.points.length;
    final curIndex = rb.currentTargetIndex + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: isDark ? const Color(0xFF111111) : const Color(0xFFEBEFF4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            tooltip: I18n.prevStation,
            onPressed: rb.hasPrevious
                ? () {
                    _roadbookStore.previousPoint();
                    final pt = _roadbookStore.activeRoadbook.currentTarget;
                    if (pt != null) _fusion.setTarget(pt.lat, pt.lon);
                  }
                : null,
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rb.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF222222) : const Color(0xFFD6D9E0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        I18n.stationProgress(curIndex, totalPoints),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rb.currentTarget?.name ?? I18n.noTargetWaypoint,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            tooltip: I18n.nextStation,
            onPressed: rb.hasNext
                ? () {
                    _roadbookStore.nextPoint();
                    final pt = _roadbookStore.activeRoadbook.currentTarget;
                    if (pt != null) _fusion.setTarget(pt.lat, pt.lon);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  /// 四大核心导航参数矩阵 (根据运动模式动态展示最适配的指标)
  Widget _buildFourGridMetrics(BuildContext context, NavigationState? state, bool isDark) {
    final distKm = state != null ? (state.distanceMeters / 1000.0).toStringAsFixed(1) : "--";
    final speed = state != null ? state.speedKmh.toStringAsFixed(0) : "--";
    final brg = state != null ? "${state.targetBearing.toStringAsFixed(0).padLeft(3, '0')}°" : "--";
    final ete = state?.ete != null ? MathUtils.formatDuration(state!.ete!) : "--";

    final distColor = isDark ? const Color(0xFF00FF66) : const Color(0xFF008833);
    final speedColor = isDark ? const Color(0xFF00FFCC) : const Color(0xFF0066CC);
    final eteColor = isDark ? Colors.white : const Color(0xFF222222);
    final brgColor = isDark ? const Color(0xFFFFCC00) : const Color(0xFFCC6600);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildMetricCell(I18n.distToNext, "$distKm km", distColor, isDark)),
          Container(width: 1, height: 42, color: Theme.of(context).dividerColor),
          Expanded(child: _buildMetricCell(I18n.instantSpeed, "$speed km/h", speedColor, isDark)),
          Container(width: 1, height: 42, color: Theme.of(context).dividerColor),
          Expanded(child: _buildMetricCell(I18n.eteLabel, ete, eteColor, isDark)),
          Container(width: 1, height: 42, color: Theme.of(context).dividerColor),
          Expanded(child: _buildMetricCell(I18n.brgLabel, brg, brgColor, isDark)),
        ],
      ),
    );
  }

  Widget _buildMetricCell(String label, String value, Color valueColor, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.grey : Colors.black54,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: valueColor,
            fontFamily: 'monospace',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 中心全量程 360° 旋转罗盘区域
  Widget _buildCompassArea(BuildContext context, NavigationState? state, bool isDark) {
    final heading = state?.currentHeading ?? 0.0;
    final relBearing = state?.relativeBearing ?? 0.0;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.90;

          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -heading * (math.pi / 180.0),
                  child: CustomPaint(
                    size: Size(size, size),
                    painter: CompassDialPainter(isDark: isDark),
                  ),
                ),
                Transform.rotate(
                  angle: relBearing * (math.pi / 180.0),
                  child: GuidanceArrow(isDark: isDark, size: size * 0.55),
                ),
                Positioned(
                  top: size * 0.06,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Text(
                      "${heading.toStringAsFixed(0).padLeft(3, '0')}° ${MathUtils.degreesToCompassDirection(heading)}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFFCC00) : const Color(0xFFCC6600),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 避险备忘卡片
  Widget _buildWaypointWarningCard(BuildContext context, bool isDark) {
    final rb = _roadbookStore.activeRoadbook;
    final cur = rb.currentTarget;
    final desc = cur?.desc.trim() ?? "";
    final hasDesc = desc.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasDesc
            ? (isDark ? const Color(0xFF261800) : const Color(0xFFFFF7E6))
            : (isDark ? const Color(0xFF141414) : const Color(0xFFF7F8FA)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDesc
              ? (isDark ? const Color(0xFFFF9900) : const Color(0xFFFFB300))
              : Theme.of(context).dividerColor,
          width: hasDesc ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                hasDesc ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 16,
                color: hasDesc
                    ? (isDark ? const Color(0xFFFFB300) : const Color(0xFFD46B08))
                    : (isDark ? Colors.white54 : Colors.black45),
              ),
              const SizedBox(width: 6),
              Text(
                I18n.hazardCardTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: hasDesc
                      ? (isDark ? const Color(0xFFFFB300) : const Color(0xFFD46B08))
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasDesc ? desc : I18n.noHazardNote,
            style: TextStyle(
              fontSize: 13,
              fontWeight: hasDesc ? FontWeight.bold : FontWeight.normal,
              color: hasDesc
                  ? (isDark ? const Color(0xFFFFE58F) : const Color(0xFF873800))
                  : (isDark ? Colors.white38 : Colors.black45),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部路线状态与全功能路书管理入口
  Widget _buildBottomRoadbookControlBar(BuildContext context, NavigationState? state, bool isDark) {
    final rb = _roadbookStore.activeRoadbook;
    final cur = rb.currentTarget;
    double totalRemKm = 0.0;
    if (state != null) {
      totalRemKm = rb.calculateTotalRemainingDistance(state.currentLat, state.currentLon) / 1000.0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.near_me,
                      color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      I18n.remainingDistance(totalRemKm),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cur != null
                      ? "${MathUtils.formatCoordinate(cur.lat, true)}  ${MathUtils.formatCoordinate(cur.lon, false)}"
                      : I18n.noCoordinates,
                  style: TextStyle(
                    color: isDark ? Colors.grey : Colors.black54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.alt_route, size: 16),
            label: Text(I18n.waypointsButton),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => const RoadbookManagerScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE8F5E9),
              foregroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              side: BorderSide(
                color: isDark ? const Color(0xFF333333) : const Color(0xFFB2DFDB),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
class CompassDialPainter extends CustomPainter {
  final bool isDark;
  CompassDialPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final circlePaint = Paint()
      ..color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFDCDFE6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 10, circlePaint);

    final tickPaint = Paint()
      ..color = isDark ? const Color(0xFF666666) : const Color(0xFF909399)
      ..strokeWidth = 1.5;

    final majorTickPaint = Paint()
      ..color = isDark ? Colors.white : const Color(0xFF111111)
      ..strokeWidth = 2.5;

    for (int deg = 0; deg < 360; deg += 15) {
      final isMajor = deg % 90 == 0;
      final isSubMajor = deg % 45 == 0;
      final tickLength = isMajor ? 16.0 : (isSubMajor ? 10.0 : 6.0);
      final rad = deg * (math.pi / 180.0);

      final p1 = Offset(
        center.dx + (radius - 12) * math.sin(rad),
        center.dy - (radius - 12) * math.cos(rad),
      );
      final p2 = Offset(
        center.dx + (radius - 12 - tickLength) * math.sin(rad),
        center.dy - (radius - 12 - tickLength) * math.cos(rad),
      );

      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CompassDialPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// ---------------------------------------------------------------------------
/// 落地页同款：3D立体折面导航大指针 (Faceted Delta Wing Needle)
/// 设计特征:
/// 1. 采用航空航海双折面导向翼设计，右翼高光、左翼微阴影，呈现硬派立体机械质感；
/// 2. 严格按 100x100 几何拓扑比例缩放 (顶点 50,10 / 右翼 78,85 / 尾凹 50,70 / 左翼 22,85)；
/// 3. 中心 (50,50) 设精密金属定位铆钉，确保以罗盘绝对中心点旋转时零偏心摆动；
/// 4. 底部投射平滑深黑阴影，强化在强颠簸强光下的 0.5 秒态势识别。
/// ---------------------------------------------------------------------------
class GuidanceArrow extends StatelessWidget {
  final bool isDark;
  final double size;
  const GuidanceArrow({super.key, required this.isDark, this.size = 120.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: ArrowPainter(isDark: isDark),
    );
  }
}

class ArrowPainter extends CustomPainter {
  final bool isDark;
  ArrowPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 拓扑关键节点定义 (基于 100x100 归一化坐标)
    final tip = Offset(w * 0.50, h * 0.10);
    final rightOuter = Offset(w * 0.78, h * 0.85);
    final leftOuter = Offset(w * 0.22, h * 0.85);
    final tailInner = Offset(w * 0.50, h * 0.70);
    final centerHub = Offset(w * 0.50, h * 0.50);

    // 1. 绘制立体悬浮外轮廓投影 (Drop Shadow)
    final fullArrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(rightOuter.dx, rightOuter.dy)
      ..lineTo(tailInner.dx, tailInner.dy)
      ..lineTo(leftOuter.dx, leftOuter.dy)
      ..close();

    canvas.drawShadow(
      fullArrowPath,
      isDark ? Colors.black.withOpacity(0.85) : Colors.black.withOpacity(0.35),
      6.0,
      false,
    );

    // 2. 右翼高光侧折面路径
    final rightWingPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(rightOuter.dx, rightOuter.dy)
      ..lineTo(tailInner.dx, tailInner.dy)
      ..close();

    // 3. 左翼受阴侧折面路径
    final leftWingPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(leftOuter.dx, leftOuter.dy)
      ..lineTo(tailInner.dx, tailInner.dy)
      ..close();

    // 4. 高反差昼夜双色配色方案 (与落地页完全一致)
    // 暗夜模式: 右翼 #00FF66 (高饱和电光绿) / 左翼 #00DD55 (沉稳深绿) / 边框 #003311 (深色高反差描边)
    // 白昼模式: 右翼 #00AA33 (烈日防直射亮绿) / 左翼 #007722 (遮光阴影绿) / 边框 #00220A (防泛白纯深绿)
    final rightColor = isDark ? const Color(0xFF00FF66) : const Color(0xFF00AA33);
    final leftColor = isDark ? const Color(0xFF00DD55) : const Color(0xFF007722);
    final strokeColor = isDark ? const Color(0xFF003311) : const Color(0xFF00220A);

    // 填充左右双翼立体折面
    canvas.drawPath(rightWingPath, Paint()..color = rightColor..style = PaintingStyle.fill);
    canvas.drawPath(leftWingPath, Paint()..color = leftColor..style = PaintingStyle.fill);

    // 5. 绘制工业级边缘与中脊分界描边 (Stroke)
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, w * 0.026)
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(rightWingPath, strokePaint);
    canvas.drawPath(leftWingPath, strokePaint);

    // 6. 绘制中心定位旋转枢轴金属铆钉 (Center Pin Hub)
    final pinRadius = math.max(3.8, w * 0.042);
    final pinFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final pinStrokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w * 0.015);

    canvas.drawCircle(centerHub, pinRadius, pinFillPaint);
    canvas.drawCircle(centerHub, pinRadius, pinStrokePaint);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) => oldDelegate.isDark != isDark;
}
