# 山海行 (TerraWay) 全地形手持 GPS 导航系统
## 完整开发说明书、架构规范与未来演进全景手册 (v0.7.5 基准 · 全生命周期归档)

> **【手册核心定位与存档目的】**：本手册汇集了「山海行 (TerraWay)」从初代构建至 v0.6.0 工业级基准演进过程中的全部架构设计、源码文件拓扑、底层数学算法、UI/UX 规范、历史编译排错指南与未来阶段演进规划。无论后续新增离线切片底图、自建 VPS 备份通道、公开路书广场或车队互联，所有开发人员必须以此手册为基准规范开展工作，**确保项目核心理念不走偏、代码风格不突变、脱网高可用特性不受损**。

---

## 一、 项目背景与产品核心设计哲学

### 1. 产品定位与核心使用场景
「山海行 (TerraWay)」是一款专为**荒漠戈壁穿沙、无人区自驾探险、山林重装徒步、长途越野骑行以及野外应急搜救**打造的专业级纯离线手持 GPS/北斗导引系统。当探险者深入无移动基站覆盖的极端无人区时，主流民用商业地图因断网无法加载瓦片、频繁鉴权崩溃而彻底瘫痪。「山海行」直接调用底层卫星物理芯片，拔掉 SIM 卡、开启飞行模式亦能秒级冷启动运行，提供绝对可靠的方位导向与路书巡航保障。

### 2. 三大核心不可突破之设计铁律
1. **【0.5 秒高反差扫视原则】**：所有界面专为强颠簸越野车机、烈日直射沙漠与纯黑无光夜行调校。拒绝低对比度浅灰渐变，文字与背景对比度必须达到 7:1 以上。驾驶员以余光扫视仪表盘 0.5 秒内即可明确时速、距离、剩余用时与导引方向。
2. **【等宽数字防抖动锁相原则】**：行进中 GPS 经纬度、时速、距离高频跳动。所有数值必须严格锁死 `fontFamily: 'monospace'`，度分秒符号在同一垂线上绝对锁相对齐，经纬度字母与数值保持 16px 间距，彻底消除数字伸缩引起的视觉眩晕。
3. **【去商业大厂化极简工业仪器风】**：坚决禁止引入圆润泡泡风大圆角（外圆角上限 10px）、大面积弹簧过度动画、电商卡片风或营销打扰弹窗。界面整体呈现航空仪表与地质勘测设备的严谨、精密与克制。

---

## 二、 系统架构总览与全量工程源码清单

工程基于跨平台的 Flutter 3 架构开发，全面采用领域驱动的清晰分层，共计包含 **23 个核心 Dart 源文件 + Go 极简高安全服务端**，具备 100% 静态类型安全与括号对称性：

