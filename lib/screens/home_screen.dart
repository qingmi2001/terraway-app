// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 卫星遥测待机与当前位置首页 (Home Screen)
// 文件职责: 开机展示北斗/GPS 双模搜星状态、海拔车速、度分秒固定列宽垂直锁相对齐、
//          极简路线/轨迹主控条；
//          v0.7.5 升级: 抽屉内明确强化【登录 / 注册】显式入口与引导、极简 2~4 字按钮
// ==============================================================================

import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/math_utils.dart';
import '../core/sensor_fusion.dart';
import '../core/theme_controller.dart';
import '../core/locale_controller.dart';
import '../core/update_checker_service.dart';
import '../core/cloud_sync_service.dart';
import '../core/app_config.dart';
import '../core/app_style.dart';
import 'roadbook_list_screen.dart';
import 'satellite_detail_screen.dart';
import '../core/navigation_mode.dart';
import '../core/device_mode_controller.dart';
import '../core/track_recorder_service.dart';
import 'track_list_screen.dart';
import 'dashboard_screen.dart';
import '../models/roadbook.dart';
import '../widgets/interactive_map_view.dart';
import '../core/offline_tile_service.dart';

enum HomeDisplayMode { map, compass }


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SensorFusionManager _fusion = SensorFusionManager();
  final ThemeController _themeCtrl = ThemeController.instance;
  final LocaleController _localeCtrl = LocaleController.instance;
  final UpdateCheckerService _updateCtrl = UpdateCheckerService.instance;
  final CloudSyncService _cloudCtrl = CloudSyncService.instance;

  bool _permissionGranted = false;
  HomeDisplayMode _displayMode = HomeDisplayMode.map;


  @override
  void initState() {
    super.initState();
    _themeCtrl.addListener(_onRebuild);
    NavigationModeController.instance.addListener(_onRebuild);
    TrackRecorderService.instance.addListener(_onRebuild);
    DeviceModeController.instance.addListener(_onRebuild);
    _updateCtrl.addListener(_onRebuild);
    _cloudCtrl.addListener(_onRebuild);
    _initPermissionsAndStart();

    // 开机非阻塞静默检测更新 (飞行模式/离线自动静默跳过)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateCtrl.checkOnStartup(context);
      }
    });
  }

  @override
  void dispose() {
    _themeCtrl.removeListener(_onRebuild);
    NavigationModeController.instance.removeListener(_onRebuild);
    TrackRecorderService.instance.removeListener(_onRebuild);
    DeviceModeController.instance.removeListener(_onRebuild);
    _updateCtrl.removeListener(_onRebuild);
    _cloudCtrl.removeListener(_onRebuild);
    _fusion.dispose();
    super.dispose();
  }

  void _onRebuild() {
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
        await OfflineTileService.instance.init();
        await _fusion.start();
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.satellite_alt, color: Colors.orange, size: 64),
                const SizedBox(height: 16),
                Text(
                  "欢迎使用 山海行 (TerraWay)",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "专为徒步、骑行、自驾等全场景纯脱网环境设计。请授予卫星定位权限。",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initPermissionsAndStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: const Text("授予定位权限"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: _buildModeToggleFab(context, isDark),
      body: SafeArea(
        child: StreamBuilder<NavigationState>(
          stream: _fusion.stateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final hasFix = state != null && state.accuracy > 0 && state.accuracy <= 50;

            if (_displayMode == HomeDisplayMode.map) {
              // 模式一: 全景地图模式 (默认开机模式)
              return Column(
                children: [
                  _buildTopBar(context, state, isDark, hasFix),
                  if (TrackRecorderService.instance.isRecording)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: _buildActiveNavBanner(context, isDark),
                    ),
                  Expanded(
                    child: InteractiveMapView(
                      navState: state,
                      isDark: isDark,
                    ),
                  ),
                  _buildBottomSelectRouteButton(context, isDark),
                ],
              );
            }

            // 模式二: 指针罗盘仪表盘模式
            return Column(
              children: [
                _buildTopBar(context, state, isDark, hasFix),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (TrackRecorderService.instance.isRecording) ...[
                          _buildActiveNavBanner(context, isDark),
                        ],
                        _buildGpsStatusCard(context, state, isDark, hasFix),
                        const SizedBox(height: 12),
                        _buildCurrentCoordinateCard(context, state, isDark),
                        const SizedBox(height: 12),
                        _buildStandbyCompass(context, state, isDark),
                      ],
                    ),
                  ),
                ),
                _buildBottomSelectRouteButton(context, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 后台导航活跃状态横幅

  /// 右下角悬浮按钮切换: 全景地图 ⇋ 罗盘指针
  Widget _buildModeToggleFab(BuildContext context, bool isDark) {
    final isMap = _displayMode == HomeDisplayMode.map;
    return Container(
      margin: const EdgeInsets.only(bottom: 64),
      child: FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _displayMode = isMap ? HomeDisplayMode.compass : HomeDisplayMode.map;
          });
        },
        elevation: 6,
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
            width: 1.5,
          ),
        ),
        icon: Icon(
          isMap ? Icons.explore_outlined : Icons.map_outlined,
          color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
          size: 20,
        ),
        label: Text(
          isMap ? "🧭 指针罗盘" : "🗺️ 全景地图",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveNavBanner(BuildContext context, bool isDark) {
    final activeRoadbook = RoadbookStore.instance.activeRoadbook;
    final distKm = TrackRecorderService.instance.currentRecordedDistanceMeters / 1000.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2214) : const Color(0xFFE8F7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.navigation,
              size: 16,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.activeNavBannerTitle(activeRoadbook.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  I18n.activeNavBannerSubtitle(distKm),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(60, 32),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const DashboardScreen()),
              );
            },
            child: Text(
              I18n.returnToNavButton,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部探险者头像按钮 (发现新版本时亮起红点)
  Widget _buildExplorerAvatarMenu(BuildContext context, bool isDark, NavigationState? state) {
    final hasUpdate = _updateCtrl.hasUpdate;

    return GestureDetector(
      onTap: () => _showExplorerMenuSheet(context, isDark, state),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)).withOpacity(0.2),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 15,
              backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFE2E8F0),
              child: Icon(
                Icons.person,
                size: 20,
                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              ),
            ),
          ),
          if (hasUpdate)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppStyle.alertRed,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.black : Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 探险者综合抽屉 (首栏明确强化【登录 / 注册】显式按钮与提示)
  void _showExplorerMenuSheet(BuildContext context, bool isDark, NavigationState? state) {
    final modeCtrl = NavigationModeController.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isLogged = _cloudCtrl.isLoggedIn;
          final hasNewVer = _updateCtrl.hasUpdate;
          final latestVerName = _updateCtrl.latestRelease?.versionName ?? UpdateCheckerService.currentVersionName;
          final primaryGreen = AppStyle.primaryGreen(isDark);

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1. 首行卡片：显式展示【登录 / 注册】按钮与提示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181818) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isLogged
                            ? primaryGreen
                            : (isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                        width: isLogged ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isLogged ? primaryGreen : (isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
                          child: Icon(
                            isLogged ? Icons.cloud_done : Icons.person_outline,
                            size: 22,
                            color: isLogged ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLogged ? _cloudCtrl.userNickname : "离线访客模式",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isLogged
                                    ? "${_cloudCtrl.userAccount} · 云端保险箱已连接"
                                    : "单机全功能可用 · 可选注册备份",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 显式登录/注册操作按钮 (直观醒目，杜绝找不到)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLogged
                                ? (isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0))
                                : primaryGreen,
                            foregroundColor: isLogged
                                ? (isDark ? Colors.white70 : Colors.black87)
                                : (isDark ? Colors.black : Colors.white),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(68, 32),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showCloudVaultDialog(context, isDark);
                          },
                          child: Text(
                            isLogged ? "管理" : "登录 / 注册",
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 菜单项 1: 昼夜显示主题
                  _buildMenuActionTile(
                    icon: _themeCtrl.modeIcon,
                    title: I18n.menuThemes,
                    subtitle: _themeCtrl.modeName,
                    isDark: isDark,
                    onTap: () {
                      _themeCtrl.toggleNext();
                      setSheetState(() {});
                      if (mounted) setState(() {});
                    },
                  ),

                  // 菜单项 2: 中英语言
                  _buildMenuActionTile(
                    icon: Icons.translate,
                    title: I18n.menuLanguages,
                    subtitle: _localeCtrl.isZh ? "简体中文 (切换 English)" : "English (切换中文)",
                    isDark: isDark,
                    onTap: () {
                      _localeCtrl.toggleLanguage();
                      setSheetState(() {});
                      if (mounted) setState(() {});
                    },
                  ),

                  // 菜单项 3: 运动模式
                  _buildMenuActionTile(
                    icon: modeCtrl.currentModeIcon,
                    title: I18n.menuModes,
                    subtitle: "${modeCtrl.currentModeName} (${modeCtrl.currentThresholdMeters.toInt()}m 阈值)",
                    isDark: isDark,
                    onTap: () {
                      modeCtrl.cycleToNextMode();
                      setSheetState(() {});
                      if (mounted) setState(() {});
                    },
                  ),

                  // 菜单项 4: 星历遥测
                  _buildMenuActionTile(
                    icon: Icons.satellite_alt,
                    title: I18n.menuSatellites,
                    subtitle: "北斗/GPS 双模信号与仰角方位",
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (c) => SatelliteDetailScreen(
                            currentLat: state?.currentLat ?? 0.0,
                            currentLon: state?.currentLon ?? 0.0,
                            accuracy: state?.accuracy ?? 0.0,
                            altitude: state?.altitude ?? 0.0,
                            hasFix: state != null && state.accuracy > 0 && state.accuracy <= 50,
                          ),
                        ),
                      );
                    },
                  ),

                  // 菜单项 5: 云端账号 (登录 / 注册)
                  _buildMenuActionTile(
                    icon: Icons.cloud_sync_outlined,
                    title: I18n.menuCloudVault,
                    subtitle: isLogged
                        ? "已登录 ${_cloudCtrl.userNickname} · 备份与换机恢复"
                        : "点击登录或注册账号 · 换机备份轨迹路线",
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCloudVaultDialog(context, isDark);
                    },
                  ),

                  // 菜单项 6: 检查更新
                  _buildMenuActionTile(
                    icon: Icons.system_update_alt,
                    title: I18n.menuCheckUpdate,
                    subtitle: hasNewVer
                        ? "发现新版本 v$latestVerName · 点击升级"
                        : "当前版本 v${UpdateCheckerService.currentVersionName} · 点击检测",
                    isDark: isDark,
                    badgeText: hasNewVer ? "${I18n.newBadgeText} v$latestVerName" : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (hasNewVer && _updateCtrl.latestRelease != null) {
                        _updateCtrl.showUpdateDialog(context, _updateCtrl.latestRelease!);
                      } else {
                        _updateCtrl.checkManually(context);
                      }
                    },
                  ),

                  // 菜单项 7: 安全须知
                  _buildMenuActionTile(
                    icon: Icons.shield_outlined,
                    title: I18n.menuSafety,
                    subtitle: "民用辅助定位说明与责任声明",
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAboutSafetyDialog(context, isDark);
                    },
                  ),

                  // 菜单项 8: 关于软件
                  _buildMenuActionTile(
                    icon: Icons.info_outline,
                    title: I18n.menuAbout,
                    subtitle: "山海行 v${AppConfig.versionName} · 官方持久签名保障",
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAboutSafetyDialog(context, isDark);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppStyle.alertRed,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: isDark ? Colors.white38 : Colors.black26,
      ),
      onTap: onTap,
    );
  }

  /// 云端数据保险箱弹窗 (顶部分立【登录】与【注册】两个清晰标签，零混淆)
  void _showCloudVaultDialog(BuildContext context, bool isDark) {
    final accountCtrl = TextEditingController(text: _cloudCtrl.userAccount);
    final passwordCtrl = TextEditingController();
    final nicknameCtrl = TextEditingController();
    final serverCtrl = TextEditingController(text: _cloudCtrl.serverBaseUrl);
    bool isRegisterMode = false;
    bool showServerConfig = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isLogged = _cloudCtrl.isLoggedIn;
          final isBusy = _cloudCtrl.isBusy;
          final primaryGreen = AppStyle.primaryGreen(isDark);

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: primaryGreen.withOpacity(0.5)),
            ),
            title: Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: primaryGreen, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    I18n.cloudVaultDialogTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_ethernet, size: 18),
                  tooltip: "节点设置",
                  onPressed: () {
                    setDialogState(() => showServerConfig = !showServerConfig);
                  },
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showServerConfig) ...[
                    TextField(
                      controller: serverCtrl,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: "VPS 服务地址",
                        hintText: "https://api.terraway.cn",
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, size: 18),
                          onPressed: () async {
                            await _cloudCtrl.setServerBaseUrl(serverCtrl.text);
                            setDialogState(() => showServerConfig = false);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (!isLogged) ...[
                    // 清晰的分段选项卡：【账号登录】 与 【极简注册】
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => isRegisterMode = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: !isRegisterMode
                                      ? (isDark ? const Color(0xFF141414) : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "账号登录",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: !isRegisterMode ? FontWeight.bold : FontWeight.normal,
                                    color: !isRegisterMode ? primaryGreen : (isDark ? Colors.white60 : Colors.black54),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => isRegisterMode = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: isRegisterMode
                                      ? (isDark ? const Color(0xFF141414) : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "新用户注册",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isRegisterMode ? FontWeight.bold : FontWeight.normal,
                                    color: isRegisterMode ? primaryGreen : (isDark ? Colors.white60 : Colors.black54),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: accountCtrl,
                      decoration: InputDecoration(
                        labelText: isRegisterMode ? "设置手机号或邮箱账号" : "手机号或邮箱账号",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isRegisterMode ? "设置密码 (至少 6 位)" : "密码",
                        isDense: true,
                      ),
                    ),
                    if (isRegisterMode) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: nicknameCtrl,
                        decoration: const InputDecoration(
                          labelText: "户外呼号/昵称 (选填)",
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: isBusy
                          ? null
                          : () async {
                              await _cloudCtrl.setServerBaseUrl(serverCtrl.text);
                              final res = isRegisterMode
                                  ? await _cloudCtrl.register(
                                      account: accountCtrl.text,
                                      password: passwordCtrl.text,
                                      nickname: nicknameCtrl.text,
                                    )
                                  : await _cloudCtrl.login(
                                      account: accountCtrl.text,
                                      password: passwordCtrl.text,
                                    );
                              setDialogState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res.message)),
                                );
                              }
                            },
                      child: Text(
                        isRegisterMode ? "立即注册并连接" : "安全登录",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!isRegisterMode) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showTicketDialog(context, isDark, defaultAccount: accountCtrl.text);
                          },
                          child: const Text("忘记密码？提交找回留言申诉", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      ),
                    ],
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D2214) : const Color(0xFFE8F7ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "当前用户：${_cloudCtrl.userNickname} (${_cloudCtrl.userAccount})",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryGreen,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await _cloudCtrl.logout();
                              setDialogState(() {});
                            },
                            child: const Text("退出", style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                      ),
                      icon: const Icon(Icons.cloud_upload, size: 18),
                      label: const Text("一键备份本地数据至 VPS"),
                      onPressed: isBusy
                          ? null
                          : () async {
                              final r1 = await _cloudCtrl.syncTracksToCloud();
                              final r2 = await _cloudCtrl.syncRoadbooksToCloud();
                              setDialogState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("${r1.message}；${r2.message}")),
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: Icon(Icons.cloud_download, size: 18, color: primaryGreen),
                      label: Text(
                        "从云端恢复数据到本机",
                        style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold),
                      ),
                      onPressed: isBusy
                          ? null
                          : () async {
                              final r1 = await _cloudCtrl.restoreTracksFromCloud();
                              final r2 = await _cloudCtrl.restoreRoadbooksFromCloud();
                              setDialogState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("${r1.message}；${r2.message}")),
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.lock_reset, size: 16),
                            label: const Text("修改密码", style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showChangePasswordDialog(context, isDark);
                            },
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.headset_mic_outlined, size: 16),
                            label: const Text("留言申诉", style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showTicketDialog(context, isDark, defaultAccount: _cloudCtrl.userAccount);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.confirm),
              ),
            ],
          );
        },
      ),
    );
  }


  void _showChangePasswordDialog(BuildContext context, bool isDark) {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final primaryGreen = AppStyle.primaryGreen(isDark);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text("修改个人登录密码", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "原密码", isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "新密码 (至少6位)", isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "确认新密码", isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () async {
              if (newPassCtrl.text != confirmPassCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("两次输入的新密码不一致")),
                );
                return;
              }
              Navigator.pop(ctx);
              final res = await _cloudCtrl.changePassword(
                oldPassword: oldPassCtrl.text,
                newPassword: newPassCtrl.text,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(res.message)),
                );
              }
            },
            child: const Text("确认修改"),
          ),
        ],
      ),
    );
  }

  void _showTicketDialog(BuildContext context, bool isDark, {String defaultAccount = ""}) {
    final accountCtrl = TextEditingController(text: defaultAccount);
    final contactCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String ticketType = "password_reset";
    final primaryGreen = AppStyle.primaryGreen(isDark);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setTicketState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text("密码找回 / 故障申诉工单", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "当前未开通短信自动下发功能，提交留言后，系统管理员将在后台查阅并协助重置处理。",
                  style: TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ticketType,
                  decoration: const InputDecoration(labelText: "工单类型", isDense: true),
                  items: const [
                    DropdownMenuItem(value: "password_reset", child: Text("找回密码申诉")),
                    DropdownMenuItem(value: "bug_report", child: Text("软件功能故障反馈")),
                    DropdownMenuItem(value: "feature_request", child: Text("路线或功能建议")),
                  ],
                  onChanged: (val) {
                    if (val != null) setTicketState(() => ticketType = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: accountCtrl,
                  decoration: const InputDecoration(labelText: "注册手机号或邮箱账号", isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactCtrl,
                  decoration: const InputDecoration(labelText: "微信 / 备用电话 (用于回执通知)", isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: messageCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "详细说明 (如: 申请重置密码或说明情况)",
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: isDark ? Colors.black : Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await _cloudCtrl.submitSupportTicket(
                  account: accountCtrl.text,
                  ticketType: ticketType,
                  contactInfo: contactCtrl.text,
                  message: messageCtrl.text,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.message)),
                  );
                }
              },
              child: const Text("提交工单"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, NavigationState? state, bool isDark, bool hasFix) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF080808) : Colors.white,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => SatelliteDetailScreen(
                    currentLat: state?.currentLat ?? 0.0,
                    currentLon: state?.currentLon ?? 0.0,
                    accuracy: state?.accuracy ?? 0.0,
                    altitude: state?.altitude ?? 0.0,
                    hasFix: hasFix,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.satellite_alt,
                    color: hasFix
                        ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                        : Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasFix ? I18n.bdsGpsLocked : I18n.acquiringSatellites,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                      color: hasFix
                          ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: hasFix
                        ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                        : Colors.orange,
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (TrackRecorderService.instance.isRecording) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const DashboardScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0D2214) : const Color(0xFFE8F7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.navigation,
                          size: 13,
                          color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _localeCtrl.isZh ? "导航中" : "Nav Active",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              _buildExplorerAvatarMenu(context, isDark, state),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGpsStatusCard(BuildContext context, NavigationState? state, bool isDark, bool hasFix) {
    final accu = state?.accuracy.toStringAsFixed(1) ?? "--";
    final alt = state?.altitude.toStringAsFixed(0) ?? "--";
    final speed = state?.speedKmh.toStringAsFixed(0) ?? "0";

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                I18n.telemetryTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => SatelliteDetailScreen(
                        currentLat: state?.currentLat ?? 0.0,
                        currentLon: state?.currentLon ?? 0.0,
                        accuracy: state?.accuracy ?? 0.0,
                        altitude: state?.altitude ?? 0.0,
                        hasFix: hasFix,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasFix
                        ? (isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA))
                        : (isDark ? const Color(0xFF332200) : const Color(0xFFFFF3E0)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasFix ? I18n.hardwareFixActive : I18n.waitingForSatellites,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasFix
                              ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                              : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 12,
                        color: hasFix
                            ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                            : Colors.orange,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTelemetryItem(I18n.accuracyLabel, "±$accu m", isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC)),
              _buildTelemetryItem(I18n.altitudeLabel, "$alt m", isDark ? Colors.white : Colors.black87),
              _buildTelemetryItem(I18n.speedLabel, "$speed km/h", isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCoordinateCard(BuildContext context, NavigationState? state, bool isDark) {
    final lat = state?.currentLat ?? 0.0;
    final lon = state?.currentLon ?? 0.0;
    final hasFix = state != null && (lat != 0.0 || lon != 0.0);

    final latDms = MathUtils.decimalToDms(lat, true);
    final lonDms = MathUtils.decimalToDms(lon, false);

    final latDir = hasFix ? latDms.direction : "N";
    final latDeg = hasFix ? latDms.degrees.toString() : "--";
    final latMin = hasFix ? latDms.minutes.toString().padLeft(2, '0') : "--";
    final latSec = hasFix ? latDms.seconds.toStringAsFixed(1) : "--.-";

    final lonDir = hasFix ? lonDms.direction : "E";
    final lonDeg = hasFix ? lonDms.degrees.toString() : "---";
    final lonMin = hasFix ? lonDms.minutes.toString().padLeft(2, '0') : "--";
    final lonSec = hasFix ? lonDms.seconds.toStringAsFixed(1) : "--.-";

    final formattedCopy = hasFix
        ? "$latDir $latDeg°$latMin'$latSec\"  $lonDir $lonDeg°$lonMin'$lonSec\""
        : "N 00°00'00.0\" E 000°00'00.0\"";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                I18n.currentLocation,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: I18n.copyCoordinatesTooltip,
                onPressed: hasFix
                    ? () {
                        Clipboard.setData(ClipboardData(text: formattedCopy));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(I18n.copiedToast)),
                        );
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDmsRow(
                    dir: latDir,
                    deg: latDeg,
                    min: latMin,
                    sec: latSec,
                    color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildDmsRow(
                    dir: lonDir,
                    deg: lonDeg,
                    min: lonMin,
                    sec: lonSec,
                    color: isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDmsRow({
    required String dir,
    required String deg,
    required String min,
    required String sec,
    required Color color,
    required bool isDark,
  }) {
    final numStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
      color: color,
    );
    final unitStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white70 : Colors.black87,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            dir,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(deg, style: numStyle),
              Text("°", style: unitStyle),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(min, style: numStyle),
              Text("'", style: unitStyle),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(sec, style: numStyle),
              Text("\"", style: unitStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStandbyCompass(BuildContext context, NavigationState? state, bool isDark) {
    final heading = state?.currentHeading ?? 0.0;
    final headingInt = heading.round() % 360;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Text(
            "${headingInt.toString().padLeft(3, '0')}°  ${I18n.directionText(headingInt)}",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: isDark ? const Color(0xFFFFAA00) : const Color(0xFFCC6600),
            ),
          ),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: -heading * (math.pi / 180.0),
            child: CustomPaint(
              size: const Size(160, 160),
              painter: StandbyCompassPainter(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutSafetyDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              Icons.terrain,
              color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              size: 26,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "山海行 (TerraWay)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text("v${AppConfig.versionName}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                I18n.aboutSlogan,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFFFAA00) : const Color(0xFFCC6600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                I18n.aboutAppSubtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(height: 24),
              Text(
                I18n.safetyNoticeHeader,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildBulletPoint(I18n.safetyBullet1),
              _buildBulletPoint(I18n.safetyBullet2),
              _buildBulletPoint(I18n.safetyBullet3),
              _buildBulletPoint(I18n.safetyBullet4),
              const Divider(height: 24),
              Text(
                I18n.licenseSectionTitle,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                I18n.licenseSectionDesc,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateCtrl.checkManually(context);
            },
            child: Text(
              I18n.menuCheckUpdate,
              style: TextStyle(
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              I18n.agreeAndClose,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSelectRouteButton(BuildContext context, bool isDark) {
    final isNavActive = TrackRecorderService.instance.isRecording;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF080808) : Colors.white,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: isNavActive
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.navigation, size: 20),
                    label: Text(
                      I18n.returnToNavButton,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => const DashboardScreen(),
                        ),
                      );
                    },
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => const RoadbookListScreen(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.alt_route, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          I18n.selectRouteButtonShort,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios, size: 14),
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                  width: 1.5,
                ),
              ),
              icon: Icon(
                Icons.timeline,
                size: 20,
                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              ),
              label: Text(
                I18n.trackListTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const TrackListScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StandbyCompassPainter extends CustomPainter {
  final bool isDark;
  StandbyCompassPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final circlePaint = Paint()
      ..color = isDark ? const Color(0xFF222222) : const Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 8, circlePaint);

    final majorPaint = Paint()
      ..color = isDark ? Colors.white : Colors.black87
      ..strokeWidth = 2;
    final tickPaint = Paint()
      ..color = isDark ? Colors.grey : Colors.black38
      ..strokeWidth = 1;

    for (int deg = 0; deg < 360; deg += 30) {
      final isMajor = deg % 90 == 0;
      final len = isMajor ? 12.0 : 6.0;
      final rad = deg * (math.pi / 180.0);
      final p1 = Offset(center.dx + (radius - 10) * math.sin(rad), center.dy - (radius - 10) * math.cos(rad));
      final p2 = Offset(center.dx + (radius - 10 - len) * math.sin(rad), center.dy - (radius - 10 - len) * math.cos(rad));
      canvas.drawLine(p1, p2, isMajor ? majorPaint : tickPaint);
    }

    final northPath = Path();
    northPath.moveTo(center.dx, center.dy - radius + 14);
    northPath.lineTo(center.dx + 8, center.dy);
    northPath.lineTo(center.dx - 8, center.dy);
    northPath.close();
    canvas.drawPath(northPath, Paint()..color = const Color(0xFFFF2222));

    final southPath = Path();
    southPath.moveTo(center.dx, center.dy + radius - 14);
    southPath.lineTo(center.dx + 8, center.dy);
    southPath.lineTo(center.dx - 8, center.dy);
    southPath.close();
    canvas.drawPath(southPath, Paint()..color = isDark ? Colors.white38 : Colors.black26);
  }

  @override
  bool shouldRepaint(covariant StandbyCompassPainter oldDelegate) => oldDelegate.isDark != isDark;
}