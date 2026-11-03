// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 路书点位管理与度分秒录入页面 (Roadbook Manager Screen)
// 文件职责: 支持最多 200 点航点增删改查、半球度分秒规范分立录入、GPS 现场实地打点
//          以及实时滑动调整到达换向判定半径 (30m~300m)
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/math_utils.dart';
import '../core/locale_controller.dart';
import '../models/roadbook.dart';
import '../models/waypoint.dart';

class RoadbookManagerScreen extends StatefulWidget {
  const RoadbookManagerScreen({super.key});

  @override
  State<RoadbookManagerScreen> createState() => _RoadbookManagerScreenState();
}

class _RoadbookManagerScreenState extends State<RoadbookManagerScreen> {
  final RoadbookStore _store = RoadbookStore.instance;
  final LocaleController _localeCtrl = LocaleController.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onRefresh);
    _localeCtrl.addListener(_onRefresh);
  }

  @override
  void dispose() {
    _store.removeListener(_onRefresh);
    _localeCtrl.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rb = _store.activeRoadbook;

    return Scaffold(
      appBar: AppBar(
        title: Text(rb.name),
        actions: [
          // 切换路书
          PopupMenuButton<int>(
            icon: const Icon(Icons.route),
            tooltip: "切换其它穿越路书",
            onSelected: (idx) => _store.selectRoadbook(idx),
            itemBuilder: (ctx) => List.generate(_store.roadbooks.length, (i) {
              final item = _store.roadbooks[i];
              final isSel = i == _store.roadbooks.indexOf(rb);
              return PopupMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(Icons.alt_route, size: 18, color: isSel ? const Color(0xFF00AA44) : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? const Color(0xFF00AA44) : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add_road),
            tooltip: "新建路书航线",
            onPressed: () => _showCreateRoadbookDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 路线头部概览条 (当前站 / 总点数 / 判定半径)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? const Color(0xFF141414) : const Color(0xFFEAECEF),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "点位数量: ${rb.points.length} / ${Roadbook.maxPointsLimit} (上限200点)",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                InkWell(
                  onTap: () => _showRadiusDialog(context, rb),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF222222) : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isDark ? const Color(0xFF444444) : Colors.black26),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.adjust, size: 14, color: Color(0xFF00AA44)),
                        const SizedBox(width: 4),
                        Text(
                          "到达半径: ${rb.arrivalRadiusMeters.toInt()}m",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 航点列表
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: rb.points.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final pt = rb.points[index];
                final isCurrent = index == rb.currentTargetIndex;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isCurrent
                          ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                          : (isDark ? const Color(0xFF242424) : const Color(0xFFE0E0E0)),
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isCurrent
                          ? (isDark ? const Color(0xFF00FF66) : const Color(0xFF008833))
                          : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD0D0D0)),
                      foregroundColor: isCurrent
                          ? Colors.black
                          : (isDark ? Colors.white70 : Colors.black87),
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            pt.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF003311) : const Color(0xFFE6F4EA),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "当前导引站",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          "${MathUtils.formatCoordinate(pt.lat, true)}  ${MathUtils.formatCoordinate(pt.lon, false)}",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF00FFFF) : const Color(0xFF0066CC),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (pt.desc.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            pt.desc,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: "修改此点",
                          onPressed: () => _showAddEditPointDialog(context, index, pt),
                        ),
                        if (rb.points.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                            tooltip: "删除此点",
                            onPressed: () => _store.removePointFromActiveRoadbook(index),
                          ),
                      ],
                    ),
                    onTap: () {
                      // 点击直接将其设为当前导引站，并退出返回仪表盘
                      rb.jumpToPoint(index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("已锁定第 ${index + 1} 站目标：${pt.name}"),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_location),
                  label: Text(I18n.addWaypointButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _showAddEditPointDialog(context, null, null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: Text(I18n.pinGpsButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF00FF66) : const Color(0xFF008833),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _quickAddCurrentGpsPoint(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一键读取当前车位并追加到路书末尾 (极其适合越野实车勘路快速打点)
  Future<void> _quickAddCurrentGpsPoint(BuildContext context) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 4),
      );
      final index = _store.activeRoadbook.points.length + 1;
      final wp = Waypoint(
        id: 'pt_${DateTime.now().millisecondsSinceEpoch}',
        name: '现场打点·P$index',
        lat: pos.latitude,
        lon: pos.longitude,
        desc: '越野实地勘测打点 (海拔: ${pos.altitude.toStringAsFixed(0)}m)',
      );
      final ok = _store.addPointToActiveRoadbook(wp);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已追加新航点：P$index (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("已达到 200 个点位上限")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("获取当前 GPS 失败: $e")),
      );
    }
  }

  void _showAddEditPointDialog(BuildContext context, int? index, Waypoint? wp) {
    final isEditing = wp != null;
    final nameCtrl = TextEditingController(text: wp?.name ?? 'P${_store.activeRoadbook.points.length + 1}');
    final descCtrl = TextEditingController(text: wp?.desc ?? '');

    // 解析已有坐标或初始化度分秒
    String latDir = "N";
    int latDeg = 40;
    int latMin = 0;
    double latSec = 0.0;

    String lonDir = "E";
    int lonDeg = 108;
    int lonMin = 0;
    double lonSec = 0.0;

    if (wp != null) {
      final dLat = MathUtils.decimalToDms(wp.lat, true);
      latDir = dLat.direction;
      latDeg = dLat.degrees;
      latMin = dLat.minutes;
      latSec = dLat.seconds;

      final dLon = MathUtils.decimalToDms(wp.lon, false);
      lonDir = dLon.direction;
      lonDeg = dLon.degrees;
      lonMin = dLon.minutes;
      lonSec = dLon.seconds;
    }

    final latDegCtrl = TextEditingController(text: latDeg.toString());
    final latMinCtrl = TextEditingController(text: latMin.toString());
    final latSecCtrl = TextEditingController(text: latSec.toStringAsFixed(1));

    final lonDegCtrl = TextEditingController(text: lonDeg.toString());
    final lonMinCtrl = TextEditingController(text: lonMin.toString());
    final lonSecCtrl = TextEditingController(text: lonSec.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? "修改第 ${index! + 1} 站坐标" : "向路书录入度分秒点位"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "航点名称", hintText: "如：大沙山入口、扎营地"),
                ),
                const SizedBox(height: 14),

                // 纬度度分秒录入 (如: N 40° 04' 55.9")
                Row(
                  children: [
                    DropdownButton<String>(
                      value: latDir,
                      items: const [
                        DropdownMenuItem(value: "N", child: Text("北纬 N")),
                        DropdownMenuItem(value: "S", child: Text("南纬 S")),
                      ],
                      onChanged: (val) => setDialogState(() => latDir = val ?? "N"),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: latDegCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "度 (°)", suffixText: "°"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: latMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "分 (')", suffixText: "'"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: latSecCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '秒 (0~59.9")', suffixText: '秒'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 经度度分秒录入 (如: E 108° 39' 03.9")
                Row(
                  children: [
                    DropdownButton<String>(
                      value: lonDir,
                      items: const [
                        DropdownMenuItem(value: "E", child: Text("东经 E")),
                        DropdownMenuItem(value: "W", child: Text("西经 W")),
                      ],
                      onChanged: (val) => setDialogState(() => lonDir = val ?? "E"),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: lonDegCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "度 (°)", suffixText: "°"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: lonMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "分 (')", suffixText: "'"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: lonSecCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '秒 (0~59.9")', suffixText: '秒'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 读取当前 GPS 物理坐标自动解析为度分秒
                OutlinedButton.icon(
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text("读取当前 GPS 转换为度分秒填入"),
                  onPressed: () async {
                    try {
                      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
                      final dLat = MathUtils.decimalToDms(pos.latitude, true);
                      final dLon = MathUtils.decimalToDms(pos.longitude, false);

                      setDialogState(() {
                        latDir = dLat.direction;
                        latDegCtrl.text = dLat.degrees.toString();
                        latMinCtrl.text = dLat.minutes.toString();
                        latSecCtrl.text = dLat.seconds.toStringAsFixed(1);

                        lonDir = dLon.direction;
                        lonDegCtrl.text = dLon.degrees.toString();
                        lonMinCtrl.text = dLon.minutes.toString();
                        lonSecCtrl.text = dLon.seconds.toStringAsFixed(1);
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("读取失败: $e")));
                    }
                  },
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "避险与路况备忘",
                    hintText: "如：避开南侧暗坑和流沙、水源点、绞盘脱困点",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(I18n.cancel)),
            ElevatedButton(
              onPressed: () {
                final dDegLat = int.tryParse(latDegCtrl.text.trim()) ?? 0;
                final dMinLat = int.tryParse(latMinCtrl.text.trim()) ?? 0;
                final dSecLat = double.tryParse(latSecCtrl.text.trim()) ?? 0.0;

                final dDegLon = int.tryParse(lonDegCtrl.text.trim()) ?? 0;
                final dMinLon = int.tryParse(lonMinCtrl.text.trim()) ?? 0;
                final dSecLon = double.tryParse(lonSecCtrl.text.trim()) ?? 0.0;

                // 校验度分秒有效性
                if (dDegLat < 0 || dDegLat > 90 || dMinLat < 0 || dMinLat >= 60 || dSecLat < 0 || dSecLat >= 60) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("纬度输入有误：分/秒需在 0~59 之间")));
                  return;
                }
                if (dDegLon < 0 || dDegLon > 180 || dMinLon < 0 || dMinLon >= 60 || dSecLon < 0 || dSecLon >= 60) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("经度输入有误：分/秒需在 0~59 之间")));
                  return;
                }

                final latDec = MathUtils.dmsToDecimal(latDir, dDegLat, dMinLat, dSecLat);
                final lonDec = MathUtils.dmsToDecimal(lonDir, dDegLon, dMinLon, dSecLon);

                if (isEditing) {
                  _store.updatePointInActiveRoadbook(index!, nameCtrl.text, latDec, lonDec, descCtrl.text);
                } else {
                  final newWp = Waypoint(
                    id: 'pt_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text,
                    lat: latDec,
                    lon: lonDec,
                    desc: descCtrl.text,
                  );
                  _store.addPointToActiveRoadbook(newWp);
                }
                Navigator.of(ctx).pop();
              },
              child: Text(I18n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateRoadbookDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: "新穿越路书");
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("创建新多点穿越路书"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "路书名称")),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: "路书简介")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(I18n.cancel)),
          ElevatedButton(
            onPressed: () {
              _store.addRoadbook(nameCtrl.text, descCtrl.text);
              Navigator.of(ctx).pop();
            },
            child: const Text("创建"),
          ),
        ],
      ),
    );
  }

  void _showRadiusDialog(BuildContext context, Roadbook rb) {
    double tempVal = rb.arrivalRadiusMeters;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text("到达换向判定半径"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("当车辆距离当前点位 ≤ ${tempVal.toInt()} 米时，系统判定已到达并自动将指针切向下一站。"),
              const SizedBox(height: 16),
              Slider(
                value: tempVal,
                min: 30,
                max: 300,
                divisions: 27,
                label: "${tempVal.toInt()}米",
                onChanged: (v) => setDlgState(() => tempVal = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(I18n.cancel)),
            ElevatedButton(
              onPressed: () {
                _store.setArrivalRadius(tempVal);
                Navigator.of(ctx).pop();
              },
              child: Text(I18n.confirm),
            ),
          ],
        ),
      ),
    );
  }
}
