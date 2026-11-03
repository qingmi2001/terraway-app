// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 安全完整性与数字签名自校验模块 (Security Checker)
// 文件职责: 校验底层 Android 原生数字签名证书指纹，防止二进制篡改与恶意二次打包
// ==============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 防篡改与官方签名自校验核心类
class SecurityChecker {
  /// 官方正版持久化数字证书 SHA-256 签名指纹 (小写无冒号)
  /// 有效期: 2020-01-01 至 2049-12-24，全版本兼容
  static const String officialSignatureSha256 =
      "85a3acfbc3f7223e85fbfbdb6e2c2ddd28283732b6447743f9b5ef3b49f691b0";

  /// 校验应用完整性与官方签名证书指纹
  static Future<bool> verifyIntegrity() async {
    // 本地开发调试模式下放行
    if (kDebugMode) return true;

    try {
      const platform = MethodChannel('com.nmlyzx.gps/security');
      final String? currentSig = await platform.invokeMethod<String>('getSignatureSha256');
      if (currentSig == null || currentSig.isEmpty) {
        return true; // 容错放行
      }
      return currentSig.toLowerCase() == officialSignatureSha256;
    } catch (e) {
      // 离线容错放行
      return true;
    }
  }
}
