// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 非阻塞云端保险箱与车队短码同步中枢 (Cloud Sync & Squad Share Service)
// 文件职责:
// 1. 恪守“本地优先、离线为核”原则：平时不登录 100% 开放全功能，仅按需弹出登录框；
// 2. 提供账号注册、登录 (JWT)、个人历史轨迹与私有路书的 Gzip 压缩云备份与换机恢复；
// 3. 提供领队-车队“6 位路书短码”一键生成与拉取，同时内置离线压缩口令双模兜底。
// ==============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/roadbook.dart';
import '../models/track.dart';
import 'track_recorder_service.dart';

/// 云端同步操作结果封装
class CloudSyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final String? shareCode;

  const CloudSyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.shareCode,
  });
}

/// 非阻塞云端同步与车队路书分发服务 (单例 + ChangeNotifier)
class CloudSyncService with ChangeNotifier {
  static final CloudSyncService instance = CloudSyncService._internal();
  factory CloudSyncService() => instance;
  CloudSyncService._internal() {
    _loadSavedSession();
  }

  static const String _prefServerUrlKey = 'terraway_vps_base_url';
  static const String _prefJwtTokenKey = 'terraway_jwt_token';
  static const String _prefUserAccountKey = 'terraway_user_account';
  static const String _prefUserNicknameKey = 'terraway_user_nickname';

  /// 默认云端服务节点地址 (可在探险者系统抽屉中随时自定义修改为你的专属 VPS 域名/IP)
  static const String defaultServerBaseUrl = 'https://api.terraway.cn';

  String _serverBaseUrl = defaultServerBaseUrl;
  String _jwtToken = '';
  String _userAccount = '';
  String _userNickname = '';
  bool _isBusy = false;

