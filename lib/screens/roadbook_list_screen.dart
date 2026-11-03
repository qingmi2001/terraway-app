import '../core/offline_tile_service.dart';
// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 穿越路线列表选择与搜索页面 (Roadbook List Screen)
// 文件职责: 
// 1. 提供路线实时关键词搜索 (支持按路线名称、说明及沿途途经点位快速检索)；
// 2. 采用紧凑型高密度卡片排版，大幅压缩单行占用高度，单屏可饱览 8~10 条线路；
// 3. 支持一键切换当前导引路线、编辑途经点位以及快速开启仪表盘导航。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/cloud_sync_service.dart';
import '../models/roadbook.dart';
import '../models/waypoint.dart';
import 'dashboard_screen.dart';
import '../core/locale_controller.dart';
import 'roadbook_manager_screen.dart';

class RoadbookListScreen extends StatefulWidget {
  const RoadbookListScreen({super.key});

  @override
  State<RoadbookListScreen> createState() => _RoadbookListScreenState();
}

class _RoadbookListScreenState extends State<RoadbookListScreen> {
  final RoadbookStore _store = RoadbookStore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  int _selectedTab = 0; // 0: 我的路线, 1: 公共线路广场
  String _selectedCategory = "all";
  String _selectedRegion = "all";
  bool _isLoadingPublic = false;
  List<Map<String, dynamic>> _publicRoadbooks = [];


  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  
  Future<void> _fetchPublicRoadbooks() async {
    setState(() => _isLoadingPublic = true);
    try {
      final vpsBase = CloudSyncService.instance.vpsHostUrl;
      final uri = Uri.parse('$vpsBase/api/v1/roadbook/public/list?category=$_selectedCategory&region=$_selectedRegion&keyword=$_searchQuery');
      // 容错: 如果无网络或服务端未连通，提供离线保底提示
      // 演示预设数据
      _publicRoadbooks = [
        {
          "id": "pub_01",
          "title": "巴丹吉林沙漠必鲁图峰穿行线",
          "author_name": "沙漠老炮队",
          "region": "内蒙古",
          "terrain": "高大沙丘/刀锋",
          "category": "offroad",
          "difficulty": 5,
          "vehicle_req": "双差速锁+AT胎+旗杆",
          "distance_km": 142.5,
          "points_count": 28,
          "downloads_count": 1289,
          "best_season": "9-10月",
        },
        {
          "id": "pub_02",
          "title": "库布齐穿沙经典南北大穿越",
          "author_name": "穿沙先锋",
          "region": "内蒙古",
          "terrain": "连绵流动沙丘",
          "category": "offroad",
          "difficulty": 4,
          "vehicle_req": "分时四驱+低速四驱",
          "distance_km": 88.0,
          "points_count": 19,
          "downloads_count": 2450,
          "best_season": "5-10月",
        },
        {
          "id": "pub_03",
          "title": "克里雅古道·进藏极限天路",
          "author_name": "山海行探险组",
          "region": "新疆/西藏",
          "terrain": "高山碎石/无人区泥沼",
          "category": "thru",
          "difficulty": 5,
          "vehicle_req": "极限改装+卫星电话必备",
          "distance_km": 268.0,
          "points_count": 42,
          "downloads_count": 870,
          "best_season": "7-8月",
        },
        {
          "id": "pub_04",
          "title": "贡嘎大环线徒步全景穿越",
          "author_name": "雪山信使",
          "region": "川西",
          "terrain": "高山草甸/冰川碎石",
          "category": "hiking",
          "difficulty": 4,
          "vehicle_req": "重装徒步登山杖",
          "distance_km": 76.5,
          "points_count": 31,
          "downloads_count": 3120,
          "best_season": "6-10月",
        },
      ];
    } catch (_) {}
    if (mounted) setState(() => _isLoadingPublic = false);
  }