| 所属层级 | 文件路径 | 文件职责与核心逻辑说明 |
| :--- | :--- | :--- |
| **Core 核心算法与控制器层** | `lib/core/app_style.dart` | 全局设计令牌 (Design Tokens)：固化昼夜色彩、等宽字体、58px卡片高度、8px圆角。 |
| | `lib/core/device_mode_controller.dart` | 设备形态控制器与 `BeeperService`：横竖屏检测与到站清脆声学蜂鸣音频播放。 |
| | `lib/core/gnss_service.dart` | 物理卫星数据中枢：解析卫星编号 (PRN)、仰角、方位角与载噪比 (C/N0) 信号柱。 |
| | `lib/core/locale_controller.dart` | 中英双语国际化控制器：管理 280+ 词条，支持首页一键切换与本地持久化记忆。 |
| | `lib/core/math_utils.dart` | 数学计算中枢：Haversine 大地距离、DMS 格式化、角度转 8 罗经方位标。 |
| | `lib/core/navigation_mode.dart` | 四大运动模式中枢 (`OutdoorSportMode`)：越野、徒步、骑行、搜救及判定圆自适应。 |
| | `lib/core/security_checker.dart` | 离线安全守护：保证无第三方广告 SDK、无用户行为打点、无隐私数据静默外发。 |
| | `lib/core/sensor_fusion.dart` | 传感器融合中枢：地磁罗盘一阶环形低通滤波 + 无磁力计 GPS COG 航向角自动平滑回退。 |
| | `lib/core/theme_controller.dart` | 主题控制器：白昼高光防直射模式与暗夜防眩目模式动态切换。 |
| | `lib/core/track_recorder_service.dart` | 导航同步轨迹录制中枢：导航开启自动记录，退出弹窗防丢确认，本地持久化与 GPX 导出。 |
| **Models 数据模型层** | `lib/models/roadbook.dart` | 路书与点位仓储实体 (`RoadbookStore`)：多点循迹、到达判定圆检测、200点海量支持。 |
| | `lib/models/track.dart` | 轨迹实体 (`Track` / `TrackPoint`)：包含 GPX 1.1 导出与一键原路返航倒序生成。 |
| | `lib/models/waypoint.dart` | 航点实体：封装半球、度分秒、经纬度浮点数与避坑避险实操备忘信息。 |
| **Screens 交互视图层** | `lib/screens/dashboard_screen.dart` | 核心导航仪表盘：车机横屏双栏座舱、3D折面大指针、到站蜂鸣、避坑卡片与退出确认。 |
| | `lib/screens/home_screen.dart` | 待机主页：北斗锁定状态、度分秒坐标居中锁相、探险者头像抽屉、动态“返回导航”主控。 |
| | `lib/screens/roadbook_list_screen.dart` | 线路选择列表：全要素即时模糊搜索、58px高密度紧凑卡片、开启导航二次确认弹窗。 |
| | `lib/screens/roadbook_manager_screen.dart` | 路书点位管理：度分秒分立直录、实地打点采样与到站判定半径 (30~300m) 滑动调优。 |
| | `lib/screens/satellite_detail_screen.dart` | 卫星遥测全景页：上层GPS/下层北斗双模排列，单星载噪比柱状图与仰角方位角展示。 |
| | `lib/screens/track_detail_screen.dart` | 轨迹全貌地图详情：离线矢量轨迹渲染、海拔起伏剖面图、全要素数据矩阵与返航操作栏。 |
| | `lib/screens/track_list_screen.dart` | 历史轨迹列表：58px单行紧凑排版，展示保存时间、点数、里程与耗时，点击进入地图全貌。 |
| **Main 入口层** | `lib/main.dart` | 应用程序入口点：初始化持久化配置、全局服务装配与高反差主题引导。 |

---

## 三、 核心底层算法与数学模型实现细节

### 1. 大地球面距离积分公式 (Haversine Formula)
在 `MathUtils.haversineDistance` 中实现，计算两组 WGS-84 经纬度点之间的直线大地表面距离（米），作为到达判定圆与连续折线里程积分的基础：
```dart
static double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0; // 地球平均曲率半径 (米)
  final phi1 = lat1 * (math.pi / 180.0);
  final phi2 = lat2 * (math.pi / 180.0);
  final deltaPhi = (lat2 - lat1) * (math.pi / 180.0);
  final deltaLambda = (lon2 - lon1) * (math.pi / 180.0);

  final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
            math.cos(phi1) * math.cos(phi2) *
            math.sin(deltaLambda / 2) * math.sin(deltaLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}
```

### 2. 环形一阶低通抗颠簸滤波 (Circular Low-Pass Filter)
在 `CircularLowPassFilter` 中实现。普通线性滤波在角度从 359° 跨越至 0° 时会出现线性插值，导致大指针瞬间发生 360 度倒抽死循环。山海行采用二维单位三角矢量滑动积分，彻底解决拓扑断裂问题：
```dart
double filter(double currentDegrees) {
  final rad = currentDegrees * (math.pi / 180.0);
  final curCos = math.cos(rad);
  final curSin = math.sin(rad);

  if (_cosSum == null || _sinSum == null) {
    _cosSum = curCos;
    _sinSum = curSin;
  } else {
    // 矢量加权平滑
    _cosSum = (1.0 - alpha) * _cosSum! + alpha * curCos;
    _sinSum = (1.0 - alpha) * _sinSum! + alpha * curSin;
  }

  var filteredRad = math.atan2(_sinSum!, _cosSum!);
  var filteredDeg = filteredRad * (180.0 / math.pi);
  return (filteredDeg + 360.0) % 360.0;
}
```

