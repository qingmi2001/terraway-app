import 'app_config.dart';
// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航与多点路书系统
// 模块名称: 全局中英双语多语言控制器与精简字典 (Locale Controller & I18n)
// 文件职责: 实现纯脱网无网络依赖的双语字典映射与 SharedPreferences 偏好落盘
//          提供极简有力的按钮与操作名称（2~4字，去冗长赘述，一目了然）
// ==============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  zh, // 中文 (简体)
  en, // English
}

class LocaleController with ChangeNotifier {
  static final LocaleController instance = LocaleController._internal();
  factory LocaleController() => instance;
  LocaleController._internal();

  static const String _prefKey = 'app_language';
  AppLanguage _language = AppLanguage.zh;

  AppLanguage get language => _language;
  bool get isZh => _language == AppLanguage.zh;

  Locale get locale => _language == AppLanguage.zh
      ? const Locale('zh', 'CN')
      : const Locale('en', 'US');

  String get languageName => _language == AppLanguage.zh ? '中文' : 'English';
  String get languageCode => _language == AppLanguage.zh ? 'zh' : 'en';

  Future<void> loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey);
      if (savedCode == 'en') {
        _language = AppLanguage.en;
        notifyListeners();
      } else if (savedCode == 'zh') {
        _language = AppLanguage.zh;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, lang == AppLanguage.zh ? 'zh' : 'en');
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    final next = _language == AppLanguage.zh ? AppLanguage.en : AppLanguage.zh;
    await setLanguage(next);
  }
}

/// 集中化多语言字典类 (I18n) - 全面遵循“极简精炼、2~4字、一目了然”原则
class I18n {
  static bool get isZh => LocaleController.instance.isZh;

  // 通用操作按钮 (极简 2~4 字)
  static String get appName => isZh ? "山海行" : "TerraWay";
  static String get appTitle => isZh ? "山海行 TerraWay" : "TerraWay GPS";
  static String get appSlogan => isZh ? "心中有方向，脚下有山海" : "In your heart a compass, beneath your feet the wilderness";
  static String get aboutSlogan => appSlogan;
  static String get save => isZh ? "保存" : "Save";
  static String get cancel => isZh ? "取消" : "Cancel";
  static String get confirm => isZh ? "确认" : "OK";
  static String get delete => isZh ? "删除" : "Delete";
  static String get login => isZh ? "登录" : "Login";
  static String get register => isZh ? "注册" : "Register";
  static String get loginOrRegister => isZh ? "登录 / 注册" : "Sign In / Register";

  // 顶栏与搜星状态
  static String get bdsGpsLocked => isZh ? "卫星已锁定" : "GNSS Locked";
  static String get acquiringSatellites => isZh ? "搜星中..." : "Searching...";
  static String get hardwareFixActive => isZh ? "硬件已定位" : "Fixed";
  static String get waitingForSatellites => isZh ? "等待搜星" : "Waiting";
  static String get switchLanguage => isZh ? "中 / EN" : "EN / 中";

  // 遥测指标
  static String get telemetryTitle => isZh ? "卫星遥测指标" : "Telemetry";
  static String get accuracyLabel => isZh ? "精度偏差" : "Accuracy";
  static String get altitudeLabel => isZh ? "当前海拔" : "Altitude";
  static String get speedLabel => isZh ? "瞬时时速" : "Speed";

  // 坐标卡片
  static String get currentLocation => isZh ? "当前位置" : "Location";
  static String get copyCoordinatesTooltip => isZh ? "复制坐标" : "Copy";
  static String get copiedToast => isZh ? "坐标已复制到剪贴板" : "Copied to clipboard";

  // 待机罗盘与方向
  static String get compassStandbyTitle => isZh ? "车头方位" : "Heading";
  static String directionText(int deg) {
    final d = (deg % 360 + 360) % 360;
    if (d >= 338 || d < 23) return isZh ? "正北 N" : "N 000°";
    if (d >= 23 && d < 68) return isZh ? "东北 NE" : "NE 045°";
    if (d >= 68 && d < 113) return isZh ? "正东 E" : "E 090°";
    if (d >= 113 && d < 158) return isZh ? "东南 SE" : "SE 135°";
    if (d >= 158 && d < 203) return isZh ? "正南 S" : "S 180°";
    if (d >= 203 && d < 248) return isZh ? "西南 SW" : "SW 225°";
    if (d >= 248 && d < 293) return isZh ? "正西 W" : "W 270°";
    return isZh ? "西北 NW" : "NW 315°";
  }

  // 底部大按钮 (精简 2 字)
  static String get selectRouteButton => isZh ? "路线" : "Routes";
  static String get selectRouteButtonShort => isZh ? "路线" : "Routes";
  static String get trackListTitle => isZh ? "轨迹" : "Tracks";

