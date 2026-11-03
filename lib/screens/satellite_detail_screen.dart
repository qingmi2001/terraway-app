// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 独立卫星连接遥测详情页 (Satellite Detail Screen)
// 文件职责: 严格按照 GPS 在上、北斗在下分层呈现全星历遥测、硬件自适应按需隐藏
// ==============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/gnss_service.dart';
import '../core/theme_controller.dart';
import '../core/locale_controller.dart';

/// 卫星连接情况与双模星历遥测详情页
class SatelliteDetailScreen extends StatefulWidget {
  final double currentLat;
  final double currentLon;
  final double accuracy;
  final double altitude;
  final bool hasFix;

  const SatelliteDetailScreen({
    super.key,
    this.currentLat = 0.0,
    this.currentLon = 0.0,
    this.accuracy = 0.0,
    this.altitude = 0.0,
    this.hasFix = true,
  });

  @override
  State<SatelliteDetailScreen> createState() => _SatelliteDetailScreenState();
}

class _SatelliteDetailScreenState extends State<SatelliteDetailScreen> {
  final GnssService _gnssService = GnssService();
  final ThemeController _themeCtrl = ThemeController.instance;
  final LocaleController _localeCtrl = LocaleController.instance;

  GnssData? _gnssData;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadGnssData();
    // 监听语言与主题状态
    _localeCtrl.addListener(_onLocaleChanged);
    // 开启 1Hz 实时刷新跟踪 (越野卫星动态感知)
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _loadGnssData(isBackground: true);
    });
  }

  @override
  void dispose() {
    _localeCtrl.removeListener(_onLocaleChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadGnssData({bool isBackground = false}) async {
    if (!isBackground) setState(() => _isLoading = true);
    final data = await _gnssService.fetchSatelliteStatus(hasFix: widget.hasFix);
    if (mounted) {
      setState(() {
        _gnssData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeCtrl,
      builder: (context, _) {
        final isDark = _themeCtrl.isDarkMode(context);
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF4F5F7),
          appBar: AppBar(
            title: Text(
              I18n.satelliteDetailsTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            elevation: 0,
            backgroundColor: isDark ? const Color(0xFF080808) : Colors.white,
            foregroundColor: isDark ? Colors.white : Colors.black87,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: I18n.refreshEphemeris,
                onPressed: () => _loadGnssData(),
              ),
            ],
          ),
          body: _isLoading && _gnssData == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(context, isDark),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    final data = _gnssData;
    if (data == null) {
      return Center(child: Text(I18n.noSatellitesFoundTitle));
    }

    // 检查手机支持情况：如果手机只有GPS或者只有北斗，按要求隐藏没有的框
    final showGps = data.hasGps && data.gpsSatellites.isNotEmpty;
    final showBeidou = data.hasBeidou && data.beidouSatellites.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        // 1. 顶部全局概览卡片 (总星数、解算数、水平精度、海拔)
        _buildSummaryOverviewCard(context, data, isDark),
        const SizedBox(height: 14),

        // 2. GPS 卫星列表 (严格要求：GPS在上面，中文写“GPS卫星导航”，英文写“GPS Navigation”，精简防溢出)
        if (showGps) ...[
          _buildConstellationSection(
            context: context,
            title: I18n.gpsNavTitle,
            systemCode: "GPS",
            satellites: data.gpsSatellites,
            usedCount: data.gpsUsedCount,
            avgCn0: data.gpsAvgCn0,
            accentColor: isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC),
            isDark: isDark,
          ),
          const SizedBox(height: 14),
        ],

        // 3. 北斗 卫星列表 (严格要求：北斗在下面，中文写“北斗卫星系统”，英文写“BeiDou System”，精简防溢出)
        if (showBeidou) ...[
          _buildConstellationSection(
            context: context,
            title: I18n.beidouNavTitle,
            systemCode: "BEIDOU",
            satellites: data.beidouSatellites,
            usedCount: data.beidouUsedCount,
            avgCn0: data.beidouAvgCn0,
            accentColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
            isDark: isDark,
          ),
          const SizedBox(height: 14),
        ],

        // 若当前手机完全搜不到两方卫星，给出开阔天空引导
        if (!showGps && !showBeidou) _buildNoSatellitesCard(isDark),
      ],
    );
  }

  /// 顶部双模连接概览卡片
  Widget _buildSummaryOverviewCard(BuildContext context, GnssData data, bool isDark) {
    String modeDesc = I18n.singleFixMode;
    if (data.hasGps && data.hasBeidou) {
      modeDesc = I18n.dualFixMode;
    } else if (data.hasBeidou) {
      modeDesc = I18n.beidouSingleFixMode;
    } else if (data.hasGps) {
      modeDesc = I18n.gpsSingleFixMode;
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
              Row(
                children: [
                  Icon(
                    Icons.cell_tower,
                    size: 18,
                    color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    modeDesc,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF142414) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.isHardwareDirect ? I18n.hardwareDirectLive : I18n.ephemerisSyncing,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildMetricTile(I18n.metricLockedCount, "${data.usedInFixCount}", isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)),
              _buildMetricTile(I18n.metricTotalInView, "${data.totalCount}", isDark ? Colors.white : Colors.black87),
              _buildMetricTile(I18n.metricAccuracy, widget.accuracy > 0 ? "±${widget.accuracy.toStringAsFixed(1)}m" : "±2.0m", isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
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

  /// 星座列表区域组件 (精简文字、Flexible 弹性布局，100% 杜绝屏幕横向溢出)
  Widget _buildConstellationSection({
    required BuildContext context,
    required String title,
    required String systemCode,
    required List<SatelliteInfo> satellites,
    required int usedCount,
    required double avgCn0,
    required Color accentColor,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片顶栏：标题缩短 + 弹性排布，彻底杜绝横向溢出
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        systemCode == "BEIDOU" ? Icons.stars : Icons.satellite_alt,
                        size: 20,
                        color: accentColor,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    I18n.lockedSatsBadge(usedCount, satellites.length),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),

          // 列表表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF141414) : const Color(0xFFF9FAFB),
            child: Row(
              children: [
                SizedBox(width: 46, child: Text(I18n.colPrn, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                SizedBox(width: 100, child: Text(I18n.colElevAzim, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                Expanded(child: Text(I18n.colSignal, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                SizedBox(width: 68, child: Text(I18n.colFixStatus, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
              ],
            ),
          ),

          // 卫星逐行列表
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: satellites.length,
            separatorBuilder: (ctx, i) => Divider(height: 1, indent: 16, endIndent: 16, color: Theme.of(context).dividerColor),
            itemBuilder: (ctx, i) {
              final sat = satellites[i];
              return _buildSatelliteRow(context, sat, isDark);
            },
          ),
        ],
      ),
    );
  }

  /// 单颗卫星数据行
  Widget _buildSatelliteRow(BuildContext context, SatelliteInfo sat, bool isDark) {
    Color barColor;
    if (sat.cn0 >= 40.0) {
      barColor = isDark ? const Color(0xFF00FF66) : const Color(0xFF008833);
    } else if (sat.cn0 >= 30.0) {
      barColor = isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC);
    } else if (sat.cn0 >= 20.0) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 卫星编号 (如 G03, B06)
          SizedBox(
            width: 46,
            child: Text(
              sat.prnCode,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: sat.usedInFix ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
              ),
            ),
          ),

          // 仰角与方位角 (如 48° / 135°)
          SizedBox(
            width: 100,
            child: Text(
              "${sat.elevation.toStringAsFixed(0)}° / ${sat.azimuth.toStringAsFixed(0)}°",
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),

          // 信号条与 dB-Hz 载噪比数值
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (sat.cn0 / 50.0).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: isDark ? const Color(0xFF222222) : const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: Text(
                    sat.cn0.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: barColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 解算有效徽章
          SizedBox(
            width: 68,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sat.usedInFix
                      ? (isDark ? const Color(0xFF003311) : const Color(0xFFE8F5E9))
                      : (isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  sat.usedInFix ? I18n.statusUsedInFix : I18n.statusSearching,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: sat.usedInFix
                        ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                        : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSatellitesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Icon(Icons.satellite_alt_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            I18n.noSatellitesFoundTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            I18n.noSatellitesFoundDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