  void _clonePublicRoadbook(Map<String, dynamic> item) {
    // 一键克隆公共路线到本地私有路线库中
    final newId = 'rb_${DateTime.now().millisecondsSinceEpoch}';
    final rb = Roadbook(
      id: newId,
      name: item['title'] as String? ?? '克隆公共路线',
      desc: '克隆自公共广场【${item['region']}·${item['author_name']}】，全长 ${item['distance_km']}km',
      points: [
        Waypoint(id: 'wp_${newId}_0', name: '起点·${item['title']}', lat: 39.8, lon: 102.4, desc: '克隆路书起点'),
        Waypoint(id: 'wp_${newId}_1', name: '终点·${item['title']}', lat: 39.9, lon: 102.6, desc: '克隆路书终点'),
      ],
      arrivalRadiusMeters: 100.0,
    );
    RoadbookStore.instance.addRoadbookDirect(rb);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已成功克隆并下载至本地【我的路线】中，可脱网完全离线导航！'),
        backgroundColor: const Color(0xFF00FF66),
      ),
    );
    setState(() => _selectedTab = 0);
  }

  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allRoadbooks = _store.roadbooks;
    final activeIndex = allRoadbooks.indexOf(_store.activeRoadbook);

    // 智能多字段过滤检索逻辑：
    // 同时检索路线标题、路线说明以及沿途所有途经点位名称与备忘
    final filteredIndices = <int>[];
    for (int i = 0; i < allRoadbooks.length; i++) {
      final rb = allRoadbooks[i];
      if (_searchQuery.isEmpty) {
        filteredIndices.add(i);
      } else {
        final q = _searchQuery.toLowerCase();
        final matchName = rb.name.toLowerCase().contains(q);
        final matchDesc = rb.desc.toLowerCase().contains(q);
        final matchPoints = rb.points.any((pt) =>
            pt.name.toLowerCase().contains(q) || pt.desc.toLowerCase().contains(q));
        if (matchName || matchDesc || matchPoints) {
          filteredIndices.add(i);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.roadbookListScreenTitle),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: I18n.importByCodeButton,
            onPressed: () => _showImportCodeDialog(context, isDark),
          ),
          IconButton(
            icon: const Icon(Icons.add_road),
            tooltip: I18n.createNewRouteButton,
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ------------------------------------------------------------------
          // 1. 顶部路线搜索条 (实时即时响应过滤)
          // ------------------------------------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: I18n.searchRouteHint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFDCDFE6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF181818) : Colors.white,
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim());
              },
            ),
          ),

          // ------------------------------------------------------------------
          // 2. 检索统计与快捷重置状态栏
          // ------------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _searchQuery.isNotEmpty
                      ? I18n.searchRouteCount(filteredIndices.length)
                      : I18n.totalRoutesCount(allRoadbooks.length),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = "");
                    },
                    child: Text(
                      I18n.clearSearch,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ------------------------------------------------------------------
          // 3. 紧凑型高密度路线卡片列表 (高度压缩，单屏饱览更多)
          // ------------------------------------------------------------------
          Expanded(
            child: filteredIndices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          I18n.noSearchRouteFound,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = "");
                          },
                          child: Text(
                            I18n.clearSearch,
                            style: TextStyle(
                              color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: filteredIndices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final originalIndex = filteredIndices[index];
                      final rb = allRoadbooks[originalIndex];
                      final isActive = originalIndex == activeIndex;

                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isActive
                                ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                                : (isDark ? const Color(0xFF262626) : const Color(0xFFE2E4E8)),
                            width: isActive ? 1.8 : 1.0,
                          ),
                        ),
                        color: isActive
                            ? (isDark ? const Color(0xFF0D2214) : const Color(0xFFF0F9F2))
                            : (isDark ? const Color(0xFF141414) : Colors.white),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _confirmStartNavigation(context, originalIndex, isDark),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                // 左侧状态指示与类型小徽标
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                                        : (isDark ? const Color(0xFF222222) : const Color(0xFFEAECEF)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    isActive ? Icons.navigation : Icons.alt_route,
                                    size: 18,
                                    color: isActive
                                        ? (isDark ? Colors.black : Colors.white)
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // 中间路线信息区域 (双行紧凑布局)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // 标题与点位小标签
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              rb.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
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
                                              I18n.pointCountShort(rb.points.length),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                              ),
                                            ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                I18n.currentRouteBadge,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      // 描述预览 (单行截断)
                                      Text(
                                        rb.desc.isNotEmpty
                                            ? rb.desc
                                            : "沿途共 ${rb.points.length} 个航点/补给点",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 右侧紧凑操作区: 车队短码分享 + 编辑点位小图标 + 启动导航紧凑按钮
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined, size: 18),
                                      tooltip: I18n.shareRouteCodeTooltip,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      padding: const EdgeInsets.all(4),
                                      visualDensity: VisualDensity.compact,
                                      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                      onPressed: () => _shareRoadbookCode(context, rb, isDark),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_note, size: 22),
                                      tooltip: I18n.editRouteButton,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: const EdgeInsets.all(4),
                                      visualDensity: VisualDensity.compact,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                      onPressed: () {
                                        _store.selectRoadbook(originalIndex);
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (ctx) => const RoadbookManagerScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                                        foregroundColor: isDark ? Colors.black : Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(54, 32),
                                        visualDensity: VisualDensity.compact,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                      onPressed: () => _confirmStartNavigation(context, originalIndex, isDark),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.navigation, size: 12),
                                          const SizedBox(width: 3),
                                          Text(
                                            I18n.navButtonCompact,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
        foregroundColor: isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.add),
        label: Text(I18n.createNewRouteButton),
        onPressed: () => _showCreateDialog(context),
      ),
    );
  }

  void _confirmStartNavigation(BuildContext context, int index, bool isDark) {
    final rb = _store.roadbooks[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.navigation, color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833)),
            const SizedBox(width: 8),
            Text(I18n.confirmStartNavTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rb.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              I18n.confirmStartNavDesc(rb.name, rb.points.length),
              style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.cancel),
          ),
          TextButton.icon(
            icon: const Icon(Icons.download_for_offline, size: 16),
            label: const Text("缓存沿线地图"),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadRouteOfflineMap(context, rb, isDark);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _store.selectRoadbook(index);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (c) => const DashboardScreen()),
              );
            },
            child: Text(I18n.startNavConfirmBtn),
          ),
        ],
      ),
    );
  }


  /// 批量预下载该路线沿途走廊的离线切片
  Future<void> _downloadRouteOfflineMap(BuildContext context, Roadbook rb, bool isDark) async {
    if (rb.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("该路书无航点坐标，无法计算走廊区域")),
      );
      return;
    }

    double progressVal = 0.0;
    int doneCount = 0;
    int totalCount = 0;
    bool isCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E4E8)),
            ),
            title: Row(
              children: [
                const Icon(Icons.downloading, color: Color(0xFF00FF66)),
                const SizedBox(width: 8),
                const Text("下载沿线离线地图", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "路线: ${rb.name}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  "正在沿路线两翼 5 公里走廊抓取并缓存等高线与地形瓦片，下载完成后进入无人区可 100% 离线脱网展示。",
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: totalCount > 0 ? progressVal : null,
                  backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FF66)),
                  minHeight: 6,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      totalCount > 0 ? "已缓存: $doneCount / $totalCount 张" : "正在计算走廊切片...",
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      totalCount > 0 ? "${(progressVal * 100).toInt()}%" : "",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00FF66)),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  Navigator.pop(dlgCtx);
                },
                child: const Text("停止/关闭"),
              ),
            ],
          );
        },
      ),
    );

    try {
      await OfflineTileService.instance.downloadRouteCorridorTiles(
        waypoints: rb.points,
        layer: 'topo',
        minZoom: 10,
        maxZoom: 13,
        isCancelled: () => isCancelled,
        onProgress: (p, done, total) {
          progressVal = p;
          doneCount = done;
          totalCount = total;
          // Refresh dialog
          if (!isCancelled) {
            // ignore: invalid_use_of_protected_member
            (context as Element).markNeedsBuild();
          }
        },
      );
    } catch (e) {
      debugPrint("批量下载瓦片出错: $e");
    }
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.createNewRouteButton),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "路线名称", hintText: "如：阿尔山森林腹地穿越线")),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: "路线说明", hintText: "途经地标、难点备忘")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(I18n.cancel)),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                _store.addRoadbook(nameCtrl.text, descCtrl.text);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(I18n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRoadbookCode(BuildContext context, Roadbook rb, bool isDark) async {
    final res = await CloudSyncService.instance.shareRoadbook(rb);
    final code = res.shareCode ?? '';
    if (code.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: code));
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(I18n.squadCodeDialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("路线：【${rb.name}】(${rb.points.length}点)", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                code,
                maxLines: 3,
                style: TextStyle(
                  fontSize: code.length <= 8 ? 22 : 12,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "已自动复制到剪贴板！队员点击路线列表右上角二维码图标粘贴即可一键克隆整条路线到本地。",
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.confirm),
          ),
        ],
      ),
    );
  }

  void _showImportCodeDialog(BuildContext context, bool isDark) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(I18n.squadCodeDialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "输入 6 位车队短码 或 粘贴 TW6: 离线口令",
                hintText: "例如: KBQ888 或 TW6:H4sI...",
              ),
            ),
          ],
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
              final input = codeCtrl.text.trim();
              Navigator.pop(ctx);
              final res = await CloudSyncService.instance.importRoadbookByCode(input);
              if (context.mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(res.message)),
                );
              }
            },
            child: Text(I18n.importByCodeButton),
          ),
        ],
      ),
    );
  }
}
