// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: APP 版本在线更新检测提醒与一键升级服务 (Update Checker Service)
// 文件职责:
// 1. 开机非阻塞静默检测新版本 (断网/飞行模式下 0 报错静默跳过，100% 保障脱网可用)；
// 2. 支持自建 VPS 接口 (/api/v1/app/check_update) 与 GitHub Releases 双通道自动回退；
// 3. 弹出符合 7:1 高反差工业风规范的更新提醒弹窗 (支持常规忽略、红点提醒与强制更新)；
// 4. 一键调起 Android 原生系统下载器/浏览器拉取最新签名 APK 进行无损覆盖安装。
// ==============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';
import 'app_style.dart';
import 'locale_controller.dart';
import 'cloud_sync_service.dart';

/// 远端版本发布信息实体
class AppReleaseInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String apkSha256;
  final double apkSizeMb;
  final String changelogZh;
  final String changelogEn;
  final bool isForced;
  final String releaseDate;

  const AppReleaseInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.apkSha256 = '',
    this.apkSizeMb = 18.5,
    required this.changelogZh,
    required this.changelogEn,
    this.isForced = false,
    required this.releaseDate,
  });

  String get localizedChangelog => I18n.isZh ? changelogZh : changelogEn;

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    final rawChangelog = json['changelog'] as String? ?? '';
    return AppReleaseInfo(
      versionCode: (json['version_code'] as num?)?.toInt() ?? 15,
      versionName: json['version_name'] as String? ?? '0.7.0',
      apkUrl: json['apk_url'] as String? ?? '',
      apkSha256: json['apk_sha256'] as String? ?? '',
      apkSizeMb: (json['apk_size_mb'] as num?)?.toDouble() ?? 18.5,
      changelogZh: json['changelog_zh'] as String? ??
          (rawChangelog.isNotEmpty ? rawChangelog : '1. 优化离线卫星定位与轨迹稳定性\n2. 提升极端环境高反差显示体验'),
      changelogEn: json['changelog_en'] as String? ??
          (rawChangelog.isNotEmpty ? rawChangelog : '1. Improved offline GNSS stability\n2. Enhanced high-contrast display'),
      isForced: json['is_forced'] == true || json['is_forced'] == 1,
      releaseDate: json['release_date'] as String? ?? '2026-11-02',
    );
  }
}

/// 全局 APP 版本更新检测与提醒控制器 (单例 + ChangeNotifier)
class UpdateCheckerService with ChangeNotifier {
  static final UpdateCheckerService instance = UpdateCheckerService._internal();
  factory UpdateCheckerService() => instance;
  UpdateCheckerService._internal();

  /// 当前客户端编译固化的版本号与构建号 (v0.7.0+15)
  static const int currentVersionCode = AppConfig.versionCode;
  static const String currentVersionName = AppConfig.versionName;

  /// 备用 GitHub Releases 自动检测地址 (当自建 VPS 未配置或不可达时自动兜底)
  static const String fallbackGithubReleaseApi =
      'https://api.github.com/repos/qingmi2001/terraway-app/releases/latest';

  static const String _prefIgnoredVersionKey = 'terraway_ignored_version_code';
  static const MethodChannel _systemChannel = MethodChannel('com.nmlyzx.gps/system');

  AppReleaseInfo? _latestRelease;
  bool _isChecking = false;
  bool _hasCheckedOnStartup = false;
  int _ignoredVersionCode = 0;

  AppReleaseInfo? get latestRelease => _latestRelease;
  bool get isChecking => _isChecking;

  /// 是否存在高于当前客户端的新版本
  bool get hasUpdate =>
      _latestRelease != null && _latestRelease!.versionCode > currentVersionCode;