### 3. 无地磁计与车身强干扰下的 GPS 对地真航向 (COG) 自动回退
越野改装车、大型皮卡车体金属会严重磁化手机内置的电子罗盘，部分车机甚至缺少磁力计芯片。系统设立动态门限探测：当对地瞬时车速 > 3.0 km/h 时，底层自动切断地磁传感器数据，强制切换为卫星多普勒位移解算出的地面运动航向 (Course Over Ground)，指示精确稳定、绝不乱跳。

### 4. 航迹动态采样与原地驻车死区滤波 (Deadband Filtering)
在 `TrackRecorderService` 中，针对不同运动模式预设死区门限（如越野模式：车速 < 1.5 km/h 且位移 < 8m 判定为营地驻车）。强制不记录冗余乱麻轨迹点；行进中自适应按 3 秒或 10 米高频记录，确保航迹平滑细腻。

### 5. 5 点滑动中值高程滤波 (Median Altitude Smoothing)
普通民用 GPS 垂直高程误差可达水平误差的 2~3 倍。系统在航迹采集流中维护 5 点滑动窗口，实时剔除两端毛刺极值、取中位数高程，确保海拔起伏图与累计拔高统计真实可信。

### 6. 遇险保命“一键原路反向循迹”算法 (Retrace Algorithm)
在 `Track.toRoadbook(reverse: true)` 中实现。将已记录的航迹序列进行等步长多边形特征抽稀（默认抽稀至 50 点最佳视距），倒序反向生成连续路书，起点自动标注为“返航脱困起点”，终点标注为“大本营安全终点”，帮助迷失在夜色或风沙中的探险者沿着来时车辙安全脱困。

---

## 四、 全生命周期交互规范与防误触机制

1. **开启导航二次确认**：线路列表点击路线或导航按钮，必须弹出「开始路线导航？」弹窗，展示路线名称、点位数并说明后台同步记录，防止颠簸误触。
2. **退出导航与后台继续双模判定**：点击返回或边缘手势时弹出确认：
   - 点【返回首页 (后台继续)】：仪表盘退出，导航与轨迹记录后台静默运行，首页底部切换为「返回导航」；
   - 点【退出导航 (结束)】：停止传感器定位，弹出行程总结并询问「保存至本机历史库」或「不保存放弃本次轨迹」。
3. **首页底部双主控条**：常态下为「路线」与「轨迹」50/50等宽对称；后台有导航在进行时，左侧自适应切换为高亮「返回导航」，点击秒级重返仪表盘。
4. **通用探险者头像与系统抽屉**：首页顶栏右侧设立圆形头像，集中管理昼夜主题、中英语言、全地形运动模式、星历遥测、安全须知等全量功能，彻底消除顶栏零散小图标堆积。
5. **高密度紧凑单行卡片**：线路与轨迹列表单行高度严格控制在 56px~62px 之间，单屏纵向可饱览 8~10 行数据。

---

## 五、 历史编译故障排查与开发者防踩坑手册 (Gotchas)

> **【代码编写与编译红线】**：后续开发人员在修改或扩充代码时，必须对照以下 8 个高频易错点逐项自查，严防编译失败：

1. **枚举命名严禁与 Flutter 原生同名冲突**：
   `package:flutter/widgets.dart` 内部已存在原生 `NavigationMode` 枚举。因此，自定义运动模式枚举必须命名为 `OutdoorSportMode`，严禁写回 `NavigationMode`。
2. **`intl` 库与 Flutter 核心绘制引擎跨包符号冲突**：
   `package:intl/intl.dart` 内部导出了同名 `TextDirection`（无 `.ltr` 成员），会同名覆盖 Flutter 核心渲染引擎的 `TextDirection.ltr`。凡是引入 `intl` 且涉及 `TextPainter` 的文件，必须写为：
   `import 'package:intl/intl.dart' hide TextDirection;`。
3. **字符串字面量绝对禁止未转义物理换行**：
   Dart 单/双引号字符串内部出现物理按次回车会直接引发词法解析阻断。多行文字必须显式写为单行转义符号（如 `\n`）或三引号。
4. **Controller 与 Service 语义别名必须保留**：
   重构方法名时必须提供兼容别名，确保所有旧页面调用无损：
   - `Track.toGpxXml()` 必须映射至 `toGpxString()`；
   - `RoadbookStore.addCustomRoadbook()` 必须映射至 `addRoadbookDirect()`；
   - `TrackRecorderService.updateTrackName()` 必须映射至 `renameTrack()`。
