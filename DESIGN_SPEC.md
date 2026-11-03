# 山海行 (TerraWay) 全地形手持 GPS 导航系统
## UI/UX 视觉设计规范与全场景组件风格说明书 (v0.6.0 架构基准)

> **【规范核心目标】**：本手册用于固化「山海行 (TerraWay)」专有的工业级纯脱网手持仪器设计语言。随着业务页面逐步扩充，未来无论是添加地图渲染、离线蓝牙电台、星历热点分享还是车机扩展，所有参与开发的工程师与 UI 人员必须严格遵循本规范，**坚决杜绝风格突变、杜绝泡泡风/互联网消费软件花哨元素**，永久保持硬派三防手持机的纯粹工具质感。

---

## 一、 核心设计哲学与三大铁律 (Design Philosophy & Hard Rules)

1. **【0.5 秒高反差扫视原则】**：
   - 手持 GPS 主要应用于沙漠烈日直射、强颠簸越野自驾、风雪重装徒步等极端自然环境。驾驶员与探险者绝无闲暇在手机前仔细端详。
   - 所有核心指标（时速、距离、航向、度分秒）必须做到 **0.5 秒内用余光扫视即刻读取**。
   - **文字与背景对比度必须达到 7:1 以上**，严禁使用低对比度的浅灰渐变、半透明毛玻璃模糊遮挡核心数据。

2. **【等宽数字防抖动与垂直锁相对齐原则】**：
   - 野外行进中，GPS 经纬度、瞬时时速、直线距离与航向每秒以 1Hz~5Hz 频率高频刷新。
   - 普通比例字体在数字 1 与 8 切换时会发生横向宽度伸缩，导致整个界面高频抖动、令人眩晕。
   - **所有数据指标、坐标度分秒、计时器必须严格锁死 `fontFamily: 'monospace'`**；度分秒符号垂直垂线严格对齐，字母与数字拉开 16px 间距。

3. **【去商业大厂化工业仪器风】**：
   - 「山海行」定位于“可信赖的专业户外三防电子罗盘”，绝非互联网商业消费软件。
   - **坚决禁止引入圆润泡泡风大圆角（外圆角上限 10px）、大面积弹簧过度动画、电商卡片风、营销打扰弹窗或任何非工具属性的装饰性元素**。
   - 界面整体呈现航空仪表与地质勘测设备的严谨、精密与克制。

---

## 二、 昼夜双模语义化色彩系统 (Color Tokens)

| 色彩语义角色 | 暗夜防眩目模式 (Dark Mode) | 沙漠高光直射模式 (Light Mode) | 核心应用场景与规范要求 |
| :--- | :--- | :--- | :--- |
| **主画布基底 (Canvas)** | `#000000` / `#080808` (纯黑) | `#F8F9FA` / `#FFFFFF` (抗泛白白) | OLED 纯黑零发光省电；白昼防强日光直射反光。 |
| **一级卡片底色 (Surface)** | `#0D0D0D` / `#141414` | `#FFFFFF` (纯白) | 各功能卡片独立背景，与主底色形成清晰层级。 |
| **核心导向电光绿 (Primary Green)** | `#00FF66` (高饱和荧光电光绿) | `#008833` / `#00AA33` (深烈日绿) | 导向大箭头高光侧、主开始按钮、当前线路徽标、卫星锁定状态。 |
| **立体指针受阴绿 (Shade Green)** | `#00DD55` (深电光绿) | `#007722` (深沉遮光绿) | 3D 折面指针左翼受阴侧，与右翼形成自然三维立体折角。 |
| **指针硬核描边 (Stroke Green)** | `#003311` (极深墨绿) | `#00220A` (近黑墨绿) | 矢量大指针与卡片微边框描边，防止色彩与底色相融。 |
| **遥测与坐标青蓝 (Cyan / Sky Blue)** | `#00FFFF` / `#38BDF8` | `#0066CC` / `#0284C7` | 度分秒 DMS 坐标分段、点位数标签、卫星 C/N0 高信噪比柱体。 |
| **方位角与航向战术金 (Heading Amber)** | `#FFCC00` / `#F59E0B` | `#CC6600` / `#D97706` | 目标绝对方位角 BRG、移动真航向 COG、避坑提示卡片边框。 |
| **正北与紧急避险红 (Alert Red)** | `#FF3333` (高亮战术红) | `#DC2626` (警示鲜红) | 罗盘盘面正北 N 标、背风坡暗坑断崖险情预警、应急搜救模式。 |
| **工业标准分割线 (Border)** | `#262626` / `#1E1E1E` | `#E2E4E8` / `#DCDFE6` | 细线条勾勒，严禁使用粗重或带色彩的模糊投影替代边框。 |