  /// 开机非阻塞静默检测 (延迟 2.5 秒执行，绝不阻塞北斗/GPS 搜星与首屏渲染)
  Future<void> checkOnStartup(BuildContext context) async {
    if (_hasCheckedOnStartup) return;
    _hasCheckedOnStartup = true;

    await Future.delayed(const Duration(milliseconds: 2500));
    if (!context.mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _ignoredVersionCode = prefs.getInt(_prefIgnoredVersionKey) ?? 0;
    } catch (_) {}

    final release = await fetchLatestReleaseSilently();
    if (release != null && release.versionCode > currentVersionCode) {
      // 若为强制更新，或用户尚未忽略该版本，则自动弹出高反差更新提醒窗
      if (release.isForced || release.versionCode > _ignoredVersionCode) {
        if (context.mounted) {
          showUpdateDialog(context, release);
        }
      }
    }
  }

  /// 用户在探险者抽屉中手动点击【检查版本更新】
  Future<void> checkManually(BuildContext context) async {
    if (_isChecking) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.checkingUpdateToast),
        duration: const Duration(seconds: 2),
      ),
    );

    final release = await fetchLatestReleaseSilently(timeoutSeconds: 6);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (release == null) {
      // 处于纯离线/飞行模式或服务器未响应时的友好提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.updateCheckOfflineToast),
          backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFF475569),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (release.versionCode > currentVersionCode) {
      showUpdateDialog(context, release);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.alreadyLatestVersionToast(currentVersionName)),
          backgroundColor: const Color(0xFF00AA44),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 核心静默探测逻辑：优先查询 VPS `/api/v1/app/check_update`，失败则回退 GitHub Releases
  Future<AppReleaseInfo?> fetchLatestReleaseSilently({int timeoutSeconds = 4}) async {
    _isChecking = true;
    notifyListeners();

    try {
      final baseUrl = await CloudSyncService.instance.getServerBaseUrl();
      if (baseUrl.isNotEmpty) {
        final vpsResult = await _queryVpsRelease(
          '$baseUrl/api/v1/app/check_update?current_code=$currentVersionCode',
          timeoutSeconds: timeoutSeconds,
        );
        if (vpsResult != null) {
          _latestRelease = vpsResult;
          _isChecking = false;
          notifyListeners();
          return vpsResult;
        }
      }

      // 回退检测 GitHub Releases 最新 Tag
      final ghResult = await _queryGithubRelease(timeoutSeconds: timeoutSeconds);
      if (ghResult != null) {
        _latestRelease = ghResult;
      }
      _isChecking = false;
      notifyListeners();
      return _latestRelease;
    } catch (_) {
      // 离线/飞行模式下完全静默吞掉网络异常，保持 100% 脱网纯净体验
      _isChecking = false;
      notifyListeners();
      return null;
    }
  }

  Future<AppReleaseInfo?> _queryVpsRelease(String url, {required int timeoutSeconds}) async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSeconds);
    try {
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri).timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'TerraWay-GPS/$currentVersionName');
      final resp = await req.close().timeout(Duration(seconds: timeoutSeconds));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final payload = data['data'] is Map<String, dynamic>
            ? data['data'] as Map<String, dynamic>
            : data;
        return AppReleaseInfo.fromJson(payload);
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<AppReleaseInfo?> _queryGithubRelease({required int timeoutSeconds}) async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSeconds);
    try {
      final uri = Uri.parse(fallbackGithubReleaseApi);
      final req = await client.getUrl(uri).timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'TerraWay-GPS/$currentVersionName');
      final resp = await req.close().timeout(Duration(seconds: timeoutSeconds));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String? ?? 'v0.7.0').replaceFirst(RegExp(r'^[vV]'), '');
        final publishedAt = (data['published_at'] as String? ?? '2026-11-02').split('T').first;
        final notes = data['body'] as String? ?? '';

        String downloadUrl = '';
        double sizeMb = 18.5;
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final item in assets) {
          if (item is Map<String, dynamic>) {
            final dl = item['browser_download_url'] as String? ?? '';
            if (dl.endsWith('.apk')) {
              downloadUrl = dl;
              final bytes = (item['size'] as num?)?.toDouble() ?? 0.0;
              if (bytes > 0) sizeMb = bytes / (1024.0 * 1024.0);
              break;
            }
          }
        }

        final parsedCode = _versionNameToCode(tagName);
        return AppReleaseInfo(
          versionCode: parsedCode,
          versionName: tagName,
          apkUrl: downloadUrl,
          apkSizeMb: sizeMb,
          changelogZh: notes.isNotEmpty ? notes : '发现新版本 v$tagName，建议升级以获取最新离线导航功能。',
          changelogEn: notes.isNotEmpty ? notes : 'New release v$tagName is available.',
          isForced: false,
          releaseDate: publishedAt,
        );
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  int _versionNameToCode(String vName) {
    // 已知历史映射: 0.6.0 -> 14, 0.7.0 -> 15, 0.8.0 -> 16, 0.9.0 -> 17, 1.0.0 -> 18
    final clean = vName.split('+').first.trim();
    if (clean == '0.6.0') return 14;
    if (clean == '0.7.0') return 15;
    if (clean == '0.8.0') return 16;
    if (clean == '0.9.0') return 17;
    if (clean == '1.0.0') return 18;
    final parts = clean.split('.');
    if (parts.length >= 3) {
      final major = int.tryParse(parts[0]) ?? 0;
      final minor = int.tryParse(parts[1]) ?? 7;
      final patch = int.tryParse(parts[2]) ?? 0;
      return major * 100 + minor * 10 + patch + 8;
    }
    return 15;
  }

  /// 记录用户忽略当前非强制更新版本
  Future<void> ignoreVersion(int versionCode) async {
    _ignoredVersionCode = versionCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefIgnoredVersionKey, versionCode);
    } catch (_) {}
    notifyListeners();
  }

  /// 一键调起系统浏览器/系统下载管理器拉取 APK 安装包
  Future<bool> launchApkDownload(BuildContext context, String apkUrl) async {
    if (apkUrl.trim().isEmpty) return false;

    // 智能防阻断：若下载链接指向外部 GitHub，而客户端已配置了自建 VPS，强制转换为 VPS 专属直链
    String targetUrl = apkUrl.trim();
    try {
      final vpsBase = await CloudSyncService.instance.getServerBaseUrl();
      if (vpsBase.isNotEmpty && targetUrl.contains('github.com')) {
        targetUrl = '$vpsBase/api/v1/app/download/latest';
      }
    } catch (_) {}

    try {
      final ok = await _systemChannel.invokeMethod<bool>(
        'openExternalUrl',
        {'url': targetUrl},
      );
      if (ok == true) return true;
    } catch (_) {}

    // 保底方案：自动复制下载直链到剪贴板并提示用户在浏览器打开
    await Clipboard.setData(ClipboardData(text: apkUrl.trim()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.apkLinkCopiedFallbackToast),
          backgroundColor: const Color(0xFF00AA44),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  /// 弹出主流 App 标准高反差版本更新提醒对话框
  void showUpdateDialog(BuildContext context, AppReleaseInfo release) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = AppStyle.primaryGreen(isDark);
    final amber = AppStyle.headingColor(isDark);

    showDialog(
      context: context,
      barrierDismissible: !release.isForced,
      builder: (ctx) => PopScope(
        canPop: !release.isForced,
        child: AlertDialog(
          backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: primaryGreen, width: 1.6),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppStyle.primaryGreenContainer(isDark),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.system_update_alt, color: primaryGreen, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.newVersionFoundTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: primaryGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${release.versionName}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${release.apkSizeMb.toStringAsFixed(1)} MB · ${release.releaseDate}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 更新日志内容框
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.updateChangelogHeader,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: amber,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        release.localizedChangelog,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 官方签名覆盖安装零丢点承诺
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0D2214) : const Color(0xFFE8F7ED),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user, size: 15, color: primaryGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          I18n.updateSafeOverwriteNotice,
                          style: TextStyle(
                            fontSize: 11,
                            color: primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!release.isForced) ...[
              TextButton(
                onPressed: () {
                  ignoreVersion(release.versionCode);
                  Navigator.of(ctx).pop();
                },
                child: Text(
                  I18n.updateLaterButton,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ],
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(
                I18n.updateNowButton,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await launchApkDownload(context, release.apkUrl);
              },
            ),
          ],
        ),
      ),
    );
  }
}