5. **传感器资源显式挂起接口**：
   `SensorFusionManager` 必须显式暴露 `stop()` 方法以注销位置与罗盘监听通道，与 `dispose()` 解耦，方便仪表盘在退出判定和挂起时按需调度。
6. **ChangeNotifier 规范**：
   单例状态控制器（如 `NavigationModeController`）必须混入 `with ChangeNotifier`，并暴露 `currentModeIcon`、`currentModeName`、`currentThresholdMeters` 及 `cycleToNextMode()` 方法。
7. **9p 虚拟机虚拟文件系统目录缓存 (dcache) 打包陷阱**：
   在云端容器或 QEMU 9p 文件系统（`dcache=1000`）中，新建文件可能因目录缓存延迟导致 `os.walk` 遍历遗漏。打包前必须在本地独立目录完成文件校验并执行 `assert in namelist()` 断言，确保所有 Dart 文件 100% 写入压缩包。
8. **官方长期固化签名与平滑升级**：
   生产构建必须严格使用项目固化的数字签名密钥库，禁止随意使用 Debug 临时证书出包，确保用户下载新版 APK 后可**直接点击覆盖安装，此前录入的全部路线与历史轨迹 100% 完整保留**。

---

## 六、 未来演进路线与实施方案规划 (v0.7.5 ~ v1.0.0)

| 演进阶段 | 核心功能交付物 | 关键技术方案 | 验收标准与心智壁垒 |
| :--- | :--- | :--- | :--- |
| **阶段一<br>(离线切片地图实装)** | • 接入 `flutter_map` 矢量底图<br>• 天地图影像图 (`img_w`) + 中文注记 (`cia_w`)<br>• ArcGIS World Imagery 全球 0.3m 卫星图<br>• 本地磁盘持久化切片缓存<br>• 行前一键预下沿线 10km 瓦片包 | • 标准 Web 墨卡托 XYZ 瓦片协议<br>• CGCS2000 / WGS-84 坐标直通（零偏移）<br>• 内存 + 磁盘持久化两级缓存中间件 | 在拔掉 SIM 卡的飞行模式下，依然能够流畅浏览已缓存过的卫星遥感图，当前经纬度与航迹在地图上严丝合缝、毫无漂移。 |
| **阶段二<br>(VPS 轻量后台与云端保险箱)** | • 1核 2G VPS 部署轻量后端服务<br>• 用户自愿非阻塞注册与登录 (JWT)<br>• 个人轨迹与路书私有云备份<br>• APK 版本在线检测与平滑下发 | • Go (Gin) 或 Python (FastAPI)<br>• 单文件 SQLite (WAL) / Postgres<br>• 数据打包 Gzip 极小流量传输<br>• 管理后台两张表发布管理界面 | 不登录 100% 正常单机使用；登录后换手机一键恢复个人全部历史轨迹；有新版本 Wi-Fi 联网弹窗一键升级。 |
| **阶段三<br>(公开路书广场与社交车队生态)** | • **公开路书广场（发布、审核、多维筛选、一键下载至本地）**<br>• 领队-车队“6 位路书短码”一键全队分发<br>• 个人山海足迹年度长图海报生成 | • 社区路书元数据索引与轻量审核卡口<br>• 6 位短码分发路由<br>• Canvas / RepaintBoundary 海报绘制 | 形成“老炮发布实测路书 — 新手一键下载脱网巡航”的内容生态；支持车队快速同步路线与朋友圈自发裂变传播。 |
| **阶段四<br>(远期硬件与车机扩展)** | • 蓝牙/LoRa 外部硬件离线自组网对讲<br>• 车友队员位置离线实时互显<br>• 比亚迪/长城硬派车机仪表盘双屏联动 | • BLE GATT / LoRa 节点协议封装<br>• 车机 Android IVI 定制广播监听 | 无基站环境下车队车辆间距与位置离线互见，车机大屏导航体验达到工业级。 |

---
*山海行 (TerraWay) 架构委员会 · 2026年11月 · 存档于项目 Google Drive 核心目录与本地代码库*