---

## 三、 字体与等宽锁相对齐排版规范 (Typography System)

1. **数据大字矩阵 (Huge Metrics)**：
   - 时速 (SPEED)、距离 (DIST)、用时 (ETE)、航向 (BRG) 必须采用 `fontSize: 28.0 ~ 36.0`、`FontWeight.w900`、`fontFamily: 'monospace'`，字母间距 `-0.5`。
2. **度分秒坐标 (DMS Coordinates)**：
   - 格式统一为：`半球(N/S/E/W) + 空格 + 度数(2~3位)° + 分数(2位)' + 秒数(4位带1位小数)"`。
   - 例：`N 39°05'22.1"    E 108°48'05.4"`。
   - 度、分、秒字符间距严格由等宽列宽保证，符号在垂直方向绝对锁相对齐。
3. **标题与说明文字层级**：
   - 大模块标题：`fontSize: 16.0 ~ 18.0, FontWeight.bold`；
   - 卡片主标题：`fontSize: 14.5 ~ 15.0, FontWeight.bold`；
   - 辅助副标题：`fontSize: 11.0 ~ 12.0, color: textSecondary`，**必须单行截断 (maxLines: 1, overflow: TextOverflow.ellipsis)**，禁止多行文本挤占宝贵竖屏空间。

---

## 四、 全场景核心组件设计规范 (Component Specifications)

### 1. 落地页同款 3D 立体折面导向大指针 (Faceted Delta Wing Needle)
这是山海行最核心的视觉资产。指针形状严格按 100x100 归一化拓扑坐标解算，旋转时以绝对中心 (50, 50) 旋转，杜绝偏心摆动：
- **顶点 (Tip)**: `(0.50, 0.10)` —— 锐利尖峰，距离中心 40% 半径；
- **右翼外点 (Right Outer)**: `(0.78, 0.85)` —— 右侧高光折翼，外凸张力十足；
- **左翼外点 (Left Outer)**: `(0.22, 0.85)` —— 左侧阴影折翼，严格对称；
- **内尾凹点 (Tail Inner)**: `(0.50, 0.70)` —— 向上收紧，强化三角翼动感；
- **中心定位铆钉 (Center Pin)**: `(0.50, 0.50)`，半径 `4.2%` 纯白金属圆环；
- **立体投影**: 底部必须包含平滑立体投影 (`canvas.drawShadow`)，模拟 6.0 深度，营造悬浮于刻度盘上方的机械立体感。

### 2. 线路列表高密度紧凑卡片 (High-Density Compact Route Card)
- 单张卡片整体高度必须锁死在 **56px ~ 62px** 之间；
- 左侧为 32x32 方形状态指示图标（活跃时高亮电光绿）；
- 中间为双行紧凑文字：第一行「路线名 + 点位微标签 (如 8点) + 当前导向标」，第二行「单行地标说明」；
- 右侧内联紧凑操作区：小尺寸编辑点位按钮 + 32px 紧凑「导航」按钮；
- 手机竖屏单屏必须能够**完整呈现 8 ~ 10 条线路**。

### 3. 首页底部主控按钮规范 (Bottom Navigation Bar)
- **对称等宽原则**：主控条包含两个 50px 高度的大尺寸安全触控按钮，按 `flex: 1` 和 `flex: 1`（各占 50% 宽度）严格等宽对称排版；
- **精炼二字标头**：常态下左侧为「路线」，右侧为「轨迹」，字符数完全一致，绝不在任何小屏机型或超大系统字体下发生折行；
- **后台导航动态变体**：若后台有导航正在运行，左侧按钮自适应变为**「返回导航」**（带闪烁导航标与电光绿背景），右侧依旧保持「轨迹」。