  // 卫星详细清单
  static String get satelliteDetailsTitle => isZh ? "卫星详情" : "Satellites";
  static String get gpsNavTitle => isZh ? "GPS 系统" : "GPS";
  static String get beidouNavTitle => isZh ? "北斗系统" : "BeiDou";
  static String lockedSatsBadge(int used, int total) => isZh ? "锁定 $used/$total" : "Locked $used/$total";
  static String get colPrn => isZh ? "编号" : "PRN";
  static String get colElevAzim => isZh ? "仰角/方位" : "Elev/Azim";
  static String get colSignal => isZh ? "信号(C/N0)" : "Signal";
  static String get colFixStatus => isZh ? "状态" : "Status";
  static String get statusUsedInFix => isZh ? "已解算" : "Used";
  static String get statusSearching => isZh ? "搜寻中" : "Search";
  static String get refreshEphemeris => isZh ? "刷新" : "Refresh";
  static String get noSatellitesFoundTitle => isZh ? "未搜到卫星信号" : "No Satellite Signals";
  static String get noSatellitesFoundDesc => isZh
      ? "请前往开阔露天场地，确保手机无金属遮挡。"
      : "Please move to open outdoor space.";
  static String get singleFixMode => isZh ? "单模搜星" : "Single Fix";
  static String get dualFixMode => isZh ? "双模解算" : "Dual Fix";
  static String get beidouSingleFixMode => isZh ? "北斗单模" : "BeiDou Only";
  static String get gpsSingleFixMode => isZh ? "GPS单模" : "GPS Only";
  static String get hardwareDirectLive => isZh ? "硬件直传" : "Hardware Live";
  static String get ephemerisSyncing => isZh ? "星历同步中" : "Syncing";
  static String get metricLockedCount => isZh ? "锁定解算" : "Locked";
  static String get metricTotalInView => isZh ? "视空可见" : "In View";
  static String get metricAccuracy => isZh ? "定位精度" : "Accuracy";

  // 导航仪表盘 (精炼缩写)
  static String get distToNext => isZh ? "本站距离" : "DIST";
  static String get instantSpeed => isZh ? "瞬时时速" : "SPEED";
  static String get eteLabel => isZh ? "到达用时" : "ETE";
  static String get brgLabel => isZh ? "目标航向" : "BEARING";
  static String get hazardCardTitle => isZh ? "前方避险备忘：" : "HAZARD:";
  static String get noHazardNote => isZh ? "当前航点无特殊备忘，请匀速通行" : "No hazard notes.";
  static String get prevStation => isZh ? "上一站" : "Prev";
  static String get nextStation => isZh ? "下一站" : "Next";
  static String get routeTourCompleted => isZh ? "巡航导引完成！" : "Completed!";
  static String stationProgress(int cur, int total) => isZh ? "第 $cur/$total 站" : "St. $cur/$total";
  static String arrivedNextTargetToast(String name) => isZh ? "🎯 已切向：$name" : "🎯 Heading: $name";
  static String remainingDistance(double km) => isZh ? "剩余: ${km.toStringAsFixed(1)}km" : "REM: ${km.toStringAsFixed(1)}km";
  static String get waypointsButton => isZh ? "点位" : "Points";
  static String get headingGps => isZh ? "GPS航向" : "GPS COG";
  static String get headingCompass => isZh ? "罗盘" : "COMPASS";
  static String altitudeFormat(String alt) => isZh ? "海拔: ${alt}m" : "ALT: ${alt}m";
  static String get noCoordinates => isZh ? "未指定坐标" : "No Coordinates";
  static String get noTargetWaypoint => isZh ? "未指定航点" : "No Waypoint";
  static String get carLandscapeCockpit => isZh ? "车机横屏" : "Cockpit";
  static String get modeSelectorTitle => isZh ? "运动模式" : "Sport Mode";

  // 昼夜模式
  static String get themeSystem => isZh ? "跟随系统" : "System";
  static String get themeLight => isZh ? "白天高光" : "Daylight";
  static String get themeDark => isZh ? "暗夜防眩" : "Night Dark";

