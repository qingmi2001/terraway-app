// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航系统
// 模块名称: 全局应用版本与常量配置 (App Configuration)
// 文件职责: 单一事实来源 (Single Source of Truth) 管理客户端版本号与构建号，
//          杜绝版本号硬编码散落各处导致显示不一致。
// ==============================================================================

class AppConfig {
  /// 客户端语义化版本名称 (与 pubspec.yaml 同步)
  static const String versionName = '0.7.8';

  /// 客户端构建号 (与 pubspec.yaml 及 build.gradle 同步)
  static const int versionCode = 23;

  /// 应用全名
  static const String appDisplayName = '山海行 (TerraWay)';

  /// 签名说明
  static const String signatureDesc = '官方持久签名保障 (2020-2049)';
}