### 4. 顶部通用探险者头像与系统功能抽屉 (Explorer Avatar Hub)
- **头像入口**：顶栏右侧设立 `CircleAvatar(radius: 15)` 探险者头像，外圈带 1.8px 电光绿边框与微光投影；
- **功能综合抽屉 (Modal BottomSheet)**：点击头像平滑滑出系统级功能面板，集中承载：
  1. 探险者身份卡片 (纯硬件脱网定位就绪状态)；
  2. 昼夜显示模式切换 (系统 / 沙漠白 / 暗夜黑)；
  3. 中英多语言即时切换 (简体中文 / English)；
  4. 全地形运动模式选择 (越野 150m / 徒步 30m / 骑行 80m / 搜救 50m)；
  5. 北斗/GPS 双模星历遥测全景入口；
  6. 户外安全须知与法律免责声明入口；
  7. 关于山海行与版本签名保障说明。

### 5. 导航生命周期与退出二次确认规范
- **开启导航**：点击任意路线或“导航”按钮，必须弹出「开始路线导航？」二次确认弹窗，明确告知将开启罗盘与后台同步轨迹记录；
- **退出导航**：行进中点击返回或滑动系统返回手势，**严禁直接退出**，必须弹出「是否退出当前导航？」询问弹窗：
  - 点【返回首页 (后台继续)】：仪表盘退回首页，导航导引与轨迹高频采样在后台持续静默运行，首页底部切换为「返回导航」；
  - 点【退出导航 (结束)】：停止传感器定位，弹出行程里程时间总结，并询问「保存到本机历史库」或「不保存放弃本次轨迹」。

---

## 五、 Flutter 基础样式代码 (AppStyle Token Code)

在项目中直接引入 `import '../core/app_style.dart';` 即可直接取用预设的设计令牌：

```dart
// 1. 仪表盘核心四宫格数值与标签
Text(
  "42 km/h",
  style: AppStyle.metricValueStyle(isDark, color: AppStyle.primaryGreen(isDark)),
);
Text(
  "瞬时速度 (SPEED)",
  style: AppStyle.metricLabelStyle(isDark),
);

// 2. 高密度路线卡片标准装饰
Container(
  height: AppStyle.compactListItemHeight, // 严格约束 58px 高度
  decoration: AppStyle.cardDecoration(isDark: isDark, isActive: isActive),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  child: Row(
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? AppStyle.primaryGreen(isDark) : AppStyle.cardBackground(isDark),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(isActive ? Icons.navigation : Icons.alt_route, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("阿尔山森林腹地穿越线", style: AppStyle.cardTitleStyle(isDark)),
            Text("沿途共 12 个地质打卡与补给水井", style: AppStyle.cardSubtitleStyle(isDark), maxLines: 1),
          ],
        ),
      ),
    ],
  ),
);

// 3. 搜索输入框标准修饰
TextField(
  decoration: AppStyle.searchInputDecoration(
    isDark: isDark,
    hintText: "搜索路线名称、地标或途经点...",
    prefixIcon: Icon(Icons.search, color: AppStyle.primaryGreen(isDark)),
  ),
);
```

---

## 六、 后续开发防风格突变审核清单 (Developer Checklist)

| 检查项 | 合规标准 (Do's) | 违规禁止项 (Don'ts) |
| :--- | :--- | :--- |
| **数据字体** | 时速、距离、度分秒坐标、航向严格使用 `monospace` 等宽字体。 | 严禁使用系统默认变宽无衬线字体渲染动态跳动的数值。 |
| **圆角弧度** | 卡片与按钮圆角固定为 `8px`，微标签固定为 `4px`。 | 严禁使用 `16px~24px` 互联网圆润胶囊泡泡风。 |
| **色彩规范** | 严格从 `AppStyle` 中引用电光绿、烈日绿、战术明黄与深黑纯白。 | 严禁使用粉红、紫色、渐变粉彩等非专业仪器色彩。 |
| **列表高度** | 列表单行高度严格控制在 `56px~64px` 内，内联操作按钮。 | 严禁每个列表项堆叠多行大按钮，导致单屏显示少于 5 条。 |
| **文字折行** | 底部按钮文字不超过 4 个字；副标题一律 `maxLines: 1` 单行截断。 | 严禁在窄屏下出现按钮文字回行、双行错位或排版破损。 |

---
*山海行 (TerraWay) 架构委员会 · 2026年10月 发布 · 版权所有 © 保留所有权利*