  // 路线列表与管理器 (精简操作名)
  static String get roadbookListScreenTitle => isZh ? "穿越路线" : "Roadbooks";
  static String get createNewRouteButton => isZh ? "新建路线" : "New";
  static String get startNavigationButton => isZh ? "开始导航" : "Start";
  static String get editRouteButton => isZh ? "编辑" : "Edit";
  static String get deleteRouteButton => isZh ? "删除" : "Delete";
  static String get addWaypointButton => isZh ? "手动加点" : "Add";
  static String get pinGpsButton => isZh ? "GPS打点" : "Pin GPS";
  static String get waypointNameField => isZh ? "航点名称" : "Name";
  static String get waypointDescField => isZh ? "路况备忘" : "Notes";
  static String get captureCurrentGpsButton => isZh ? "读取当前GPS转度分秒" : "Read GPS to DMS";
  static String get confirmDeleteRouteTitle => isZh ? "确认删除该路线？" : "Delete route?";
  static String get arrivalRadiusSlider => isZh ? "到达判定半径" : "Arrival Radius";
  static String get searchRouteHint => isZh ? "搜索路线或途经点..." : "Search...";
  static String searchRouteCount(int count) => isZh ? "匹配 $count 条" : "$count routes";
  static String totalRoutesCount(int count) => isZh ? "共 $count 条路线" : "Total $count";
  static String get noSearchRouteFound => isZh ? "未找到匹配路线" : "No matching routes";
  static String get clearSearch => isZh ? "清空" : "Clear";
  static String get navButtonCompact => isZh ? "导航" : "NAV";
  static String get currentRouteBadge => isZh ? "当前" : "Active";
  static String pointCountShort(int count) => isZh ? "$count点" : "${count}pts";

  // 导航确认
  static String get confirmStartNavTitle => isZh ? "开始路线导航？" : "Start Navigation?";
  static String confirmStartNavDesc(String name, int pts) => isZh
      ? "即将开启【$name】($pts 点) 导引，后台将同步记录轨迹。"
      : "Start guidance for \"$name\" ($pts points).";
  static String get startNavConfirmBtn => isZh ? "开始导航" : "Start Nav";

  // 退出确认
  static String get exitNavDialogTitle => isZh ? "退出当前导航？" : "Exit Nav?";
  static String get exitNavDialogBody => isZh
      ? "•【结束导航】：结束本次行程，提示保存轨迹；\n•【后台运行】：罗盘与轨迹记录在后台继续运行。"
      : "• [Exit]: Ends trip session.\n• [Background]: Keeps running in background.";
  static String get btnExitNav => isZh ? "结束导航" : "Exit";
  static String get btnKeepBackground => isZh ? "后台运行" : "Background";
  static String get toastNavRunningInBackground => isZh ? "🧭 导航正在后台运行中..." : "🧭 Running in background...";

  // 首页返回导航
  static String get returnToNavButton => isZh ? "返回导航" : "Resume";
  static String activeNavBannerTitle(String name) => isZh ? "🧭 巡航中：$name" : "🧭 Nav: $name";
  static String activeNavBannerSubtitle(double km) => isZh
      ? "已行进 ${km.toStringAsFixed(1)}km · 点击返回仪表盘"
      : "${km.toStringAsFixed(1)}km recorded";

  // 轨迹详情与操作
  static String get trackDetailTitle => isZh ? "轨迹详情" : "Track Detail";
  static String get retraceBtnShort => isZh ? "原路返航" : "Retrace";
  static String get exportBtnShort => isZh ? "导出" : "Export";
  static String get uploadBtnShort => isZh ? "云备份" : "Backup";
  static String get roadbookBtnShort => isZh ? "转路书" : "To Route";
  static String get uploadCloudTitle => isZh ? "云端备份" : "Cloud Backup";
  static String get uploadCloudDesc => isZh
      ? "加密备份至个人云端保险箱，换机一键找回（本地始终保留离线副本）。"
      : "Backup to your cloud vault for device recovery.";

  // 头像与菜单
  static String get explorerProfileTitle => isZh ? "山海行者" : "Explorer";
  static String get explorerProfileSubtitle => isZh ? "离线系统 · v${AppConfig.versionName}" : "Offline · v${AppConfig.versionName}";
  static String get notLoggedInBadge => isZh ? "未登录 (点击登录/注册)" : "Not Signed In";
  static String get deviceReadyStatus => isZh ? "硬件已就绪" : "Ready";
  static String get cloudConnectedStatus => isZh ? "云端已连接" : "Connected";
  static String get menuThemes => isZh ? "昼夜主题" : "Theme";
  static String get menuLanguages => isZh ? "语言切换" : "Language";
  static String get menuModes => isZh ? "运动模式" : "Sport Mode";
  static String get menuSatellites => isZh ? "星历遥测" : "Satellites";
  static String get menuCloudVault => isZh ? "云端账号 (登录 / 注册)" : "Cloud Account";
  static String get menuCheckUpdate => isZh ? "检查更新" : "Check Update";
  static String get menuSafety => isZh ? "安全须知" : "Safety";
  static String get menuAbout => isZh ? "关于软件" : "About";

