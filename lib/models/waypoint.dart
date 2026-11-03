// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 航点数据实体 (Waypoint Model)
// 文件职责: 定义户外路书单点实体，包含航点名称、WGS-84 经纬度与避险备忘字段
// ==============================================================================

/// 户外路书单点实体 (Waypoint)
class Waypoint {
  final String id;      // 航点唯一标识符 (时间戳或预置 ID)
  String name;          // 航点易读名称 (如: S1·北线集结大本营)
  double lat;           // 纬度 (WGS-84 十进制双精度)
  double lon;           // 经度 (WGS-84 十进制双精度)
  String desc;          // 避险与实操备忘 (如: 避开南侧暗坑和流沙、深水井位置)
  final bool isPreset;  // 是否为官方出厂预置经典路标

  Waypoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.desc = '',
    this.isPreset = false,
  });

  /// 浅拷贝更新对象属性
  Waypoint copyWith({
    String? name,
    double? lat,
    double? lon,
    String? desc,
  }) {
    return Waypoint(
      id: id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      desc: desc ?? this.desc,
      isPreset: isPreset,
    );
  }
}