  String get serverBaseUrl => _serverBaseUrl;
  String get vpsHostUrl => _serverBaseUrl;
  bool get isLoggedIn => _jwtToken.isNotEmpty;
  String get userAccount => _userAccount;
  String get userNickname => _userNickname.isNotEmpty ? _userNickname : _userAccount;
  bool get isBusy => _isBusy;

  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverBaseUrl = prefs.getString(_prefServerUrlKey) ?? defaultServerBaseUrl;
      _jwtToken = prefs.getString(_prefJwtTokenKey) ?? '';
      _userAccount = prefs.getString(_prefUserAccountKey) ?? '';
      _userNickname = prefs.getString(_prefUserNicknameKey) ?? '';
      notifyListeners();
    } catch (_) {}
  }

  /// 获取当前配置的 VPS 服务器根地址
  Future<String> getServerBaseUrl() async {
    if (_serverBaseUrl.isEmpty) {
      await _loadSavedSession();
    }
    return _serverBaseUrl.replaceAll(RegExp(r'/+$'), '');
  }

  /// 修改并保存自定义 VPS 服务器地址
  Future<void> setServerBaseUrl(String newUrl) async {
    final cleaned = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _serverBaseUrl = cleaned.isEmpty ? defaultServerBaseUrl : cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerUrlKey, _serverBaseUrl);
    } catch (_) {}
    notifyListeners();
  }

  /// 注册新账号 (/api/v1/auth/register)
  Future<CloudSyncResult> register({
    required String account,
    required String password,
    required String nickname,
  }) async {
    return _authenticate(
      endpoint: '/api/v1/auth/register',
      payload: {
        'phone_or_email': account.trim(),
        'password': password,
        'nickname': nickname.trim().isEmpty ? account.trim() : nickname.trim(),
      },
    );
  }

  /// 登录账号 (/api/v1/auth/login)
  Future<CloudSyncResult> login({
    required String account,
    required String password,
  }) async {
    return _authenticate(
      endpoint: '/api/v1/auth/login',
      payload: {
        'phone_or_email': account.trim(),
        'password': password,
      },
    );
  }

  Future<CloudSyncResult> _authenticate({
    required String endpoint,
    required Map<String, dynamic> payload,
  }) async {
    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _postJson('$base$endpoint', payload, timeoutSeconds: 8);
      _isBusy = false;

      if (resp != null && (resp['code'] == 0 || resp['token'] != null)) {
        final data = resp['data'] is Map<String, dynamic>
            ? resp['data'] as Map<String, dynamic>
            : resp;
        _jwtToken = data['token'] as String? ?? '';
        _userAccount = data['phone_or_email'] as String? ?? (payload['phone_or_email'] as String? ?? '');
        _userNickname = data['nickname'] as String? ?? _userAccount;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefJwtTokenKey, _jwtToken);
        await prefs.setString(_prefUserAccountKey, _userAccount);
        await prefs.setString(_prefUserNicknameKey, _userNickname);
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: resp['message'] as String? ?? '云端账户认证成功',
        );
      }

      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '无法连接云端节点，请检查网络或服务器地址配置',
      );
    } catch (e) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '当前处于离线环境或云端服务器未响应，本地数据依然 100% 安全保存',
      );
    }
  }

  /// 退出云端账户 (不影响本地沙盒已保存的任何轨迹与路书)
  Future<void> logout() async {
    _jwtToken = '';
    _userAccount = '';
    _userNickname = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefJwtTokenKey);
      await prefs.remove(_prefUserAccountKey);
      await prefs.remove(_prefUserNicknameKey);
    } catch (_) {}
    notifyListeners();
  }

  /// 上传单条或全部未同步轨迹至云端 (/api/v1/sync/tracks/upload)
  Future<CloudSyncResult> syncTracksToCloud({Track? singleTrack}) async {
    if (!isLoggedIn) {
      return const CloudSyncResult(success: false, message: '请先登录云端保险箱账户');
    }

    final recorder = TrackRecorderService.instance;
    final targets = singleTrack != null
        ? [singleTrack]
        : recorder.savedTracks.where((t) => !t.isSynced).toList();

    if (targets.isEmpty) {
      return const CloudSyncResult(success: true, message: '所有本地轨迹均已同步至云端', syncedCount: 0);
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final payload = {
        'tracks': targets.map((t) => t.toJson()).toList(),
      };
      final resp = await _postJson('$base/api/v1/sync/tracks/upload', payload, timeoutSeconds: 15);
      _isBusy = false;

      if (resp != null && (resp['code'] == 0 || resp['success'] == true)) {
        for (final t in targets) {
          t.isSynced = true;
          await recorder.updateTrackName(t.id, t.name);
        }
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: '成功备份 ${targets.length} 条轨迹至云端保险箱',
          syncedCount: targets.length,
        );
      }

      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '上传失败，轨迹已安全保留在本机沙盒',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '网络不可用，轨迹已保存在本机，待有网时可再次同步',
      );
    }
  }

  /// 从云端拉取恢复个人历史轨迹 (/api/v1/sync/tracks/list)
  Future<CloudSyncResult> restoreTracksFromCloud() async {
    if (!isLoggedIn) {
      return const CloudSyncResult(success: false, message: '请先登录云端保险箱账户');
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _getJson('$base/api/v1/sync/tracks/list', timeoutSeconds: 12);
      _isBusy = false;

      if (resp != null && resp['code'] == 0) {
        final list = (resp['data'] as List<dynamic>?) ?? [];
        final restored = <Track>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final trk = Track.fromJson(item);
            trk.isSynced = true;
            restored.add(trk);
          }
        }
        final added = await TrackRecorderService.instance.mergeCloudTracks(restored);
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: '成功从云端恢复 $added 条新轨迹至本机',
          syncedCount: added,
        );
      }

      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '未能从云端读取轨迹列表',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '当前无网络连接，无法连接云端保险箱',
      );
    }
  }

  /// 备份本地全部路书至云端 (/api/v1/sync/roadbooks/upload)
  Future<CloudSyncResult> syncRoadbooksToCloud() async {
    if (!isLoggedIn) {
      return const CloudSyncResult(success: false, message: '请先登录云端保险箱账户');
    }

    final store = RoadbookStore.instance;
    final roadbooks = store.roadbooks;
    if (roadbooks.isEmpty) {
      return const CloudSyncResult(success: false, message: '本地暂无路书可备份');
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final payload = {
        'roadbooks': roadbooks.map((r) => r.toJson()).toList(),
      };
      final resp = await _postJson('$base/api/v1/sync/roadbooks/upload', payload, timeoutSeconds: 12);
      _isBusy = false;

      if (resp != null && resp['code'] == 0) {
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: '成功将 ${roadbooks.length} 条穿越路书备份至云端',
          syncedCount: roadbooks.length,
        );
      }
      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '路书云端备份失败',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '网络未连接，路书已安全存储于手机本地沙盒',
      );
    }
  }

  /// 从云端恢复私有路书至本机 (/api/v1/sync/roadbooks/list)
  Future<CloudSyncResult> restoreRoadbooksFromCloud() async {
    if (!isLoggedIn) {
      return const CloudSyncResult(success: false, message: '请先登录云端保险箱账户');
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _getJson('$base/api/v1/sync/roadbooks/list', timeoutSeconds: 12);
      _isBusy = false;

      if (resp != null && resp['code'] == 0) {
        final list = (resp['data'] as List<dynamic>?) ?? [];
        final restored = <Roadbook>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            restored.add(Roadbook.fromJson(item));
          }
        }
        final added = await RoadbookStore.instance.mergeCloudRoadbooks(restored);
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: '成功从云端同步恢复 $added 条新路线至本机',
          syncedCount: added,
        );
      }
      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '云端暂无已备份的路书',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '当前处于离线状态，无法拉取云端路书',
      );
    }
  }

  /// 生成领队-车队 6 位路书短码 (/api/v1/roadbook/share)，无网时自动生成离线压缩口令兜底
  Future<CloudSyncResult> shareRoadbook(Roadbook roadbook) async {
    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _postJson(
        '$base/api/v1/roadbook/share',
        {'roadbook': roadbook.toJson()},
        timeoutSeconds: 6,
      );
      _isBusy = false;

      if (resp != null && resp['code'] == 0) {
        final data = resp['data'] is Map<String, dynamic>
            ? resp['data'] as Map<String, dynamic>
            : resp;
        final code = data['share_code'] as String? ?? '';
        if (code.isNotEmpty) {
          notifyListeners();
          return CloudSyncResult(
            success: true,
            message: '已生成 6 位车队路书短码：$code',
            shareCode: code,
          );
        }
      }
    } catch (_) {
      _isBusy = false;
    }

    // 脱网/未部署 VPS 时的纯离线兜底：生成 Gzip+Base64 离线分享口令
    final jsonBytes = utf8.encode(jsonEncode(roadbook.toJson()));
    final compressed = gzip.encode(jsonBytes);
    final offlineToken = 'TW6:${base64UrlEncode(compressed)}';
    notifyListeners();
    return CloudSyncResult(
      success: true,
      message: '已生成离线车队路书口令（已复制到剪贴板，发给队员粘贴即可导入）',
      shareCode: offlineToken,
    );
  }

  /// 根据 6 位短码或离线口令导入车队路书 (/api/v1/roadbook/fetch/:code)
  Future<CloudSyncResult> importRoadbookByCode(String codeOrToken) async {
    final cleaned = codeOrToken.trim();
    if (cleaned.isEmpty) {
      return const CloudSyncResult(success: false, message: '请输入 6 位短码或离线口令');
    }

    // 1. 识别纯离线压缩口令 (TW6:xxx)
    if (cleaned.startsWith('TW6:')) {
      try {
        final rawB64 = cleaned.substring(4).trim();
        final compressed = base64Url.decode(rawB64);
        final jsonStr = utf8.decode(gzip.decode(compressed));
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final rb = Roadbook.fromJson(map);
        rb.name = '${rb.name} [车队导入]';
        RoadbookStore.instance.addCustomRoadbook(rb);
        return CloudSyncResult(
          success: true,
          message: '成功离线导入路书：【${rb.name}】(${rb.points.length}个航点)',
          syncedCount: 1,
        );
      } catch (_) {
        return const CloudSyncResult(success: false, message: '离线口令格式损坏，请重新复制');
      }
    }

    // 2. 联网通过 VPS 6 位短码拉取
    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _getJson(
        '$base/api/v1/roadbook/fetch/${Uri.encodeComponent(cleaned.toUpperCase())}',
        timeoutSeconds: 8,
      );
      _isBusy = false;

      if (resp != null && resp['code'] == 0 && resp['data'] is Map<String, dynamic>) {
        final rb = Roadbook.fromJson(resp['data'] as Map<String, dynamic>);
        RoadbookStore.instance.addCustomRoadbook(rb);
        notifyListeners();
        return CloudSyncResult(
          success: true,
          message: '成功导入车队路书：【${rb.name}】(${rb.points.length}个航点)',
          syncedCount: 1,
        );
      }

      notifyListeners();
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '未找到该短码对应的路书或短码已过期',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '无网络连接，离线环境下请使用 TW6: 开头的离线口令导入',
      );
    }
  }

  /// 修改个人登录密码 (/api/v1/user/password/change)
  Future<CloudSyncResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (!isLoggedIn) {
      return const CloudSyncResult(success: false, message: '请先登录云端账户');
    }
    if (newPassword.length < 6) {
      return const CloudSyncResult(success: false, message: '新密码长度至少为 6 位');
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _postJson(
        '$base/api/v1/user/password/change',
        {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
        timeoutSeconds: 8,
      );
      _isBusy = false;
      notifyListeners();

      if (resp != null && resp['code'] == 0) {
        return CloudSyncResult(
          success: true,
          message: resp['message'] as String? ?? '密码修改成功，请使用新密码登录',
        );
      }
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '原密码不正确或修改失败',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '网络未连接，无法修改密码',
      );
    }
  }

  /// 提交找回密码 / 故障申诉工单留言 (/api/v1/user/ticket/submit)
  Future<CloudSyncResult> submitSupportTicket({
    required String account,
    required String ticketType,
    required String contactInfo,
    required String message,
  }) async {
    if (account.trim().isEmpty || message.trim().isEmpty) {
      return const CloudSyncResult(success: false, message: '请填写账号与具体说明');
    }

    _isBusy = true;
    notifyListeners();

    try {
      final base = await getServerBaseUrl();
      final resp = await _postJson(
        '$base/api/v1/user/ticket/submit',
        {
          'account': account.trim(),
          'ticket_type': ticketType,
          'contact_info': contactInfo.trim(),
          'message': message.trim(),
        },
        timeoutSeconds: 8,
      );
      _isBusy = false;
      notifyListeners();

      if (resp != null && resp['code'] == 0) {
        return CloudSyncResult(
          success: true,
          message: resp['message'] as String? ?? '工单留言已提交！管理员审核后将协助处理。',
        );
      }
      return CloudSyncResult(
        success: false,
        message: resp?['message'] as String? ?? '提交失败，请稍后重试',
      );
    } catch (_) {
      _isBusy = false;
      notifyListeners();
      return const CloudSyncResult(
        success: false,
        message: '网络未连接，无法提交留言',
      );
    }
  }

  Future<Map<String, dynamic>?> _postJson(
    String url,
    Map<String, dynamic> bodyMap, {
    int timeoutSeconds = 8,
  }) async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSeconds);
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_jwtToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_jwtToken');
      }
      final encoded = utf8.encode(jsonEncode(bodyMap));
      req.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close().timeout(Duration(seconds: timeoutSeconds));
      final text = await resp.transform(utf8.decoder).join();
      if (text.isNotEmpty) {
        return jsonDecode(text) as Map<String, dynamic>;
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(
    String url, {
    int timeoutSeconds = 8,
  }) async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSeconds);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_jwtToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_jwtToken');
      }
      final resp = await req.close().timeout(Duration(seconds: timeoutSeconds));
      final text = await resp.transform(utf8.decoder).join();
      if (text.isNotEmpty) {
        return jsonDecode(text) as Map<String, dynamic>;
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }
}