  // 在线更新
  static String get newVersionFoundTitle => isZh ? "发现新版本" : "New Version";
  static String get updateChangelogHeader => isZh ? "更新内容：" : "Changelog:";
  static String get updateSafeOverwriteNotice => isZh
      ? "官方签名 · 覆盖安装，本地数据零丢失"
      : "Safe overwrite install keeps all local data";
  static String get updateLaterButton => isZh ? "稍后" : "Later";
  static String get updateNowButton => isZh ? "立即升级" : "Update";
  static String get checkingUpdateToast => isZh ? "🔄 正在检测最新版本..." : "🔄 Checking...";
  static String get updateCheckOfflineToast => isZh
      ? "📡 当前处于离线环境，本地功能 100% 正常可用"
      : "📡 Offline mode active.";
  static String alreadyLatestVersionToast(String ver) => isZh
      ? "✅ 当前已是最新版 (v$ver)"
      : "✅ Latest version (v$ver)";
  static String get apkLinkCopiedFallbackToast => isZh
      ? "📋 已复制下载链接，请在浏览器中打开安装"
      : "📋 Link copied. Open in browser.";
  static String get newBadgeText => isZh ? "新版" : "NEW";

  // 车队短码
  static String get cloudVaultDialogTitle => isZh ? "云端保险箱" : "Cloud Vault";
  static String get cloudVaultNonBlockingHint => isZh
      ? "非阻塞服务：不登录亦可完全单机使用；登录后换机可一键恢复轨迹与路线。"
      : "Optional: 100% offline features work without login. Sign in to sync across devices.";
  static String get squadCodeDialogTitle => isZh ? "车队短码互传" : "Squad Code";
  static String get importByCodeButton => isZh ? "短码导入" : "Import";
  static String get shareRouteCodeTooltip => isZh ? "生成车队码" : "Share";
  static String get cloudSyncedBadge => isZh ? "云端已存" : "Synced";

  // 轨迹结束保存
  static String autoRecordingLive(double km) => isZh ? "录制中 ${km.toStringAsFixed(1)}km" : "Rec ${km.toStringAsFixed(1)}km";
  static String get finishTrackSessionTitle => isZh ? "结束行程" : "End Trip";
  static String get promptSaveTrackTitle => isZh ? "保存本次轨迹？" : "Save track?";
  static String promptSaveTrackSubtitle(double km, String time, int pts) => isZh
      ? "里程：${km.toStringAsFixed(2)}km  ·  用时：$time  ·  点数：$pts\n\n【保存】存入本机历史库；【放弃】清空本次记录。"
      : "Dist: ${km.toStringAsFixed(2)}km · Time: $time · Points: $pts";
  static String get saveToHistoryButton => isZh ? "保存历史" : "Save";
  static String get discardTrackButton => isZh ? "放弃本次" : "Discard";
  static String get savedToLocalSuccessToast => isZh ? "🎯 轨迹已成功存入本机！" : "🎯 Track saved!";
  static String get discardedToast => isZh ? "本次记录已放弃" : "Discarded.";
  static String get localSavedBadge => isZh ? "本机已存" : "Local";
  static String get retraceLaunchedToast => isZh ? "🧭 原路返航已激活！" : "🧭 Retrace started!";
  static String get noTracksYet => isZh ? "暂无轨迹记录" : "No Tracks";
  static String get noTracksHint => isZh ? "开启导航将自动记录轨迹，支持原路返航。" : "Nav tracks are auto recorded.";
  static String get trackExportSuccess => isZh ? "📄 GPX 已复制到剪贴板！" : "📄 GPX copied!";
  static String get safetyNoticeHeader => isZh ? "⚠️ 户外安全须知" : "⚠️ Safety Notice";
  static String get aboutAppSubtitle => isZh ? "100% 纯脱网全地形手持 GPS 导航系统。" : "100% offline handheld GPS.";
  static String get agreeAndClose => isZh ? "知悉同意" : "Agree";
  static String get safetyBullet1 => isZh ? "辅助工具：严禁作为无人区穿越的唯一生存依赖。" : "Auxiliary civilian tool only.";
  static String get safetyBullet2 => isZh ? "应急冗余：荒野穿越必须备齐卫星电话、指北针与纸质地图。" : "Satellite phone & paper map mandatory.";
  static String get safetyBullet3 => isZh ? "风险自负：野外路况多变，路线仅供参考，决策责任自负。" : "Terrain changes constantly. User assumes risk.";
  static String get safetyBullet4 => isZh ? "纯净隐私：100% 脱网本地运行，零广告、无后台监控打点。" : "Zero telemetry, zero ads, local data.";
  static String get licenseSectionTitle => isZh ? "📄 版权所有" : "📄 License";
  static String get licenseSectionDesc => isZh ? "© 2026 山海行 (TerraWay) · 保留所有权利" : "© 2026 TerraWay · All Rights Reserved";
}
