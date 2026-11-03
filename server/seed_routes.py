#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# 山海行 (TerraWay) - 国内 62 条经典顶级越野/徒步/自驾全景路线一键直写种子脚本
# 适用场景: VPS 本地一键向 SQLite (terraway_public.db) 注入 62 条官方全量路线
# ==============================================================================

import sqlite3, os, json, sys, datetime

DB_PATHS = [
    './data/terraway_public.db',
    '../data/terraway_public.db',
    '/opt/terraway-server/data/terraway_public.db',
    '/app/data/terraway_public.db'
]

db_path = None
for p in DB_PATHS:
    if os.path.exists(p):
        db_path = p
        break

if not db_path:
    os.makedirs('./data', exist_ok=True)
    db_path = './data/terraway_public.db'

print(f"[*] 正在连接公共路书数据库: {db_path}")
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# 确保表结构存在
cur.execute('''
CREATE TABLE IF NOT EXISTS public_roadbooks (
    id TEXT PRIMARY KEY,
    author_id TEXT NOT NULL,
    author_name TEXT NOT NULL,
    title TEXT NOT NULL,
    region TEXT NOT NULL,
    terrain TEXT NOT NULL,
    category TEXT NOT NULL,
    difficulty INTEGER NOT NULL,
    vehicle_req TEXT NOT NULL,
    distance_km REAL NOT NULL,
    points_count INTEGER NOT NULL,
    elevation_gain_m REAL NOT NULL,
    elevation_max_m REAL NOT NULL,
    estimated_duration TEXT NOT NULL,
    best_season TEXT NOT NULL,
    downloads_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'approved',
    roadbook_json TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    reviewed_at DATETIME,
    reviewer_name TEXT
);
''')
conn.commit()

ROUTES = [
  {
    "id": "pub_nm_01",
    "title": "巴丹吉林沙漠穿行越野线",
    "region": "neimenggu",
    "terrain": "desert_dune",
    "category": "offroad",
    "difficulty": 5,
    "vehicle_req": "4x4_extreme",
    "distance_km": 182.5,
    "elevation_gain_m": 850,
    "elevation_max_m": 1611,
    "estimated_duration": "3天2夜",
    "best_season": "5-10月",
    "downloads_count": 892,
    "description": "中国最美沙漠核心穿越线。跨越世界最高沙峰“必鲁图沙峰”，探访沙漠奇观音德日图神泉、仙女峰与庙海子。全线为重度流动高大沙丘，沙刀与暗沙梁密布，极易陷车翻滚，必须硬派高底盘四驱双锁车型且由两台以上车队同行，配齐防沙旗、放气减压表（胎压需降至0.6-0.8 bar）及脱困防滑板。",
    "waypoints": [
      {
        "id": "wp_nm01_1",
        "name": "巴丹吉林地质公园入口",
        "lat": 39.3512,
        "lon": 102.3214,
        "ele": 1210,
        "desc": "入沙检查登记，放胎压至0.8bar，插沙旗"
      },
      {
        "id": "wp_nm01_2",
        "name": "巴丹湖营地",
        "lat": 39.423,
        "lon": 102.385,
        "ele": 1235,
        "desc": "首个沙漠湖泊，淡水补给与首晚露营点"
      },
      {
        "id": "wp_nm01_3",
        "name": "音德日图神泉湖",
        "lat": 39.754,
        "lon": 102.432,
        "ele": 1280,
        "desc": "咸水湖中涌现百眼淡水泉，地质奇观，禁止冲滩"
      },
      {
        "id": "wp_nm01_4",
        "name": "必鲁图沙峰脚下",
        "lat": 39.812,
        "lon": 102.473,
        "ele": 1390,
        "desc": "世界最高沙峰基座，坡度达45度，需大动力冲顶"
      },
      {
        "id": "wp_nm01_5",
        "name": "必鲁图珠峰观景台",
        "lat": 39.825,
        "lon": 102.481,
        "ele": 1611,
        "desc": "俯瞰数个彩色盐湖群，信号微弱，注意防风"
      },
      {
        "id": "wp_nm01_6",
        "name": "庙海子沙漠绿洲",
        "lat": 39.789,
        "lon": 102.408,
        "ele": 1260,
        "desc": "藏传佛教巴丹吉林庙，补给燃油水饮中继站"
      },
      {
        "id": "wp_nm01_7",
        "name": "诺尔图湖畔",
        "lat": 39.712,
        "lon": 102.355,
        "ele": 1245,
        "desc": "沙漠最大湖泊，沙山倒影极佳出片点"
      },
      {
        "id": "wp_nm01_8",
        "name": "雅布赖镇出沙口",
        "lat": 39.601,
        "lon": 102.185,
        "ele": 1205,
        "desc": "出沙公路连接点，给轮胎充气，完成穿越"
      }
    ]
  },
  {
    "id": "pub_nm_02",
    "title": "克什克腾旗·达里诺尔湖大环线",
    "region": "neimenggu",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "at_tire",
    "distance_km": 328.0,
    "elevation_gain_m": 420,
    "elevation_max_m": 1420,
    "estimated_duration": "2天1夜",
    "best_season": "6-9月",
    "downloads_count": 645,
    "description": "内蒙古经典草原自驾大环线。串联贡格尔草原、热水塘温泉、达里湖（达里诺尔）、砧子山古岩画以及阿斯哈图石林第四纪冰川花岗岩石臼地貌。路况以柏油路、铺装碎石及草原车辙道为主，四驱SUV或更换AT胎即可轻松通达。",
    "waypoints": [
      {
        "id": "wp_nm02_1",
        "name": "经棚镇起点",
        "lat": 43.265,
        "lon": 117.538,
        "ele": 1020,
        "desc": "克什克腾旗首府，完成油料与食物采购"
      },
      {
        "id": "wp_nm02_2",
        "name": "热水塘地热温泉",
        "lat": 43.372,
        "lon": 117.485,
        "ele": 1090,
        "desc": "著名硫磺温泉小镇，疗养歇脚"
      },
      {
        "id": "wp_nm02_3",
        "name": "达里诺尔湖北岸",
        "lat": 43.328,
        "lon": 116.654,
        "ele": 1226,
        "desc": "候鸟天堂，火山熔岩堰塞湖，观夕阳晚霞"
      },
      {
        "id": "wp_nm02_4",
        "name": "砧子山古岩画",
        "lat": 43.361,
        "lon": 116.602,
        "ele": 1310,
        "desc": "孤峰突起火山口遗迹，古突厥岩画"
      },
      {
        "id": "wp_nm02_5",
        "name": "贡格尔草原腹地",
        "lat": 43.452,
        "lon": 116.985,
        "ele": 1150,
        "desc": "风车群与河曲草原，土路车辙注意减速"
      },
      {
        "id": "wp_nm02_6",
        "name": "阿斯哈图石林",
        "lat": 44.053,
        "lon": 117.265,
        "ele": 1420,
        "desc": "第四纪冰川遗迹石林群，地质公园打卡"
      },
      {
        "id": "wp_nm02_7",
        "name": "黄岗梁大兴安岭主峰",
        "lat": 43.725,
        "lon": 117.489,
        "ele": 1380,
        "desc": "大兴安岭最高峰森林秋景与盘山弯道"
      },
      {
        "id": "wp_nm02_8",
        "name": "经棚终点闭环",
        "lat": 43.265,
        "lon": 117.538,
        "ele": 1020,
        "desc": "返回起点完成环线"
      }
    ]
  },
  {
    "id": "pub_nm_03",
    "title": "库布齐沙漠东段重装徒步穿越",
    "region": "neimenggu",
    "terrain": "desert_dune",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 46.8,
    "elevation_gain_m": 320,
    "elevation_max_m": 1230,
    "estimated_duration": "2天1夜",
    "best_season": "4-5月, 9-10月",
    "downloads_count": 520,
    "description": "国内最适合新手晋升进阶的重装沙漠徒步路线。由响沙湾西行穿越连绵沙丘至恩格贝生态示范区，沿途横穿断续沙梁与草滩。需备足每日至少4L饮用水、雪套（防沙套）、GPS离线导航手持设备、防风沙护目镜与抗风沙帐篷。",
    "waypoints": [
      {
        "id": "wp_nm03_1",
        "name": "响沙湾入沙点",
        "lat": 40.298,
        "lon": 109.985,
        "ele": 1080,
        "desc": "穿戴雪套，配足4L水源，校准手持罗盘"
      },
      {
        "id": "wp_nm03_2",
        "name": "一号绿洲锁边林",
        "lat": 40.325,
        "lon": 109.852,
        "ele": 1120,
        "desc": "人工草方格防护林边缘，微弱手机信号"
      },
      {
        "id": "wp_nm03_3",
        "name": "龙头拐高大沙梁",
        "lat": 40.362,
        "lon": 109.689,
        "ele": 1230,
        "desc": "沙梁顶脊线行走阻力较小，沿背风坡滑行"
      },
      {
        "id": "wp_nm03_4",
        "name": "沙心露营地",
        "lat": 40.395,
        "lon": 109.521,
        "ele": 1180,
        "desc": "避风低洼平地扎营，重装打地钉固定防风绳"
      },
      {
        "id": "wp_nm03_5",
        "name": "黑赖沟断流河床",
        "lat": 40.428,
        "lon": 109.385,
        "ele": 1100,
        "desc": "沙石混杂河床，注意防陷泥沼"
      },
      {
        "id": "wp_nm03_6",
        "name": "恩格贝生态区终点",
        "lat": 40.485,
        "lon": 109.215,
        "ele": 1030,
        "desc": "抵达绿洲，洗去沙尘，联系接驳车返程"
      }
    ]
  },
  {
    "id": "pub_nm_04",
    "title": "呼伦贝尔大草原·中俄边防自驾",
    "region": "neimenggu",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 680.0,
    "elevation_gain_m": 380,
    "elevation_max_m": 820,
    "estimated_duration": "4天3夜",
    "best_season": "6-8月, 9月中下旬",
    "downloads_count": 1120,
    "description": "中国北疆最辽阔温情的边防公路自驾之旅。沿额尔古纳河（中俄界河）顺流而下，途经天下第一曲水莫日格勒河、白桦林、黑山头骑马场、边境卡线（五卡/七卡/九卡）、室韦俄罗斯民族乡直至满洲里国门。全程景观开阔壮丽，路况良好，普通家用SUV即可顺畅通行。",
    "waypoints": [
      {
        "id": "wp_nm04_1",
        "name": "海拉尔出发",
        "lat": 49.215,
        "lon": 119.754,
        "ele": 610,
        "desc": "租车/自驾集合，补给冷库牛羊肉与行囊"
      },
      {
        "id": "wp_nm04_2",
        "name": "莫日格勒河九曲观景台",
        "lat": 49.421,
        "lon": 119.985,
        "ele": 650,
        "desc": "天下第一曲水，草原俯瞰蜿蜒河道"
      },
      {
        "id": "wp_nm04_3",
        "name": "额尔古纳湿地公园",
        "lat": 50.245,
        "lon": 120.178,
        "ele": 580,
        "desc": "亚洲第一湿地灌木丛群落"
      },
      {
        "id": "wp_nm04_4",
        "name": "黑山头马术训练营",
        "lat": 50.215,
        "lon": 119.562,
        "ele": 530,
        "desc": "日落山俯瞰额尔古纳河日落，体验骑马"
      },
      {
        "id": "wp_nm04_5",
        "name": "七卡边防中俄界河公路",
        "lat": 50.852,
        "lon": 119.921,
        "ele": 510,
        "desc": "边防巡逻X904县道，近观对岸俄境木屋"
      },
      {
        "id": "wp_nm04_6",
        "name": "室韦俄罗斯民族乡",
        "lat": 51.345,
        "lon": 119.892,
        "ele": 520,
        "desc": "住木刻楞小木屋，品尝俄式大列巴与蓝莓酱"
      },
      {
        "id": "wp_nm04_7",
        "name": "满洲里口岸国门",
        "lat": 49.598,
        "lon": 117.438,
        "ele": 590,
        "desc": "国门景区，中俄蒙三国异域风情夜景"
      }
    ]
  },
  {
    "id": "pub_nm_05",
    "title": "乌兰布统草原越野穿越线",
    "region": "neimenggu",
    "terrain": "forest_mountain",
    "category": "offroad",
    "difficulty": 3,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 125.0,
    "elevation_gain_m": 480,
    "elevation_max_m": 1580,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月, 12-2月雪原",
    "downloads_count": 780,
    "description": "京津冀越野车友的“后花园与练兵场”。涵盖塞罕坝界河、蛤蟆坝摄影天堂、透亮沟涉水穿越、影视基地以及野鸭湖。春夏季绿浪翻滚，秋季层林尽染，冬季则是天然大雪原漂移越野圣地。透亮沟包含多处卵石浅滩涉水，需检查进气口与排气管离地间隙。",
    "waypoints": [
      {
        "id": "wp_nm05_1",
        "name": "御道口牧场入山口",
        "lat": 42.125,
        "lon": 117.025,
        "ele": 1320,
        "desc": "承德入塞罕坝国家森林公园门禁"
      },
      {
        "id": "wp_nm05_2",
        "name": "乌兰布统古战场遗迹",
        "lat": 42.582,
        "lon": 117.214,
        "ele": 1410,
        "desc": "康熙亲征噶尔丹历史遗迹点"
      },
      {
        "id": "wp_nm05_3",
        "name": "影视基地北沟",
        "lat": 42.632,
        "lon": 117.285,
        "ele": 1460,
        "desc": "百部影视剧取景地，起伏丘陵草甸车辙道"
      },
      {
        "id": "wp_nm05_4",
        "name": "蛤蟆坝摄影平台",
        "lat": 42.715,
        "lon": 117.382,
        "ele": 1510,
        "desc": "沟谷错落农耕草原结合，晨雾与牛羊炊烟"
      },
      {
        "id": "wp_nm05_5",
        "name": "透亮沟涉水段",
        "lat": 42.685,
        "lon": 117.452,
        "ele": 1380,
        "desc": "连续卵石涉水滩，挂低速四驱稳油门通过"
      },
      {
        "id": "wp_nm05_6",
        "name": "暖水河红松林出口",
        "lat": 42.541,
        "lon": 117.158,
        "ele": 1350,
        "desc": "湿地蜿蜒河流，出山接承围公路"
      }
    ]
  },
  {
    "id": "pub_nm_06",
    "title": "浑善达克沙地腹地穿越线",
    "region": "neimenggu",
    "terrain": "desert_dune",
    "category": "offroad",
    "difficulty": 4,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 218.0,
    "elevation_gain_m": 350,
    "elevation_max_m": 1380,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月",
    "downloads_count": 460,
    "description": "被誉为“塞外水乡沙地”的典型半固定沙丘穿行路线。沙丘高大且植被丰富，暗藏多处沼泽湿地与柳丛泥塘（俗称烂泥潭）。需要掌握沙丘滚刀梁切入技巧，避开水草丰茂的隐蔽泥淖，极度考验驾驶者的选线眼力和领航默契。",
    "waypoints": [
      {
        "id": "wp_nm06_1",
        "name": "正蓝旗上都镇起点",
        "lat": 42.254,
        "lon": 116.012,
        "ele": 1210,
        "desc": "元上都遗址旁集结，放胎压至1.0bar"
      },
      {
        "id": "wp_nm06_2",
        "name": "小扎格斯台淖尔湖",
        "lat": 42.482,
        "lon": 115.892,
        "ele": 1265,
        "desc": "沙漠中的淡水湖，沙山与芦苇相映成趣"
      },
      {
        "id": "wp_nm06_3",
        "name": "榆树林沙梁分水岭",
        "lat": 42.651,
        "lon": 115.752,
        "ele": 1340,
        "desc": "沙地疏林景观，沙脊骑梁行驶注意对向盲区"
      },
      {
        "id": "wp_nm06_4",
        "name": "高格斯台河涉水点",
        "lat": 42.812,
        "lon": 115.621,
        "ele": 1250,
        "desc": "河床较软，切勿停车怠速，紧跟前车车辙"
      },
      {
        "id": "wp_nm06_5",
        "name": "哈毕日嘎镇公路出沙口",
        "lat": 42.985,
        "lon": 115.421,
        "ele": 1190,
        "desc": "驶入国道，补气洗车完成穿越"
      }
    ]
  },
  {
    "id": "pub_nm_07",
    "title": "乌兰哈达火山地质巡游线",
    "region": "neimenggu",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 85.0,
    "elevation_gain_m": 260,
    "elevation_max_m": 1450,
    "estimated_duration": "1天",
    "best_season": "4-10月, 适合太空服出片",
    "downloads_count": 960,
    "description": "内蒙古察哈尔右翼后旗火山群地质探索。由3号北炼丹炉（修有木栈道）、4号黑脑包（火山石柱）、5号中炼丹炉（保存最完整火山口锥体）及6号南炼丹炉组成。犹如漫步火星地表，适合轻越野、摄影露营与星空夜拍。",
    "waypoints": [
      {
        "id": "wp_nm07_1",
        "name": "察右后旗白音察干集结点",
        "lat": 41.452,
        "lon": 113.185,
        "ele": 1380,
        "desc": "国道补给，租借宇航服拍照道具"
      },
      {
        "id": "wp_nm07_2",
        "name": "3号火山(北炼丹炉)",
        "lat": 41.582,
        "lon": 113.215,
        "ele": 1420,
        "desc": "设有木栈道可登顶火山口俯瞰平原"
      },
      {
        "id": "wp_nm07_3",
        "name": "4号火山(黑脑包玛瑙滩)",
        "lat": 41.552,
        "lon": 113.225,
        "ele": 1410,
        "desc": "黑色玄武岩地质构造，地面有火山玛瑙碎石"
      },
      {
        "id": "wp_nm07_4",
        "name": "5号火山(中炼丹炉最美锥体)",
        "lat": 41.521,
        "lon": 113.235,
        "ele": 1450,
        "desc": "保存最完好火山锥，夕阳落日熔岩奇观"
      },
      {
        "id": "wp_nm07_5",
        "name": "6号火山(南炼丹炉开采遗迹)",
        "lat": 41.485,
        "lon": 113.245,
        "ele": 1430,
        "desc": "半截被开采的火山口截面，宛如太空基地"
      }
    ]
  },
  {
    "id": "pub_nm_08",
    "title": "额济纳胡杨林·黑城弱水穿越",
    "region": "neimenggu",
    "terrain": "desert_dune",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "at_tire",
    "distance_km": 195.0,
    "elevation_gain_m": 180,
    "elevation_max_m": 1020,
    "estimated_duration": "2天1夜",
    "best_season": "9月下旬-10月中旬",
    "downloads_count": 1250,
    "description": "阿拉善大漠深处金色奇迹之路。金秋十月胡杨树叶金黄璀璨，串联达来呼布镇一至八道桥、西夏黑城遗址古城堡、弱水金沙湾与怪树林千年枯木。夜宿大漠露营观赏绝美银河。",
    "waypoints": [
      {
        "id": "wp_nm08_1",
        "name": "达来呼布镇一道桥",
        "lat": 41.958,
        "lon": 101.052,
        "ele": 940,
        "desc": "额济纳旗政府所在地，胡杨林国家级保护区起点"
      },
      {
        "id": "wp_nm08_2",
        "name": "四道桥英雄林",
        "lat": 41.985,
        "lon": 101.152,
        "ele": 950,
        "desc": "电影《英雄》取景地，古老苍劲金黄胡杨"
      },
      {
        "id": "wp_nm08_3",
        "name": "八道桥巴丹吉林沙漠北缘",
        "lat": 42.012,
        "lon": 101.285,
        "ele": 980,
        "desc": "沙漠与胡杨交界处，滑沙驼队出片"
      },
      {
        "id": "wp_nm08_4",
        "name": "居延海芦苇湿地日出点",
        "lat": 42.315,
        "lon": 101.452,
        "ele": 900,
        "desc": "老子化胡西出之地，晨曦群鸟翔集"
      },
      {
        "id": "wp_nm08_5",
        "name": "黑城古遗址(西夏黑水城)",
        "lat": 41.752,
        "lon": 101.125,
        "ele": 920,
        "desc": "丝路最完整古城城堡遗址，黄沙掩埋佛塔"
      },
      {
        "id": "wp_nm08_6",
        "name": "怪树林千年不倒枯木群",
        "lat": 41.725,
        "lon": 101.105,
        "ele": 930,
        "desc": "“生而一千年不死，死而一千年不倒”，晚霞悲壮"
      }
    ]
  },
  {
    "id": "pub_xj_09",
    "title": "独库公路全线壮美自驾 (G217)",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 561.0,
    "elevation_gain_m": 2650,
    "elevation_max_m": 3390,
    "estimated_duration": "2~3天",
    "best_season": "6月中旬-10月初",
    "downloads_count": 2840,
    "description": "“一天经历四季，十里不同天”。贯穿天山南北的英雄之路，连接北疆独山子与南疆库车。翻越哈希勒根达坂、玉希莫勒盖达坂、铁力买提达坂3座雪山垭口，途径乔尔玛烈士陵园、巴音布鲁克天鹅湖与库车大峡谷。仅限7座及以下小客车通行，需密切关注气候封路通知。",
    "waypoints": [
      {
        "id": "wp_xj09_1",
        "name": "独山子大峡谷入口(零公里)",
        "lat": 44.312,
        "lon": 84.885,
        "ele": 850,
        "desc": "独库公路起点，检查刹车油水，加满汽油"
      },
      {
        "id": "wp_xj09_2",
        "name": "哈希勒根防雪走廊(3390m)",
        "lat": 43.782,
        "lon": 84.625,
        "ele": 3390,
        "desc": "北段最高海拔雪山达坂，常年积雪"
      },
      {
        "id": "wp_xj09_3",
        "name": "乔尔玛革命烈士陵园",
        "lat": 43.654,
        "lon": 84.512,
        "ele": 2180,
        "desc": "缅怀筑路筑梦筑脊梁的168名解放军烈士"
      },
      {
        "id": "wp_xj09_4",
        "name": "那拉提草原连通岔口",
        "lat": 43.325,
        "lon": 84.015,
        "ele": 1650,
        "desc": "空中草原与巩乃斯森林交汇口"
      },
      {
        "id": "wp_xj09_5",
        "name": "巴音布鲁克天鹅湖",
        "lat": 43.025,
        "lon": 84.152,
        "ele": 2450,
        "desc": "开都河日落九个太阳奇观，高原湿地"
      },
      {
        "id": "wp_xj09_6",
        "name": "铁力买提达坂隧道",
        "lat": 42.482,
        "lon": 83.585,
        "ele": 3220,
        "desc": "穿透天山南北分水岭，驶出即进入南疆热风"
      },
      {
        "id": "wp_xj09_7",
        "name": "大龙池·小龙池",
        "lat": 42.152,
        "lon": 83.254,
        "ele": 2390,
        "desc": "高山冰碛堰塞湖，碧蓝如翡翠"
      },
      {
        "id": "wp_xj09_8",
        "name": "库车天山大峡谷终点",
        "lat": 41.985,
        "lon": 83.052,
        "ele": 1600,
        "desc": "红褐色克孜利亚地貌，终点库车南疆人文"
      }
    ]
  },
  {
    "id": "pub_xj_10",
    "title": "喀喇昆仑公路 (G314·中巴友谊路)",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 415.0,
    "elevation_gain_m": 3450,
    "elevation_max_m": 4733,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月",
    "downloads_count": 1980,
    "description": "世界上最高最惊险的国际公路之一。从古城喀什出发，横跨帕米尔高原，仰望慕士塔格峰（7546m）、公格尔九别峰，驻足白沙湖梦幻蓝白倒影与卡拉库里湖，穿过塔什库尔干石头城与金草滩，直至海拔4733米的红其拉甫国门口岸。需在喀什预先办理边防通行证。",
    "waypoints": [
      {
        "id": "wp_xj10_1",
        "name": "喀什古城西大门",
        "lat": 39.472,
        "lon": 75.985,
        "ele": 1280,
        "desc": "查验边防通行证，备好氧气袋与抗高反装备"
      },
      {
        "id": "wp_xj10_2",
        "name": "奥依塔克红山峡谷",
        "lat": 39.125,
        "lon": 75.452,
        "ele": 2100,
        "desc": "丹霞赤壁地貌，公路开始攀升进入帕米尔"
      },
      {
        "id": "wp_xj10_3",
        "name": "布伦口白沙湖观景台",
        "lat": 38.752,
        "lon": 75.052,
        "ele": 3300,
        "desc": "银白沙山与碧水交融，帕米尔高原明珠"
      },
      {
        "id": "wp_xj10_4",
        "name": "卡拉库里湖(慕士塔格峰下)",
        "lat": 38.452,
        "lon": 75.045,
        "ele": 3690,
        "desc": "近距离仰视慕士塔格峰与公格尔峰"
      },
      {
        "id": "wp_xj10_5",
        "name": "塔什库尔干石头城金草滩",
        "lat": 37.775,
        "lon": 75.228,
        "ele": 3100,
        "desc": "塔吉克族自治县，金草滩湿地夜宿"
      },
      {
        "id": "wp_xj10_6",
        "name": "瓦罕走廊岔口界碑",
        "lat": 37.215,
        "lon": 75.385,
        "ele": 3890,
        "desc": "玄奘法师东归之路古道入口"
      },
      {
        "id": "wp_xj10_7",
        "name": "红其拉甫前哨国门",
        "lat": 36.852,
        "lon": 75.428,
        "ele": 4733,
        "desc": "中国最西端口岸界碑，气候严寒严禁剧烈运动"
      }
    ]
  },
  {
    "id": "pub_xj_11",
    "title": "盘龙古道“今日走过所有弯路”",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 3,
    "vehicle_req": "suv_standard",
    "distance_km": 38.0,
    "elevation_gain_m": 1150,
    "elevation_max_m": 4210,
    "estimated_duration": "半天",
    "best_season": "5-10月",
    "downloads_count": 2450,
    "description": "帕米尔高原悬崖上的疯狂发卡弯。连接塔县与瓦恰乡的盘山天路，全长30多公里，拥有超过600多个弯道，落差超千米，海拔最高达4200米。“今日走过了人生所有的弯路，从此人生尽是坦途”。建议低速挡行驶，禁止空挡滑行。",
    "waypoints": [
      {
        "id": "wp_xj11_1",
        "name": "瓦恰公路西入口(大盘龙起点)",
        "lat": 37.685,
        "lon": 75.312,
        "ele": 3080,
        "desc": "网红标牌打卡，检查刹车盘片温度"
      },
      {
        "id": "wp_xj11_2",
        "name": "大盘龙盘山观景平台",
        "lat": 37.662,
        "lon": 75.352,
        "ele": 3680,
        "desc": "俯瞰密集整齐的S弯天路，如黑色巨龙卧雪峰"
      },
      {
        "id": "wp_xj11_3",
        "name": "盘龙古道最高垭口(4210m)",
        "lat": 37.635,
        "lon": 75.385,
        "ele": 4210,
        "desc": "最高峰拍照，风力强劲注意随身物品"
      },
      {
        "id": "wp_xj11_4",
        "name": "小盘龙密集发卡弯",
        "lat": 37.612,
        "lon": 75.421,
        "ele": 3520,
        "desc": "更小半径的急转弯，必须鸣笛慢速通过"
      },
      {
        "id": "wp_xj11_5",
        "name": "瓦恰乡杏花村出口",
        "lat": 37.585,
        "lon": 75.485,
        "ele": 2890,
        "desc": "驶入安静质朴的塔吉克小村庄"
      }
    ]
  },
  {
    "id": "pub_xj_12",
    "title": "伊昭公路白石峰穿越线 (S237)",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 3,
    "vehicle_req": "at_tire",
    "distance_km": 180.0,
    "elevation_gain_m": 1950,
    "elevation_max_m": 3120,
    "estimated_duration": "1天",
    "best_season": "6月-10月(每年仅夏季通车)",
    "downloads_count": 1150,
    "description": "伊犁仅次于独库公路的险峻天路。从伊宁出发经察布查尔翻越乌孙山白石峰达坂直达昭苏大草原。崖壁陡峭，临渊而建，弯急坡陡，雨雾天易发生落石与暗冰。限座7座及以下小车通行。",
    "waypoints": [
      {
        "id": "wp_xj12_1",
        "name": "察布查尔县锡伯自治县起点",
        "lat": 43.835,
        "lon": 81.145,
        "ele": 620,
        "desc": "伊犁河谷平原向乌孙山攀升起点"
      },
      {
        "id": "wp_xj12_2",
        "name": "安格列特达坂盘山道",
        "lat": 43.512,
        "lon": 81.185,
        "ele": 2450,
        "desc": "连续Z字发卡弯，陡峭崖壁视野开阔"
      },
      {
        "id": "wp_xj12_3",
        "name": "白石峰观景台(3120m)",
        "lat": 43.421,
        "lon": 81.195,
        "ele": 3120,
        "desc": "白色石灰岩巨峰拔地而起，巍峨雄奇"
      },
      {
        "id": "wp_xj12_4",
        "name": "乌孙山南坡高山草甸",
        "lat": 43.325,
        "lon": 81.162,
        "ele": 2350,
        "desc": "下山进入平坦辽阔的昭苏盆地"
      },
      {
        "id": "wp_xj12_5",
        "name": "昭苏天马文化园终点",
        "lat": 43.158,
        "lon": 81.125,
        "ele": 1820,
        "desc": "万马奔腾，天马故乡昭苏县城"
      }
    ]
  },
  {
    "id": "pub_xj_13",
    "title": "乌孙古道南北重装徒步穿越",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 128.0,
    "elevation_gain_m": 3800,
    "elevation_max_m": 3860,
    "estimated_duration": "6天5夜",
    "best_season": "8月下旬-10月初",
    "downloads_count": 890,
    "description": "中国十大徒步路线之冠。北起特克斯琼库什台，南出阿克苏拜城黑英山。沿途翻越包扎墩达坂与阿克布拉克达坂，溜索飞渡汹涌的科克苏河，途经高山绝美堰塞湖“天堂湖（阿克库勒湖）”。全线无补给、无信号，过河数十次水深至大腿，需携带卫星电话、过河朔溪鞋、潜水袜及高强度专业轻量化装备。",
    "waypoints": [
      {
        "id": "wp_xj13_1",
        "name": "琼库什台村牧业点",
        "lat": 43.125,
        "lon": 82.254,
        "ele": 2050,
        "desc": "徒步起点，称重背包（建议控制在18kg以内）"
      },
      {
        "id": "wp_xj13_2",
        "name": "包扎墩达坂垭口(3660m)",
        "lat": 42.895,
        "lon": 82.215,
        "ele": 3660,
        "desc": "乱石碎坡陡峭攀升，碎石滑坠高风险"
      },
      {
        "id": "wp_xj13_3",
        "name": "科克苏河溜索飞渡点",
        "lat": 42.752,
        "lon": 82.152,
        "ele": 2180,
        "desc": "水流湍急严禁徒步渡河，必须使用滑轮溜索过河"
      },
      {
        "id": "wp_xj13_4",
        "name": "天堂湖(阿克库勒湖)",
        "lat": 42.582,
        "lon": 82.025,
        "ele": 3100,
        "desc": "深邃湛蓝湖泊，栈道贴壁行走注意重心稳定"
      },
      {
        "id": "wp_xj13_5",
        "name": "阿克布拉克达坂(3860m)",
        "lat": 42.495,
        "lon": 81.985,
        "ele": 3860,
        "desc": "终年积雪达坂，暴风雪风险极高"
      },
      {
        "id": "wp_xj13_6",
        "name": "博孜克日格河谷涉水区",
        "lat": 42.325,
        "lon": 82.012,
        "ele": 2200,
        "desc": "一日内连续涉渡冰川融水20余次，失温高发区"
      },
      {
        "id": "wp_xj13_7",
        "name": "黑英山村出口",
        "lat": 42.112,
        "lon": 82.152,
        "ele": 1420,
        "desc": "出峡谷乘车出山，完成顶级朝圣之行"
      }
    ]
  },
  {
    "id": "pub_xj_14",
    "title": "夏特古道南北徒步探险",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 115.0,
    "elevation_gain_m": 3200,
    "elevation_max_m": 3580,
    "estimated_duration": "5天4夜",
    "best_season": "5月-6月, 9月-10月",
    "downloads_count": 650,
    "description": "跨越天山汗腾格里峰冰川的古丝绸之路险径。从昭苏夏特温泉向南，横跨木扎尔特大冰川冰塔林、冰裂缝，翻越哈达木孜达坂，出阿克苏温宿县。冰裂缝遍布、流沙冰崩频繁，必须结组使用冰爪、高山绳索与头盔等冰雪行进装备。",
    "waypoints": [
      {
        "id": "wp_xj14_1",
        "name": "夏特温泉度假村登山口",
        "lat": 42.785,
        "lon": 80.852,
        "ele": 2280,
        "desc": "徒步起点，向木扎尔特河谷溯流而上"
      },
      {
        "id": "wp_xj14_2",
        "name": "三号冰川观测营地",
        "lat": 42.612,
        "lon": 80.812,
        "ele": 2980,
        "desc": "近观木扎尔特巨型蓝色悬冰川"
      },
      {
        "id": "wp_xj14_3",
        "name": "木扎尔特大冰川前舌",
        "lat": 42.485,
        "lon": 80.785,
        "ele": 3280,
        "desc": "换穿高山冰爪，结组通过冰塔林与明暗冰裂缝"
      },
      {
        "id": "wp_xj14_4",
        "name": "哈达木孜达坂(3580m)",
        "lat": 42.385,
        "lon": 80.752,
        "ele": 3580,
        "desc": "南北天山最高分界达坂，古炮台遗址"
      },
      {
        "id": "wp_xj14_5",
        "name": "破城子营地(唐代古堡)",
        "lat": 42.125,
        "lon": 80.685,
        "ele": 2350,
        "desc": "南疆干燥峡谷碎石路，历史边关遗迹"
      },
      {
        "id": "wp_xj14_6",
        "name": "温宿县夏特柯尔克孜村",
        "lat": 41.852,
        "lon": 80.521,
        "ele": 1580,
        "desc": "出峡谷接阿克苏公路，完成穿越"
      }
    ]
  },
  {
    "id": "pub_xj_15",
    "title": "狼塔C+V高危极限重装徒步",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 195.0,
    "elevation_gain_m": 6800,
    "elevation_max_m": 4030,
    "estimated_duration": "9天8夜",
    "best_season": "8月中旬-9月中旬",
    "downloads_count": 420,
    "description": "国内公认最高难度“骨灰级”重装徒步线路。贯通天山中部未开发深山，翻越白杨沟达坂、库勒阿特达坂、蒙格特逊达坂等9座高海拔雪山达坂，横切无数悬崖绝壁与咆哮冰河。需极强野外生存自救能力，严禁独行，必须携带卫通设备与专业技术领队引导。",
    "waypoints": [
      {
        "id": "wp_xj15_1",
        "name": "呼图壁雀儿沟白杨沟煤矿",
        "lat": 43.852,
        "lon": 86.825,
        "ele": 1450,
        "desc": "狼塔C线传统起点，最后称重与装备排查"
      },
      {
        "id": "wp_xj15_2",
        "name": "白杨沟达坂垭口(3860m)",
        "lat": 43.612,
        "lon": 86.752,
        "ele": 3860,
        "desc": "雪坡攀升，下达坂为极碎滑石坡"
      },
      {
        "id": "wp_xj15_3",
        "name": "台勒德达坂与一棵树营地",
        "lat": 43.425,
        "lon": 86.685,
        "ele": 3680,
        "desc": "绝壁狭窄横切羊道，一失足成千古恨"
      },
      {
        "id": "wp_xj15_4",
        "name": "库勒阿特达坂垭口(3980m)",
        "lat": 43.285,
        "lon": 86.612,
        "ele": 3980,
        "desc": "狂风呼啸乱石如刀，注意防高反与滑坠"
      },
      {
        "id": "wp_xj15_5",
        "name": "狼塔核心夏热达坂(4030m)",
        "lat": 43.152,
        "lon": 86.521,
        "ele": 4030,
        "desc": "全线最高峰垭口，极度严寒，积雪盈尺"
      },
      {
        "id": "wp_xj15_6",
        "name": "哈尔嘎特郭勒大冰河",
        "lat": 42.985,
        "lon": 86.421,
        "ele": 2850,
        "desc": "河水冰刺入骨，必须合力结绳保护渡河"
      },
      {
        "id": "wp_xj15_7",
        "name": "巴伦台古仁郭勒出山口",
        "lat": 42.752,
        "lon": 86.254,
        "ele": 2100,
        "desc": "抵达南疆和静县境出山，终结史诗挑战"
      }
    ]
  },
  {
    "id": "pub_xj_16",
    "title": "喀纳斯·贾登峪-禾木-白哈巴徒步",
    "region": "xinjiang",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 2,
    "vehicle_req": "on_foot",
    "distance_km": 68.0,
    "elevation_gain_m": 1450,
    "elevation_max_m": 2350,
    "estimated_duration": "3天2夜",
    "best_season": "6月-7月花季, 9月中下旬金秋",
    "downloads_count": 1890,
    "description": "北疆童话阿尔泰山脉最治愈的景观徒步。自贾登峪出发，顺布尔津河谷至图瓦人禾木村看日出晨雾，经美丽峰越过黑湖高山草原抵中国西北第一村白哈巴。金秋白桦林金黄、木屋炊烟、繁星闪烁，难度适中、客栈成熟。",
    "waypoints": [
      {
        "id": "wp_xj16_1",
        "name": "贾登峪国家森林公园门票站",
        "lat": 48.512,
        "lon": 87.125,
        "ele": 1420,
        "desc": "轻装/重装出发，沿河谷步道慢行"
      },
      {
        "id": "wp_xj16_2",
        "name": "布尔津河与禾木河三角洲",
        "lat": 48.585,
        "lon": 87.254,
        "ele": 1280,
        "desc": "两条冰川河汇流处，桥头木屋午餐中继"
      },
      {
        "id": "wp_xj16_3",
        "name": "禾木图瓦人古村落观景台",
        "lat": 48.712,
        "lon": 87.425,
        "ele": 1150,
        "desc": "万亩白桦林环抱木屋，晨雾炊烟摄影圣地"
      },
      {
        "id": "wp_xj16_4",
        "name": "黑湖高山苔原海子(2350m)",
        "lat": 48.812,
        "lon": 87.215,
        "ele": 2350,
        "desc": "黑色深邃的高山融雪湖，蒙古包茶歇"
      },
      {
        "id": "wp_xj16_5",
        "name": "白哈巴中哈边境第一村",
        "lat": 48.685,
        "lon": 86.785,
        "ele": 1240,
        "desc": "边防界碑与中哈界河，乘景区巴士出山"
      }
    ]
  },
  {
    "id": "pub_xj_17",
    "title": "罗布泊大海道无人区雅丹硬派越野",
    "region": "xinjiang",
    "terrain": "gobi_gravel",
    "category": "thru",
    "difficulty": 5,
    "vehicle_req": "4x4_extreme",
    "distance_km": 385.0,
    "elevation_gain_m": 450,
    "elevation_max_m": 1280,
    "estimated_duration": "3天2夜",
    "best_season": "4-5月, 9-10月",
    "downloads_count": 1260,
    "description": "古丝绸之路最神秘残酷的荒漠走廊。穿越哈密戈壁、红柳滩、核心雅丹魔鬼城城堡、火星基地至鄯善迪坎尔村。全程无信号、无水源、地表布满刀片状锋利碎石与暗沟陷沙坑，必须配备双备胎、北斗卫星通讯终端、脱困千斤顶及双车以上编队结伴穿行。",
    "waypoints": [
      {
        "id": "wp_xj17_1",
        "name": "哈密五堡镇了墩集结点",
        "lat": 42.652,
        "lon": 92.852,
        "ele": 780,
        "desc": "最后水源加注，检查双备胎与卫星通信"
      },
      {
        "id": "wp_xj17_2",
        "name": "南湖黑戈壁锋利碎石带",
        "lat": 42.412,
        "lon": 92.421,
        "ele": 920,
        "desc": "刀片黑石减速慢行，严防高速爆胎"
      },
      {
        "id": "wp_xj17_3",
        "name": "大海道外星人城堡雅丹",
        "lat": 42.125,
        "lon": 91.895,
        "ele": 1050,
        "desc": "千万年风蚀巨型城堡雅丹，风势呼啸"
      },
      {
        "id": "wp_xj17_4",
        "name": "火星基地胶囊营地",
        "lat": 41.952,
        "lon": 91.521,
        "ele": 1120,
        "desc": "核心腹地扎营点，极度干燥备足饮用水"
      },
      {
        "id": "wp_xj17_5",
        "name": "神仙石与断崖迷宫",
        "lat": 41.825,
        "lon": 91.125,
        "ele": 1180,
        "desc": "雅丹迷宫易迷失航向，严格依托离线GPS航迹"
      },
      {
        "id": "wp_xj17_6",
        "name": "鄯善迪坎尔村接铺装路",
        "lat": 42.682,
        "lon": 89.852,
        "ele": 350,
        "desc": "抵达古村出荒漠，重回文明绿洲"
      }
    ]
  },
  {
    "id": "pub_xj_18",
    "title": "塔克拉玛干沙漠公路纵穿 (G216)",
    "region": "xinjiang",
    "terrain": "desert_dune",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 552.0,
    "elevation_gain_m": 180,
    "elevation_max_m": 1150,
    "estimated_duration": "1~2天",
    "best_season": "4月-11月(金秋胡杨季最佳)",
    "downloads_count": 1480,
    "description": "横跨“死亡之海”的世界级工程奇迹。由轮台出发跨越塔里木河胡杨林，一路向南直抵民丰县。全线被防沙芦苇方格与苦咸水滴灌红柳防护林包围。浩瀚起伏的沙海浩瀚无垠，需备足饮用水与检查空调滤芯防细沙进入。",
    "waypoints": [
      {
        "id": "wp_xj18_1",
        "name": "轮台沙漠公路零公里纪念碑",
        "lat": 41.785,
        "lon": 84.252,
        "ele": 940,
        "desc": "加满燃油，进入世界最长流动沙漠公路"
      },
      {
        "id": "wp_xj18_2",
        "name": "塔里木河大桥与原始胡杨",
        "lat": 41.215,
        "lon": 84.215,
        "ele": 920,
        "desc": "深秋万亩胡杨倒映塔里木河两岸"
      },
      {
        "id": "wp_xj18_3",
        "name": "肖塘水文监测水井房",
        "lat": 40.582,
        "lon": 84.112,
        "ele": 980,
        "desc": "沿线每4公里一座的护林滴灌水井房，可临时避暑"
      },
      {
        "id": "wp_xj18_4",
        "name": "塔中油田沙漠深处小镇",
        "lat": 38.985,
        "lon": 83.652,
        "ele": 1090,
        "desc": "沙漠正中心石油基地，有加油站与餐馆"
      },
      {
        "id": "wp_xj18_5",
        "name": "民丰县公路南端终点",
        "lat": 37.052,
        "lon": 82.685,
        "ele": 1410,
        "desc": "抵达南疆昆仑山北麓民丰，完成纵穿"
      }
    ]
  },
  {
    "id": "pub_xj_19",
    "title": "克里雅古道昆仑秘境越野探险",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "thru",
    "difficulty": 5,
    "vehicle_req": "4x4_extreme",
    "distance_km": 260.0,
    "elevation_gain_m": 3600,
    "elevation_max_m": 5450,
    "estimated_duration": "4天3夜",
    "best_season": "9月-10月(极短安全窗口期)",
    "downloads_count": 310,
    "description": "西藏阿里与南疆于田之间最凶险的昆仑天路。翻越火山群、硫磺达坂、阿特塔木达坂（5450m）与红柳滩。道路几乎全为高寒冻土融沉、碎石悬崖崩塌与冰川涉水冲沟，是国内越野探险的终极毕业路线之一。非顶配改装双锁重型四驱严禁涉足。",
    "waypoints": [
      {
        "id": "wp_xj19_1",
        "name": "于田县普鲁村最后补给点",
        "lat": 36.325,
        "lon": 81.652,
        "ele": 2680,
        "desc": "维吾尔族昆仑山古村，雇佣当地向导向昆仑进发"
      },
      {
        "id": "wp_xj19_2",
        "name": "阿拉马斯玉矿岔口",
        "lat": 36.012,
        "lon": 81.521,
        "ele": 3890,
        "desc": "和田玉采掘古矿道，悬崖极窄路段"
      },
      {
        "id": "wp_xj19_3",
        "name": "硫磺达坂地热温泉喷发区",
        "lat": 35.752,
        "lon": 81.385,
        "ele": 4680,
        "desc": "黄色硫磺结晶地貌，空气含硫气味刺鼻"
      },
      {
        "id": "wp_xj19_4",
        "name": "阿特塔木达坂(5450m)",
        "lat": 35.485,
        "lon": 81.215,
        "ele": 5450,
        "desc": "全线最高难关，严寒缺氧极度考验车辆发动机进气与冷却"
      },
      {
        "id": "wp_xj19_5",
        "name": "红柳滩G219新藏线接驳点",
        "lat": 35.852,
        "lon": 79.125,
        "ele": 4250,
        "desc": "驶入G219铺装公路，脱离极限险境"
      }
    ]
  },
  {
    "id": "pub_xj_20",
    "title": "孟克特古道天山秘境穿越",
    "region": "xinjiang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 72.0,
    "elevation_gain_m": 2100,
    "elevation_max_m": 3490,
    "estimated_duration": "3天2夜",
    "best_season": "6月-9月",
    "downloads_count": 780,
    "description": "古代西汉乌孙国通道。由独库公路K625处切入，翻越门克廷达坂（海拔3490m），穿过天山高山明珠门克廷湖、乌兰萨德克湖（天山魔湖），出唐布拉百里画廊。沿途有大片枯木堰塞湖、高山雪岭云杉与温泉泉眼。",
    "waypoints": [
      {
        "id": "wp_xj20_1",
        "name": "独库公路K625徒步起点",
        "lat": 44.025,
        "lon": 84.812,
        "ele": 1820,
        "desc": "过铁索吊桥入峡谷，沿奎屯河上溯"
      },
      {
        "id": "wp_xj20_2",
        "name": "天山魔湖(乌兰萨德克淖尔)",
        "lat": 43.912,
        "lon": 84.625,
        "ele": 2210,
        "desc": "枯死云杉直立湖中，水色碧绿宛如魔境"
      },
      {
        "id": "wp_xj20_3",
        "name": "门克廷达坂雪坡(3490m)",
        "lat": 43.785,
        "lon": 84.452,
        "ele": 3490,
        "desc": "常年积雪翻越点，注意碎石坡防滑"
      },
      {
        "id": "wp_xj20_4",
        "name": "温泉草滩营地",
        "lat": 43.682,
        "lon": 84.285,
        "ele": 2450,
        "desc": "天然硫磺热泉泡脚解乏，高山草甸宿营"
      },
      {
        "id": "wp_xj20_5",
        "name": "唐布拉草原小华山出山口",
        "lat": 43.612,
        "lon": 83.985,
        "ele": 1780,
        "desc": "接百里画廊柏油路，乘车前往尼勒克"
      }
    ]
  },
  {
    "id": "pub_xz_21",
    "title": "川藏南线 318 国道经典景观大道",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 3,
    "vehicle_req": "suv_standard",
    "distance_km": 1280.0,
    "elevation_gain_m": 8900,
    "elevation_max_m": 5130,
    "estimated_duration": "6~8天",
    "best_season": "4-5月, 9-10月",
    "downloads_count": 3450,
    "description": "中国人的景观大道天花板。自芒康入藏，翻越东达山（5130m）、业拉山（4658m），挑战怒江七十二拐天险，穿过然乌湖冰川群、波密通麦天险特大桥、鲁朗林海与林芝雅鲁藏布江，直抵日光城拉萨布达拉宫。全线柏油化良好但高海拔地质滑坡多发，需留意落石。",
    "waypoints": [
      {
        "id": "wp_xz21_1",
        "name": "金沙江大桥(川藏交界)",
        "lat": 29.752,
        "lon": 98.985,
        "ele": 2580,
        "desc": "正式进入西藏自治区辖境"
      },
      {
        "id": "wp_xz21_2",
        "name": "东达山垭口(5130m)",
        "lat": 29.685,
        "lon": 97.892,
        "ele": 5130,
        "desc": "318川藏段最高海拔垭口，常年大风降雪"
      },
      {
        "id": "wp_xz21_3",
        "name": "业拉山怒江七十二拐观景台",
        "lat": 30.125,
        "lon": 97.285,
        "ele": 4658,
        "desc": "大落差盘山公路，使用低档发动机制动防刹车过热"
      },
      {
        "id": "wp_xz21_4",
        "name": "然乌湖与米堆冰川",
        "lat": 29.521,
        "lon": 96.752,
        "ele": 3850,
        "desc": "冰川湖泊融水倒影，林芝门户"
      },
      {
        "id": "wp_xz21_5",
        "name": "波密通麦特大桥",
        "lat": 30.085,
        "lon": 95.125,
        "ele": 2080,
        "desc": "昔日通麦天险排龙天险如今一桥飞架"
      },
      {
        "id": "wp_xz21_6",
        "name": "色季拉山南迦巴瓦观景台",
        "lat": 29.652,
        "lon": 94.621,
        "ele": 4728,
        "desc": "十人九不遇的中国最美雪山南迦巴瓦峰"
      },
      {
        "id": "wp_xz21_7",
        "name": "米拉山隧道(4752m)",
        "lat": 29.852,
        "lon": 92.385,
        "ele": 4752,
        "desc": "高海拔特长隧道，林芝与拉萨分水岭"
      },
      {
        "id": "wp_xz21_8",
        "name": "拉萨布达拉宫广场",
        "lat": 29.658,
        "lon": 91.118,
        "ele": 3650,
        "desc": "圣城拉萨终点，圆梦朝圣之旅"
      }
    ]
  },
  {
    "id": "pub_xz_22",
    "title": "川藏北线 317 国道人文探秘之路",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 4,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 1450.0,
    "elevation_gain_m": 9200,
    "elevation_max_m": 5050,
    "estimated_duration": "7~9天",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 1250,
    "description": "相比318更原始苍凉、宗教人文积淀更深厚的藏地秘境。由四川德格印经院入藏，经江达、昌都强巴林寺、类乌齐查杰玛大殿、丁青孜珠寺（悬崖苯教神庙）、巴青、索县赞丹寺抵那曲大草原，最终并入青藏公路抵拉萨。高海拔非铺装多，暗冰与坑洼频繁。",
    "waypoints": [
      {
        "id": "wp_xz22_1",
        "name": "德格印经院(甘孜西大门)",
        "lat": 31.812,
        "lon": 98.582,
        "ele": 3280,
        "desc": "藏文化大百科全书，木雕刻经板宝库"
      },
      {
        "id": "wp_xz22_2",
        "name": "矮拉山特长隧道(川藏界)",
        "lat": 31.685,
        "lon": 98.254,
        "ele": 3950,
        "desc": "穿越分水岭正式进入西藏江达县"
      },
      {
        "id": "wp_xz22_3",
        "name": "昌都强巴林寺与两江汇流",
        "lat": 31.145,
        "lon": 97.185,
        "ele": 3240,
        "desc": "昂曲与扎曲汇流为澜沧江，康区格鲁派第一大寺"
      },
      {
        "id": "wp_xz22_4",
        "name": "类乌齐查杰玛大殿",
        "lat": 31.215,
        "lon": 96.612,
        "ele": 3780,
        "desc": "红白黑三色条纹建筑奇迹，达隆噶举派名刹"
      },
      {
        "id": "wp_xz22_5",
        "name": "丁青孜珠寺(悬崖苯教神庙)",
        "lat": 31.425,
        "lon": 95.582,
        "ele": 4850,
        "desc": "海拔4850米怪石嶙峋鹰巢古寺，天险盘山土路"
      },
      {
        "id": "wp_xz22_6",
        "name": "索县赞丹寺(小布达拉宫)",
        "lat": 31.885,
        "lon": 93.785,
        "ele": 4010,
        "desc": "依山而建雄伟气魄，进入藏北牧区"
      },
      {
        "id": "wp_xj22_7",
        "name": "那曲草原接G109国道",
        "lat": 31.472,
        "lon": 92.052,
        "ele": 4500,
        "desc": "并入青藏公路南下直抵拉萨"
      }
    ]
  },
  {
    "id": "pub_xz_23",
    "title": "新藏线 G219 世界最高海拔公路",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "thru",
    "difficulty": 5,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 2140.0,
    "elevation_gain_m": 14200,
    "elevation_max_m": 5378,
    "estimated_duration": "7~10天",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 1120,
    "description": "“行者之巅，生死新藏”。从新疆叶城零公里石碑启程，横跨昆仑山脉、喀喇昆仑山脉与冈底斯山脉，翻越库地达坂、麻扎达坂、界山达坂（5347m）、红土达坂（5378m），穿经死人沟（泉水沟极度缺氧区），沿班公错抵阿里日土、狮泉河直至拉孜。平均海拔超4500米，对人车抗高原极限考验极大。",
    "waypoints": [
      {
        "id": "wp_xz23_1",
        "name": "叶城零公里石碑",
        "lat": 37.885,
        "lon": 77.412,
        "ele": 1365,
        "desc": "检查边防证、车辆机油防冻液，出发誓师"
      },
      {
        "id": "wp_xz23_2",
        "name": "麻扎达坂连续回头弯",
        "lat": 36.582,
        "lon": 77.012,
        "ele": 4969,
        "desc": "碎石寸草不生黑山峡谷，长下坡发动机制动"
      },
      {
        "id": "wp_xj23_3",
        "name": "三十里营房驻地",
        "lat": 36.352,
        "lon": 78.025,
        "ele": 3780,
        "desc": "新藏线中途唯一正规医疗兵站补给点"
      },
      {
        "id": "wp_xz23_4",
        "name": "死人沟(泉水沟高危缺氧区)",
        "lat": 35.215,
        "lon": 79.552,
        "ele": 5120,
        "desc": "极度低压缺氧高寒，禁止剧烈运动，非必要不停留"
      },
      {
        "id": "wp_xz23_5",
        "name": "界山达坂(新疆西藏交界5347m)",
        "lat": 34.985,
        "lon": 80.125,
        "ele": 5347,
        "desc": "新藏公路最高纪念碑垭口，正式入藏"
      },
      {
        "id": "wp_xz23_6",
        "name": "班公错中印界湖",
        "lat": 33.452,
        "lon": 79.712,
        "ele": 4240,
        "desc": "东淡西咸奇特狭长高原湖泊，水鸟栖息"
      },
      {
        "id": "wp_xz23_7",
        "name": "日土宗古堡与岩画",
        "lat": 33.225,
        "lon": 79.685,
        "ele": 4280,
        "desc": "阿里高原第一重镇，山顶石城遗迹"
      },
      {
        "id": "wp_xz23_8",
        "name": "拉孜G318线5000公里处",
        "lat": 29.085,
        "lon": 87.652,
        "ele": 4010,
        "desc": "新藏线终点接G318国道返回拉萨"
      }
    ]
  },
  {
    "id": "pub_xz_24",
    "title": "阿里大北线荒原越野 (一错再错)",
    "region": "xizang",
    "terrain": "plateau_grassland",
    "category": "thru",
    "difficulty": 5,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 2420.0,
    "elevation_gain_m": 12500,
    "elevation_max_m": 5360,
    "estimated_duration": "10~12天",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 1540,
    "description": "无阿里，不西藏；无大北，不荒原。深入藏北羌塘国家级自然保护区边缘，拥抱野生藏羚羊、野牦牛与藏野驴。途经圣湖玛旁雍错、神山冈仁波齐、狮泉河、仁多、错勤、扎日南木错、当惹雍错（古象雄文明腹地）、色林错、班戈直至纳木错。路况涵盖数百公里搓板碎石非铺装路，需严控补给燃油。",
    "waypoints": [
      {
        "id": "wp_xz24_1",
        "name": "拉萨布宫出发",
        "lat": 29.658,
        "lon": 91.118,
        "ele": 3650,
        "desc": "检查全车胎压与高反救援应急物资"
      },
      {
        "id": "wp_xz24_2",
        "name": "神山冈仁波齐塔钦",
        "lat": 31.025,
        "lon": 81.285,
        "ele": 4680,
        "desc": "四大宗教宇宙中心，玛旁雍错圣湖守望"
      },
      {
        "id": "wp_xz24_3",
        "name": "札达土林与古格遗址",
        "lat": 31.485,
        "lon": 79.852,
        "ele": 3750,
        "desc": "百万年地壳隆起峡谷古城堡遗迹"
      },
      {
        "id": "wp_xz24_4",
        "name": "狮泉河镇(阿里行署)",
        "lat": 32.502,
        "lon": 80.105,
        "ele": 4280,
        "desc": "大北线起点补给站，加满所有备用油桶"
      },
      {
        "id": "wp_xz24_5",
        "name": "仁多乡高原搓板路",
        "lat": 31.952,
        "lon": 83.421,
        "ele": 4820,
        "desc": "正式进入一错再错无人荒原，无手机网络"
      },
      {
        "id": "wp_xz24_6",
        "name": "当惹雍错·文布南村",
        "lat": 31.052,
        "lon": 86.582,
        "ele": 4580,
        "desc": "笨教最大圣湖，古象雄文明遗址，湖畔石屋"
      },
      {
        "id": "wp_xz24_7",
        "name": "色林错(西藏第一大湖)",
        "lat": 31.852,
        "lon": 88.985,
        "ele": 4540,
        "desc": "浩瀚魔鬼湖，藏羚羊种群穿行"
      },
      {
        "id": "wp_xz24_8",
        "name": "当雄县返回拉萨闭环",
        "lat": 30.485,
        "lon": 91.105,
        "ele": 4280,
        "desc": "并入G109京藏高速，完成大北线闭环"
      }
    ]
  },
  {
    "id": "pub_xz_25",
    "title": "冈仁波齐神山高海拔转山路书",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 52.0,
    "elevation_gain_m": 1580,
    "elevation_max_m": 5648,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月",
    "downloads_count": 2150,
    "description": "藏传佛教、印度教、苯教共同尊奉的“神山之王”。从塔钦出发，顺时针环绕冈仁波齐峰。首日由塔钦徒步至止热寺，近距离凝望神山北壁日照金山；次日翻越全程最高险阻“卓玛拉达坂”（海拔5648米），经过慈悲湖（托吉错）下至祖楚寺返程。需极强抗高反体能与防风保暖装备。",
    "waypoints": [
      {
        "id": "wp_xz25_1",
        "name": "塔钦小镇转山起点",
        "lat": 30.985,
        "lon": 81.285,
        "ele": 4680,
        "desc": "清晨出发，登山杖、高能量路粮齐备"
      },
      {
        "id": "wp_xz25_2",
        "name": "经幡广场(双腿佛塔)",
        "lat": 31.025,
        "lon": 81.252,
        "ele": 4780,
        "desc": "仰望神山南壁，虔诚藏民朝圣叩长头起点"
      },
      {
        "id": "wp_xz25_3",
        "name": "止热寺(神山北壁正对点)",
        "lat": 31.115,
        "lon": 81.295,
        "ele": 5080,
        "desc": "首夜宿营客栈，神山北壁金字塔壮美日照金山"
      },
      {
        "id": "wp_xz25_4",
        "name": "卓玛拉达坂最高点(5648m)",
        "lat": 31.139,
        "lon": 81.348,
        "ele": 5648,
        "desc": "挂经幡撒隆达祈福，不可长时间停留防严重失温"
      },
      {
        "id": "wp_xz25_5",
        "name": "慈悲湖(托吉错绿翡翠)",
        "lat": 31.135,
        "lon": 81.355,
        "ele": 5580,
        "desc": "达坂下方万年冰川高山湖泊，急陡碎石下坡防滑"
      },
      {
        "id": "wp_xz25_6",
        "name": "塔钦终点圆满",
        "lat": 30.985,
        "lon": 81.285,
        "ele": 4680,
        "desc": "完成52公里神山洗礼，功德圆满"
      }
    ]
  },
  {
    "id": "pub_xz_26",
    "title": "珠峰东坡·嘎玛沟世界顶级徒步",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 85.0,
    "elevation_gain_m": 4200,
    "elevation_max_m": 5350,
    "estimated_duration": "7天6夜",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 780,
    "description": "美国《国家地理》评选的“世界十大顶级徒步路线”之一。置身喜马拉雅腹地原始森林与冰川峡谷，同时面对珠穆朗玛峰（8848m）、洛子峰（8516m）、马卡鲁峰（8463m）三座八千米级巨峰东壁冰川。需翻越海拔5350米的朗玛拉达坂，全程雇佣牦牛工驮运物资。",
    "waypoints": [
      {
        "id": "wp_xz26_1",
        "name": "定日县曲当乡优帕村",
        "lat": 28.012,
        "lon": 87.285,
        "ele": 3750,
        "desc": "徒步起点，办理边防与牦牛队接洽"
      },
      {
        "id": "wp_xz26_2",
        "name": "晓乌措冰川湖营地",
        "lat": 28.052,
        "lon": 87.185,
        "ele": 4650,
        "desc": "高山碧蓝海子扎营，倒映马卡鲁雪山"
      },
      {
        "id": "wp_xz26_3",
        "name": "晓乌拉达坂(4900m)",
        "lat": 28.085,
        "lon": 28.085,
        "ele": 4900,
        "desc": "进入嘎玛沟原始峡谷杜鹃林分界点"
      },
      {
        "id": "wp_xz26_4",
        "name": "汤湘高山观景台营地",
        "lat": 28.125,
        "lon": 87.052,
        "ele": 4050,
        "desc": "正对嘎玛沟谷地与洛子峰冰川瀑布"
      },
      {
        "id": "wp_xz26_5",
        "name": "白当营地(珠峰东坡正对点)",
        "lat": 28.015,
        "lon": 86.952,
        "ele": 4950,
        "desc": "近距离仰望世界最高峰巨型冰壁震撼景致"
      },
      {
        "id": "wp_xz26_6",
        "name": "朗玛拉达坂最高峰(5350m)",
        "lat": 28.152,
        "lon": 87.185,
        "ele": 5350,
        "desc": "全线最险峻垭口，冰雪与巨石混合路段"
      },
      {
        "id": "wp_xz26_7",
        "name": "轮朱林村出山终点",
        "lat": 28.085,
        "lon": 87.325,
        "ele": 3950,
        "desc": "乘车返回日喀则，完成世界屋脊漫步"
      }
    ]
  },
  {
    "id": "pub_xz_27",
    "title": "库拉岗日神山三神湖经典徒步",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 38.0,
    "elevation_gain_m": 1650,
    "elevation_max_m": 4850,
    "estimated_duration": "3天2夜",
    "best_season": "5月-10月",
    "downloads_count": 1160,
    "description": "山南洛扎县境内的秘境雪山湖泊天堂。仰望海拔7538米的藏南第一神山库拉岗日，探访如宝石般镶嵌在雪峰下的白玛林错、折公措、介久措三座圣湖。路况多高山碎石山道与草甸步道，风景纯美，游客相对较少。",
    "waypoints": [
      {
        "id": "wp_xz27_1",
        "name": "洛扎县色乡错玉村起点",
        "lat": 28.285,
        "lon": 90.852,
        "ele": 4120,
        "desc": "进山前在藏民家安顿，租用当地向导"
      },
      {
        "id": "wp_xz27_2",
        "name": "白玛林错观景台",
        "lat": 28.215,
        "lon": 90.785,
        "ele": 4550,
        "desc": "蓝绿相间圣湖，传闻能看到前世今生的圣湖"
      },
      {
        "id": "wp_xz27_3",
        "name": "折公三措分水岭",
        "lat": 28.185,
        "lon": 90.752,
        "ele": 4850,
        "desc": "三个阶梯状湖泊连成一串，雪山倒影"
      },
      {
        "id": "wp_xz27_4",
        "name": "介久措与库拉岗日主峰冰川",
        "lat": 28.152,
        "lon": 90.712,
        "ele": 4700,
        "desc": "翡翠绿色湖水，正面迎接库拉岗日七千米冰壁"
      },
      {
        "id": "wp_xz27_5",
        "name": "错玉村终点",
        "lat": 28.285,
        "lon": 90.852,
        "ele": 4120,
        "desc": "返回村庄，乘车前往洛扎县城"
      }
    ]
  },
  {
    "id": "pub_xz_28",
    "title": "丙察察“魔鬼越野进藏路”",
    "region": "xizang",
    "terrain": "canyon_gorge",
    "category": "offroad",
    "difficulty": 5,
    "vehicle_req": "4x4_extreme",
    "distance_km": 286.0,
    "elevation_gain_m": 4200,
    "elevation_max_m": 4720,
    "estimated_duration": "2~3天",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 1680,
    "description": "昔日“最艰险的进藏越野公路”。自云南怒江贡山丙中洛出发，经过秋那桶进入西藏察瓦龙，挑战令人闻风丧胆的“大流沙”（落石如瀑布）、滚石坡，再翻越齐马拉达坂（4630m）、昌拉达坂直达察隅。沿途峡谷悬崖深达数百米，必须硬派四驱车辆并随时提防高空坠石。",
    "waypoints": [
      {
        "id": "wp_xz28_1",
        "name": "丙中洛人神共居之乡",
        "lat": 28.012,
        "lon": 98.595,
        "ele": 1750,
        "desc": "怒江第一湾观景，出发前检查底盘护板"
      },
      {
        "id": "wp_xz28_2",
        "name": "秋那桶峡谷滇藏界碑",
        "lat": 28.185,
        "lon": 98.572,
        "ele": 1820,
        "desc": "进入西藏自治区林芝察隅县境"
      },
      {
        "id": "wp_xz28_3",
        "name": "大流沙天险(生死关卡)",
        "lat": 28.325,
        "lon": 98.485,
        "ele": 1950,
        "desc": "巨型碎石滑坡带，观察山顶动静，一脚油门快速通过切勿鸣笛"
      },
      {
        "id": "wp_xz28_4",
        "name": "察瓦龙镇怒江干热河谷",
        "lat": 28.452,
        "lon": 98.452,
        "ele": 1980,
        "desc": "仙人掌遍野的干热小镇，首晚宿营加汽油"
      },
      {
        "id": "wp_xz28_5",
        "name": "甲应村神山隐秘岔口",
        "lat": 28.582,
        "lon": 98.352,
        "ele": 3200,
        "desc": "梅里雪山西坡绝壁古村分道口"
      },
      {
        "id": "wp_xz28_6",
        "name": "雄楚拉达坂垭口(4630m)",
        "lat": 28.652,
        "lon": 98.152,
        "ele": 4630,
        "desc": "高山原始红杉冷杉林，气温骤降"
      },
      {
        "id": "wp_xz28_7",
        "name": "目若村高山牧场",
        "lat": 28.521,
        "lon": 97.852,
        "ele": 3720,
        "desc": "黑青稞与藏香猪成群，纯净原始"
      },
      {
        "id": "wp_xz28_8",
        "name": "察隅县城水乡终点",
        "lat": 28.658,
        "lon": 97.462,
        "ele": 2350,
        "desc": "西藏江南察隅，连接省道完成传奇越野"
      }
    ]
  },
  {
    "id": "pub_xz_29",
    "title": "山南藏文化发祥地深度大环线",
    "region": "xizang",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 850.0,
    "elevation_gain_m": 4800,
    "elevation_max_m": 5070,
    "estimated_duration": "4天3夜",
    "best_season": "4-10月",
    "downloads_count": 1050,
    "description": "探索藏民族摇篮与早期文明源头。从拉萨出发，翻越岗巴拉山俯瞰羊卓雍错珊瑚碧玉蓝，抵普莫雍错看“天空之泪”与库拉岗日，穿过洛扎碉楼群、乃东雍布拉康（西藏第一座宫殿）、桑耶寺（西藏第一座佛法僧俱全寺院）返回拉萨。",
    "waypoints": [
      {
        "id": "wp_xz29_1",
        "name": "拉萨滨河大道出发",
        "lat": 29.658,
        "lon": 91.118,
        "ele": 3650,
        "desc": "出城沿雅鲁藏布江一路向南"
      },
      {
        "id": "wp_xz29_2",
        "name": "岗巴拉山垭口(羊卓雍错)",
        "lat": 29.185,
        "lon": 90.625,
        "ele": 4998,
        "desc": "俯瞰羊湖蜿蜒深蓝湖水与宁金抗沙峰"
      },
      {
        "id": "wp_xz29_3",
        "name": "普莫雍错推村(海拔5010m)",
        "lat": 28.521,
        "lon": 90.452,
        "ele": 5010,
        "desc": "世界海拔最高行政村，冬季蓝冰羊群转场"
      },
      {
        "id": "wp_xz29_4",
        "name": "洛扎藏东石碉楼群",
        "lat": 28.385,
        "lon": 90.852,
        "ele": 3820,
        "desc": "悬崖绝壁防御性千年古碉楼群"
      },
      {
        "id": "wp_xz29_5",
        "name": "雍布拉康(西藏第一宫殿)",
        "lat": 29.152,
        "lon": 91.785,
        "ele": 3700,
        "desc": "雅砻河谷耸立石崖古堡，藏王聂赤赞普行宫"
      },
      {
        "id": "wp_xz29_6",
        "name": "桑耶寺(坛城宇宙构型)",
        "lat": 29.325,
        "lon": 91.512,
        "ele": 3620,
        "desc": "莲花生大师亲自主持修建，藏汉印三合一风格"
      },
      {
        "id": "wp_xz29_7",
        "name": "拉萨贡嘎大桥闭环",
        "lat": 29.285,
        "lon": 90.952,
        "ele": 3580,
        "desc": "返回拉萨市区完成山南文明大环线"
      }
    ]
  },
  {
    "id": "pub_xz_30",
    "title": "阿里中线无人区穿越 (大北线精华)",
    "region": "xizang",
    "terrain": "plateau_grassland",
    "category": "thru",
    "difficulty": 5,
    "vehicle_req": "4x4_extreme",
    "distance_km": 980.0,
    "elevation_gain_m": 5200,
    "elevation_max_m": 5150,
    "estimated_duration": "5天4夜",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 580,
    "description": "介于阿里南线与大北线之间的极野探索通道。深入无路之境的羌塘荒原，自改则向南穿越洞错、达瓦错、扎布耶茶卡（世界三大锂盐湖之一的粉红色盐湖）、塔若错直至措勤。必须备足备用燃油（中途超500公里无正规加油站）、强光射灯与卫星通信。",
    "waypoints": [
      {
        "id": "wp_xz30_1",
        "name": "改则县城最后加油站",
        "lat": 32.302,
        "lon": 84.065,
        "ele": 4500,
        "desc": "加满全车与备用油桶，检查双备胎"
      },
      {
        "id": "wp_xz30_2",
        "name": "洞错高原咸水湖畔",
        "lat": 32.215,
        "lon": 84.452,
        "ele": 4480,
        "desc": "湖畔天然土路，藏野驴群在此奔跑"
      },
      {
        "id": "wp_xz30_3",
        "name": "达瓦错月亮之湖",
        "lat": 31.252,
        "lon": 84.952,
        "ele": 4650,
        "desc": "宛如一弯新月的蓝色湖泊，无信号区"
      },
      {
        "id": "wp_xz30_4",
        "name": "扎布耶茶卡(粉红锂盐湖)",
        "lat": 31.352,
        "lon": 84.152,
        "ele": 4420,
        "desc": "世界第三大锂盐湖，卤水结晶呈现神奇粉红色"
      },
      {
        "id": "wp_xz30_5",
        "name": "塔若错与布嘎寺",
        "lat": 31.125,
        "lon": 83.985,
        "ele": 4560,
        "desc": "沿湖沙石路，水鸟聚集地"
      },
      {
        "id": "wp_xz30_6",
        "name": "措勤县城重回铺装路",
        "lat": 31.025,
        "lon": 85.152,
        "ele": 4700,
        "desc": "完成阿里中线纯野路穿行"
      }
    ]
  },
  {
    "id": "pub_xz_31",
    "title": "希夏邦马峰南坡大本营徒步",
    "region": "xizang",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 42.0,
    "elevation_gain_m": 1850,
    "elevation_max_m": 4350,
    "estimated_duration": "2天1夜",
    "best_season": "5月-10月",
    "downloads_count": 850,
    "description": "探访唯一一座完全在中国境内的八千米级极高峰（8027m）。从吉隆县宗嘎镇向乃村进发，俯瞰佩枯措湛蓝湖水，近观希峰南坡巨大的现代悬冰川与冰塔林。视野极度开阔，高原草甸上藏原羚跳跃。",
    "waypoints": [
      {
        "id": "wp_xz31_1",
        "name": "佩枯措湖畔营地",
        "lat": 28.612,
        "lon": 85.852,
        "ele": 4590,
        "desc": "佩枯措与希夏邦马雪山倒影起点"
      },
      {
        "id": "wp_xz31_2",
        "name": "乃村高山观景台",
        "lat": 28.452,
        "lon": 85.325,
        "ele": 4150,
        "desc": "吉隆沟云海与雪山全景天然观礼台"
      },
      {
        "id": "wp_xj31_3",
        "name": "希峰南坡冰川末端",
        "lat": 28.325,
        "lon": 85.785,
        "ele": 4350,
        "desc": "巨大的冰碛物堆积垄，仰视8027m雪山主峰"
      },
      {
        "id": "wp_xz31_4",
        "name": "吉隆沟口口岸通道",
        "lat": 28.285,
        "lon": 85.252,
        "ele": 2800,
        "desc": "返回中尼边境吉隆口岸，完成徒步"
      }
    ]
  },
  {
    "id": "pub_xz_32",
    "title": "滇藏线 G214 穿越梅里与盐井",
    "region": "xizang",
    "terrain": "canyon_gorge",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 430.0,
    "elevation_gain_m": 3100,
    "elevation_max_m": 4292,
    "estimated_duration": "2~3天",
    "best_season": "4-6月, 9-11月",
    "downloads_count": 2200,
    "description": "彩云之南入藏的茶马古道经典脉络。由香格里拉独克宗古城出发，经奔子栏金沙江大拐弯、翻越白马雪山垭口（4292m），朝拜梅里雪山卡瓦格博峰日照金山，进入西藏芒康盐井（品尝千年古盐田与加加面），在芒康汇入318国道。",
    "waypoints": [
      {
        "id": "wp_xz32_1",
        "name": "香格里拉独克宗月光城",
        "lat": 27.812,
        "lon": 99.712,
        "ele": 3280,
        "desc": "世界最大转经筒，滇藏自驾始发站"
      },
      {
        "id": "wp_xz32_2",
        "name": "金沙江大拐弯(月亮湾)",
        "lat": 28.254,
        "lon": 99.312,
        "ele": 2180,
        "desc": "Ω形巨型河湾，干热河谷地貌"
      },
      {
        "id": "wp_xz32_3",
        "name": "白马雪山老路垭口(4292m)",
        "lat": 28.352,
        "lon": 99.012,
        "ele": 4292,
        "desc": "高山杜鹃林与流石滩，远眺白马雪山U型冰川谷"
      },
      {
        "id": "wp_xz32_4",
        "name": "德钦飞来寺观景台",
        "lat": 28.452,
        "lon": 98.885,
        "ele": 3450,
        "desc": "朝圣梅里雪山十三峰日照金山第一圣地"
      },
      {
        "id": "wp_xz32_5",
        "name": "西藏芒康千年古盐田",
        "lat": 29.025,
        "lon": 98.612,
        "ele": 2350,
        "desc": "澜沧江畔层叠木质晒盐架，品尝特色加加面"
      },
      {
        "id": "wp_xz32_6",
        "name": "芒康县城接G318国道",
        "lat": 29.685,
        "lon": 98.595,
        "ele": 3880,
        "desc": "滇藏线与川藏南线交汇点"
      }
    ]
  },
  {
    "id": "pub_cx_33",
    "title": "洛克之路 (扎尕那-迭部-若尔盖)",
    "region": "chuanxi",
    "terrain": "forest_mountain",
    "category": "overland",
    "difficulty": 3,
    "vehicle_req": "at_tire",
    "distance_km": 115.0,
    "elevation_gain_m": 1250,
    "elevation_max_m": 3950,
    "estimated_duration": "1天",
    "best_season": "5-10月",
    "downloads_count": 1420,
    "description": "追寻探险家约瑟夫·洛克的足迹。穿越甘南迭部扎尕那巨石城堡，翻越光盖山垭口（海拔3950米），跨越白龙江发源地峡谷直达若尔盖草原。沿途尽是石灰岩巨壁、高山流石滩、暗针叶林与高山草甸，被越野探险界公认为“中国最壮丽的峡谷天路”。",
    "waypoints": [
      {
        "id": "wp_cx33_1",
        "name": "扎尕那东哇村石城起点",
        "lat": 34.248,
        "lon": 103.215,
        "ele": 2980,
        "desc": "清晨观云雾石城仙境，检查四驱与胎压"
      },
      {
        "id": "wp_cx33_2",
        "name": "老虎嘴峡谷崖壁公路",
        "lat": 34.285,
        "lon": 103.185,
        "ele": 3420,
        "desc": "悬崖峭壁擦肩而过，注意弯道盲区与会车鸣笛"
      },
      {
        "id": "wp_cx33_3",
        "name": "光盖山分水岭垭口(3950m)",
        "lat": 34.325,
        "lon": 103.152,
        "ele": 3950,
        "desc": "洛克之路最高峰，眺望层峦石海与迭山主峰"
      },
      {
        "id": "wp_cx33_4",
        "name": "贡巴寺高山牧区",
        "lat": 34.385,
        "lon": 103.085,
        "ele": 3480,
        "desc": "下行至峡谷牧区，夏季野花漫山"
      },
      {
        "id": "wp_cx33_5",
        "name": "卓尼大峪沟公路岔口",
        "lat": 34.452,
        "lon": 103.025,
        "ele": 2850,
        "desc": "汇入国道完成洛克之路穿越"
      }
    ]
  },
  {
    "id": "pub_cx_34",
    "title": "格涅神山大环线越野穿越",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "offroad",
    "difficulty": 4,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 235.0,
    "elevation_gain_m": 2850,
    "elevation_max_m": 4820,
    "estimated_duration": "2~3天",
    "best_season": "6-10月",
    "downloads_count": 980,
    "description": "川西深处最后的越野净土。自理塘毛垭大草原切入，环抱格涅神山雪峰（6204m）。打卡大地明眸“格涅之眼”、依崖而建的冷古寺老庙、热梯大峡谷温泉与波密乡。路况多碎石炮弹坑、冲沟与泥浆漫水路，必须四驱硬派SUV并携带备胎。",
    "waypoints": [
      {
        "id": "wp_cx34_1",
        "name": "理塘毛垭大草原西入口",
        "lat": 30.052,
        "lon": 100.125,
        "ele": 4010,
        "desc": "从G318切入格涅南线砂石路"
      },
      {
        "id": "wp_cx34_2",
        "name": "铁匠山古冰帽垭口(4770m)",
        "lat": 29.952,
        "lon": 99.852,
        "ele": 4770,
        "desc": "怪石嶙峋古冰帽遗迹，远眺格涅群峰"
      },
      {
        "id": "wp_cx34_3",
        "name": "格涅之眼(水塘奇观)",
        "lat": 29.825,
        "lon": 99.652,
        "ele": 4150,
        "desc": "圆形水草湿地宛如大地之眸，倒映雪山金顶"
      },
      {
        "id": "wp_cx34_4",
        "name": "老冷古寺肖扎神山下",
        "lat": 29.712,
        "lon": 99.512,
        "ele": 4120,
        "desc": "藏传佛教噶玛噶举派著名古寺，三件圣物"
      },
      {
        "id": "wp_cx34_5",
        "name": "热梯河谷草甸碎石滩",
        "lat": 29.652,
        "lon": 99.385,
        "ele": 4350,
        "desc": "碎石河滩极易刮底盘，严格缓行"
      },
      {
        "id": "wp_cx34_6",
        "name": "劳者龙巴垭口(4820m)",
        "lat": 29.782,
        "lon": 99.215,
        "ele": 4820,
        "desc": "格涅环线最高达坂，风雪高发地带"
      },
      {
        "id": "wp_cx34_7",
        "name": "巴塘县城接G318国道",
        "lat": 30.005,
        "lon": 99.105,
        "ele": 2580,
        "desc": "出峡谷完成格涅大环线越野"
      }
    ]
  },
  {
    "id": "pub_cx_35",
    "title": "贡嘎雪山全线重装大环线徒步",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 76.5,
    "elevation_gain_m": 3100,
    "elevation_max_m": 4920,
    "estimated_duration": "4天3夜",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 1380,
    "description": "朝圣“蜀山之王”（7556米）的殿堂级重装徒步路线。由康定老榆林电站出发，穿过格西草原、两岔河，翻越海拔4920米冰雪覆盖的日乌且达坂，经莫溪沟谷地抵达六百年历史的贡嘎寺，最后翻越子梅垭口眺望贡嘎群峰云海。需准备高海拔抗低温零下防寒装备。",
    "waypoints": [
      {
        "id": "wp_cx35_1",
        "name": "老榆林水库电站起点",
        "lat": 29.985,
        "lon": 101.952,
        "ele": 2880,
        "desc": "向导挑夫汇合，检查冰爪防风软壳"
      },
      {
        "id": "wp_cx35_2",
        "name": "格西草原营地",
        "lat": 29.895,
        "lon": 101.885,
        "ele": 3400,
        "desc": "高山草甸开阔地，首晚适应海拔扎营"
      },
      {
        "id": "wp_cx35_3",
        "name": "上日乌且冰川营地",
        "lat": 29.785,
        "lon": 101.812,
        "ele": 4350,
        "desc": "雪山冰川脚下，气温直逼冰点"
      },
      {
        "id": "wp_cx35_4",
        "name": "日乌且达坂垭口(4920m)",
        "lat": 29.742,
        "lon": 101.785,
        "ele": 4920,
        "desc": "全线最高难关，碎石巨石坡，注意滑坠"
      },
      {
        "id": "wp_cx35_5",
        "name": "贡嘎寺(主峰正对朝拜点)",
        "lat": 29.612,
        "lon": 101.785,
        "ele": 3750,
        "desc": "面对贡嘎主峰冰川，藏传佛教古寺"
      },
      {
        "id": "wp_cx35_6",
        "name": "子梅垭口云海观景台",
        "lat": 29.582,
        "lon": 101.745,
        "ele": 4550,
        "desc": "贡嘎主峰云海日落最佳摄影平台"
      },
      {
        "id": "wp_cx35_7",
        "name": "上木居村乘车出山",
        "lat": 29.521,
        "lon": 101.685,
        "ele": 3720,
        "desc": "徒步终点，乘车前往康定返程"
      }
    ]
  },
  {
    "id": "pub_cx_36",
    "title": "四姑娘山长坪沟-毕棚沟“长毕穿越”",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 36.0,
    "elevation_gain_m": 1550,
    "elevation_max_m": 4668,
    "estimated_duration": "2天1夜",
    "best_season": "5月-10月",
    "downloads_count": 2100,
    "description": "川西最经典的高山徒步跨越线。从四姑娘山长坪沟喇嘛寺出发，沿着原始森林峡谷经木骡子、叉子沟营地，凌晨冲顶翻越海拔4668米的毕棚沟垭口，下行进入阿坝理县毕棚沟三棵树红石滩出山。需备好雪套、高帮防水徒步鞋与简易冰爪。",
    "waypoints": [
      {
        "id": "wp_cx36_1",
        "name": "长坪沟景区喇嘛寺栈道起点",
        "lat": 30.985,
        "lon": 102.885,
        "ele": 3400,
        "desc": "四姑娘山传统栈道步入森林碎石道"
      },
      {
        "id": "wp_cx36_2",
        "name": "枯树滩与木骡子高山大草甸",
        "lat": 31.052,
        "lon": 102.852,
        "ele": 3760,
        "desc": "仰望婆缪峰、幺妹峰后侧冰壁，绝佳露营地"
      },
      {
        "id": "wp_cx36_3",
        "name": "叉子沟尾营地(海拔3900m)",
        "lat": 31.125,
        "lon": 102.812,
        "ele": 3900,
        "desc": "凌晨3点拔营冲顶准备，补充高能热食"
      },
      {
        "id": "wp_cx36_4",
        "name": "长毕达坂垭口(4668m)",
        "lat": 31.185,
        "lon": 102.785,
        "ele": 4668,
        "desc": "风口极冷，翻过垭口即进入阿坝理县"
      },
      {
        "id": "wp_cx36_5",
        "name": "毕棚沟三棵树红石滩出口",
        "lat": 31.252,
        "lon": 102.752,
        "ele": 3600,
        "desc": "乘毕棚沟电瓶车出景区，完成穿越"
      }
    ]
  },
  {
    "id": "pub_cx_37",
    "title": "四姑娘山二峰初级雪山攀登",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 28.0,
    "elevation_gain_m": 1850,
    "elevation_max_m": 5276,
    "estimated_duration": "3天2夜",
    "best_season": "4月-11月",
    "downloads_count": 1850,
    "description": "户外爱好者的“人生第一座5000米雪山”。海拔5276米。由日隆镇（四姑娘山镇）海子沟入山，经朝山坪、打尖包抵大本营（4300m），凌晨登顶。线路成熟安全，配备协作与冰爪头盔即可体验真正的雪峰攀登成就感。",
    "waypoints": [
      {
        "id": "wp_cx37_1",
        "name": "海子沟售票处进山马道",
        "lat": 30.985,
        "lon": 102.852,
        "ele": 3200,
        "desc": "高山草甸起步爬升，体能分配至关重要"
      },
      {
        "id": "wp_cx37_2",
        "name": "朝山坪锅庄坪观景台",
        "lat": 31.012,
        "lon": 102.865,
        "ele": 3650,
        "desc": "正面一字排开的四姑娘山四座雪峰"
      },
      {
        "id": "wp_cx37_3",
        "name": "打尖包休息补给中继木屋",
        "lat": 31.052,
        "lon": 102.875,
        "ele": 3780,
        "desc": "热泡面、红牛补给点，分岔口向二峰营地"
      },
      {
        "id": "wp_cx37_4",
        "name": "二峰高山大本营(4300m)",
        "lat": 31.095,
        "lon": 102.895,
        "ele": 4300,
        "desc": "石头木屋或帐篷扎营，早歇备战凌晨2点冲顶"
      },
      {
        "id": "wp_cx37_5",
        "name": "碎石大陡坡与垭口拉绳处",
        "lat": 31.115,
        "lon": 102.912,
        "ele": 4950,
        "desc": "穿戴冰爪与安全头盔，抓握路绳攀升"
      },
      {
        "id": "wp_cx37_6",
        "name": "四姑娘山二峰峰顶(5276m)",
        "lat": 31.125,
        "lon": 102.918,
        "ele": 5276,
        "desc": "登顶眺望幺妹峰傲立云海，热泪盈眶"
      }
    ]
  },
  {
    "id": "pub_cx_38",
    "title": "稻城亚丁三神山大环线徒步",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 62.0,
    "elevation_gain_m": 2900,
    "elevation_max_m": 4750,
    "estimated_duration": "3天2夜",
    "best_season": "5月-10月",
    "downloads_count": 1750,
    "description": "香格里拉之魂。环绕仙乃日（观音）、央迈勇（文殊）、夏诺多吉（金刚手）三座呈品字形排列的圣洁雪山。由亚丁龙同坝、洛绒牛场出发，探访牛奶海、五色海，翻越央迈勇垭口经松多垭口沿卡斯地狱谷下行。高海拔冰川流石与缺氧挑战极大。",
    "waypoints": [
      {
        "id": "wp_cx38_1",
        "name": "亚丁冲古寺与珍珠海",
        "lat": 28.452,
        "lon": 100.352,
        "ele": 3880,
        "desc": "仙乃日雪山下碧绿海子"
      },
      {
        "id": "wp_cx38_2",
        "name": "洛绒牛场贡嘎河曲草甸",
        "lat": 28.395,
        "lon": 100.412,
        "ele": 4180,
        "desc": "三座神山汇聚中心，纯净的高山牧场"
      },
      {
        "id": "wp_cx38_3",
        "name": "牛奶海与五色海(海拔4600m)",
        "lat": 28.362,
        "lon": 100.385,
        "ele": 4600,
        "desc": "折射五彩光芒的古冰斗湖泊"
      },
      {
        "id": "wp_cx38_4",
        "name": "央迈勇松多垭口(4750m)",
        "lat": 28.325,
        "lon": 100.352,
        "ele": 4750,
        "desc": "全线最高点，直面央迈勇冰壁"
      },
      {
        "id": "wp_cx38_5",
        "name": "卡斯地狱谷幽深峡谷",
        "lat": 28.352,
        "lon": 100.252,
        "ele": 3200,
        "desc": "原始密林瀑布怪石，穿越出山"
      }
    ]
  },
  {
    "id": "pub_cx_39",
    "title": "党岭·葫芦海-丹巴自驾徒步线",
    "region": "chuanxi",
    "terrain": "forest_mountain",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "at_tire",
    "distance_km": 68.0,
    "elevation_gain_m": 1150,
    "elevation_max_m": 4200,
    "estimated_duration": "2天1夜",
    "best_season": "5-6月杜鹃, 9-10月秋色彩林",
    "downloads_count": 1120,
    "description": "丹巴嘉绒藏族风情与高山海子仙境。从中国最美乡村丹巴甲居藏寨出发，深入边耳乡党岭村，轻装或骑马徒步至海拔4160米的葫芦海（形似葫芦的高山海子）。温泉野汤与雪山倒影交织，秋季彩林绚烂夺目。",
    "waypoints": [
      {
        "id": "wp_cx39_1",
        "name": "丹巴甲居藏寨观景台",
        "lat": 30.885,
        "lon": 101.852,
        "ele": 2050,
        "desc": "梨花掩映下的白红特色藏式碉房"
      },
      {
        "id": "wp_cx39_2",
        "name": "边耳乡党岭村藏家乐",
        "lat": 31.025,
        "lon": 101.612,
        "ele": 3180,
        "desc": "村中木屋住宿，泡纯天然野温泉"
      },
      {
        "id": "wp_cx39_3",
        "name": "飞机坪草甸休息点",
        "lat": 31.052,
        "lon": 101.582,
        "ele": 3650,
        "desc": "开阔平坦的高山草场，马帮中继站"
      },
      {
        "id": "wp_cx39_4",
        "name": "党岭葫芦海湖畔(4160m)",
        "lat": 31.085,
        "lon": 101.552,
        "ele": 4160,
        "desc": "倒映夏羌拉雪峰的高原明珠，清澈见底"
      },
      {
        "id": "wp_cx39_5",
        "name": "大海子幽蓝秘境",
        "lat": 31.095,
        "lon": 101.535,
        "ele": 4250,
        "desc": "更深处的高山海子，原路返回党岭"
      }
    ]
  },
  {
    "id": "pub_cx_40",
    "title": "怒江大峡谷·滇西北秘境自驾",
    "region": "chuanxi",
    "terrain": "canyon_gorge",
    "category": "overland",
    "difficulty": 3,
    "vehicle_req": "at_tire",
    "distance_km": 320.0,
    "elevation_gain_m": 2450,
    "elevation_max_m": 3100,
    "estimated_duration": "3天2夜",
    "best_season": "11月-次年4月(怒江水碧蓝如翡翠)",
    "downloads_count": 1350,
    "description": "自云南保山/六库起，沿怒江美丽公路一路向北。穿过老虎跳急流峡谷、福贡石月亮奇观、贡山县城，深入独龙江乡寻找纹面女文化，抵达“人神共居”的丙中洛。冬季与早春怒江褪去浊浪，水色碧绿如翠玉。",
    "waypoints": [
      {
        "id": "wp_cx40_1",
        "name": "六库怒江美丽公路起点",
        "lat": 25.852,
        "lon": 98.852,
        "ele": 810,
        "desc": "怒江傈僳族自治州府，开启大峡谷自驾"
      },
      {
        "id": "wp_cx40_2",
        "name": "匹河飞来石与老姆登基督教堂",
        "lat": 26.582,
        "lon": 98.892,
        "ele": 1280,
        "desc": "怒族特色达玛花，听老姆登天籁赞美诗"
      },
      {
        "id": "wp_cx40_3",
        "name": "福贡石月亮高空山体透穿",
        "lat": 27.025,
        "lon": 98.865,
        "ele": 1150,
        "desc": "高黎贡山峰顶大理岩溶洞天然穿孔奇观"
      },
      {
        "id": "wp_cx40_4",
        "name": "独龙江高黎贡山隧道",
        "lat": 27.752,
        "lon": 98.452,
        "ele": 3020,
        "desc": "穿透雪山告别半年大雪封山历史，探寻独龙族"
      },
      {
        "id": "wp_cx40_5",
        "name": "丙中洛怒江第一湾",
        "lat": 28.012,
        "lon": 98.595,
        "ele": 1750,
        "desc": "怒江在此被气势磅礴的山石拦截形成大回环"
      }
    ]
  },
  {
    "id": "pub_cx_41",
    "title": "若尔盖大草原·黄河九曲第一湾",
    "region": "chuanxi",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 420.0,
    "elevation_gain_m": 650,
    "elevation_max_m": 3500,
    "estimated_duration": "2天1夜",
    "best_season": "6月-8月",
    "downloads_count": 1680,
    "description": "川西北高原“绿宝石”。途经红原月亮湾、唐克黄河九曲第一湾看长河落日大圆月，游历若尔盖花湖国家级黑颈鹤湿地保护区与郎木寺镇（甘川分界）。盛夏漫山遍野繁花似锦，牛羊宛如珍珠散落。",
    "waypoints": [
      {
        "id": "wp_cx41_1",
        "name": "红原县月亮湾景区",
        "lat": 32.785,
        "lon": 102.552,
        "ele": 3480,
        "desc": "白河水在茫茫草原上曲折如新月"
      },
      {
        "id": "wp_cx41_2",
        "name": "唐克黄河九曲第一湾观景台",
        "lat": 33.325,
        "lon": 102.485,
        "ele": 3550,
        "desc": "黄河与白河交汇，电梯登顶看雄浑大河落日"
      },
      {
        "id": "wp_cx41_3",
        "name": "若尔盖热尔大草原腹地",
        "lat": 33.682,
        "lon": 102.852,
        "ele": 3450,
        "desc": "中国仅次于呼伦贝尔的第二大草原"
      },
      {
        "id": "wp_cx41_4",
        "name": "若尔盖花湖木栈道",
        "lat": 33.912,
        "lon": 102.825,
        "ele": 3468,
        "desc": "高原泥炭沼泽湿地，黑颈鹤与天鹅飞舞"
      },
      {
        "id": "wp_cx41_5",
        "name": "郎木寺东方小瑞士镇",
        "lat": 34.085,
        "lon": 102.625,
        "ele": 3350,
        "desc": "一河跨甘川两省两座藏传古寺"
      }
    ]
  },
  {
    "id": "pub_cx_42",
    "title": "川西大环线全景深度自驾",
    "region": "chuanxi",
    "terrain": "snow_alpine",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 1680.0,
    "elevation_gain_m": 9500,
    "elevation_max_m": 4718,
    "estimated_duration": "7~9天",
    "best_season": "5-6月, 9-10月",
    "downloads_count": 3120,
    "description": "川西全景一网打尽的殿堂级自驾路线。成都出发，经雅安、康定折多山、新都桥光影天堂、理塘天空之城、稻城亚丁、新龙红山、甘孜格萨尔王城、色达五明佛学院红房子、炉霍、马尔康卓克基土司官寨返回成都。全线高等级公路，震撼无匹。",
    "waypoints": [
      {
        "id": "wp_cx42_1",
        "name": "成都绕城高速西出口",
        "lat": 30.658,
        "lon": 104.065,
        "ele": 500,
        "desc": "雅康高速启程，穿越二郎山特长隧道"
      },
      {
        "id": "wp_cx42_2",
        "name": "康定情歌广场与折多山(4298m)",
        "lat": 30.052,
        "lon": 101.812,
        "ele": 4298,
        "desc": "康巴第一关，正式步入藏区高海拔"
      },
      {
        "id": "wp_cx42_3",
        "name": "新都桥摄影家走廊",
        "lat": 30.025,
        "lon": 101.521,
        "ele": 3460,
        "desc": "白杨树、藏寨、小溪与金黄夕阳"
      },
      {
        "id": "wp_cx42_4",
        "name": "理塘西城门(海拔4014m)",
        "lat": 29.985,
        "lon": 100.285,
        "ele": 4014,
        "desc": "世界高城理塘，打卡勒通古镇与长青春科尔寺"
      },
      {
        "id": "wp_cx42_5",
        "name": "稻城金珠镇万亩青杨林",
        "lat": 29.052,
        "lon": 100.295,
        "ele": 3750,
        "desc": "尊胜塔林白塔，红草地与金秋杨林"
      },
      {
        "id": "wp_cx42_6",
        "name": "甘孜县城与雅砻江大雪山",
        "lat": 31.625,
        "lon": 99.985,
        "ele": 3390,
        "desc": "仰望雀儿山冰峰，格萨尔王文化圣地"
      },
      {
        "id": "wp_cx42_7",
        "name": "色达喇荣五明佛学院",
        "lat": 32.145,
        "lon": 100.752,
        "ele": 4000,
        "desc": "山谷遍布红色僧房，震撼万分的信仰之城"
      },
      {
        "id": "wp_cx42_8",
        "name": "马尔康卓克基土司官寨",
        "lat": 31.912,
        "lon": 102.254,
        "ele": 2680,
        "desc": "茅盾文学奖《尘埃落定》故事发生地，返程成都"
      }
    ]
  },
  {
    "id": "pub_qh_43",
    "title": "柴达木盆地·火星一号公路越野探险",
    "region": "qinghai",
    "terrain": "gobi_gravel",
    "category": "offroad",
    "difficulty": 4,
    "vehicle_req": "4x4_high_clearance",
    "distance_km": 365.0,
    "elevation_gain_m": 620,
    "elevation_max_m": 2980,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月",
    "downloads_count": 1890,
    "description": "地球上最像火星地貌的无人越野地带。由大柴旦翡翠湖出发，穿经世界上唯一的水上雅丹（乌素特），驶入G315火星一号公路（砂石非铺装），深入俄博梁雅丹硅化立柱群核心，入住火星营地睡眠舱，最终抵临冷湖石油废墟小镇。沿途严禁单车盲目驶离主航迹，沙地极易下沉深陷。",
    "waypoints": [
      {
        "id": "wp_qh43_1",
        "name": "大柴旦翡翠湖景区大门",
        "lat": 37.852,
        "lon": 95.325,
        "ele": 3140,
        "desc": "盐湖结晶色彩斑斓，出发前加满燃油"
      },
      {
        "id": "wp_qh43_2",
        "name": "G315网红U型公路段",
        "lat": 37.652,
        "lon": 94.452,
        "ele": 2850,
        "desc": "波浪起伏公路线，切勿路中停车拍照"
      },
      {
        "id": "wp_qh43_3",
        "name": "乌素特水上雅丹公园",
        "lat": 37.582,
        "lon": 93.852,
        "ele": 2720,
        "desc": "世界绝无仅有的水上雅丹地质地貌"
      },
      {
        "id": "wp_qh43_4",
        "name": "火星一号公路南端入口",
        "lat": 37.712,
        "lon": 93.421,
        "ele": 2780,
        "desc": "转入非铺装荒漠砂石路，开启低速减震模式"
      },
      {
        "id": "wp_qh43_5",
        "name": "冷湖火星营地空间站",
        "lat": 38.012,
        "lon": 93.254,
        "ele": 2890,
        "desc": "太空胶囊舱宿营体验，租借宇航服拍摄大片"
      },
      {
        "id": "wp_qh43_6",
        "name": "俄博梁雅丹魔鬼城核心",
        "lat": 38.125,
        "lon": 93.185,
        "ele": 2980,
        "desc": "规模宏大的柱状雅丹群，强磁场指南针失效"
      },
      {
        "id": "wp_qh43_7",
        "name": "冷湖石油工业废墟遗址",
        "lat": 38.745,
        "lon": 93.325,
        "ele": 2750,
        "desc": "昔日数万人油田基地遗迹，出荒漠完成穿越"
      }
    ]
  },
  {
    "id": "pub_qh_44",
    "title": "青海湖·祁连山大环线经典自驾",
    "region": "qinghai",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 1180.0,
    "elevation_gain_m": 3200,
    "elevation_max_m": 3820,
    "estimated_duration": "5~6天",
    "best_season": "6-8月",
    "downloads_count": 4200,
    "description": "西北最经典的国民大环线。西宁出发，经日月山抵青海湖二郎剑，漫步茶卡天空之镜盐湖，穿越柴达木盆地大柴旦翡翠湖，翻越祁连山脉卓尔山看东方小瑞士，途经门源百里油菜花海返回西宁。全线均为高等级柏油公路，配套设施完备成熟，老少皆宜。",
    "waypoints": [
      {
        "id": "wp_qh44_1",
        "name": "西宁火车站/机场集结点",
        "lat": 36.621,
        "lon": 101.785,
        "ele": 2260,
        "desc": "青甘大环线始发站，采购抗高反葡萄糖"
      },
      {
        "id": "wp_qh44_2",
        "name": "日月山文成公主进藏道",
        "lat": 36.425,
        "lon": 100.985,
        "ele": 3520,
        "desc": "黄土高原与青藏高原天然地理分界线"
      },
      {
        "id": "wp_qh44_3",
        "name": "青海湖二郎剑景区",
        "lat": 36.582,
        "lon": 100.452,
        "ele": 3200,
        "desc": "中国最大内陆咸水湖，蔚蓝湖水海天一色"
      },
      {
        "id": "wp_qh44_4",
        "name": "茶卡天空之镜盐湖",
        "lat": 36.712,
        "lon": 99.085,
        "ele": 3059,
        "desc": "小火车驶入盐湖腹地，白色倒影摄影圣地"
      },
      {
        "id": "wp_qh44_5",
        "name": "大柴旦翡翠湖",
        "lat": 37.852,
        "lon": 95.325,
        "ele": 3140,
        "desc": "矿物结晶形成的翠绿浅滩湖泊"
      },
      {
        "id": "wp_qh44_6",
        "name": "祁连县卓尔山风景区",
        "lat": 38.185,
        "lon": 100.254,
        "ele": 2980,
        "desc": "东方小瑞士，红色丹霞与油菜花群山辉映"
      },
      {
        "id": "wp_qh44_7",
        "name": "门源百里油菜花海",
        "lat": 37.385,
        "lon": 101.621,
        "ele": 2850,
        "desc": "7月万亩金色油菜花海壮丽盛景"
      },
      {
        "id": "wp_qh44_8",
        "name": "西宁市区闭环终点",
        "lat": 36.621,
        "lon": 101.785,
        "ele": 2260,
        "desc": "回到西宁，品尝炕锅羊肉与酸奶"
      }
    ]
  },
  {
    "id": "pub_qh_45",
    "title": "茫崖翡翠湖·恶魔之眼艾肯泉自驾",
    "region": "qinghai",
    "terrain": "gobi_gravel",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 480.0,
    "elevation_gain_m": 580,
    "elevation_max_m": 2920,
    "estimated_duration": "2天1夜",
    "best_season": "5-10月",
    "downloads_count": 1360,
    "description": "柴达木盆地最西端的极致色彩盛宴。经西台吉乃尔双色湖（一侧蓝一侧绿的奇景）、水上雅丹、黄瓜梁雅丹群，抵达茫崖市翡翠湖（深邃翠绿如琥珀），最后探寻奔涌数千年如恶魔之瞳的含硫热泉“艾肯泉”。",
    "waypoints": [
      {
        "id": "wp_qh45_1",
        "name": "大柴旦镇西向出发点",
        "lat": 37.852,
        "lon": 95.325,
        "ele": 3140,
        "desc": "沿G315国道一路西行向西柴达木深入"
      },
      {
        "id": "wp_qh45_2",
        "name": "西台吉乃尔双色湖",
        "lat": 37.625,
        "lon": 93.352,
        "ele": 2680,
        "desc": "公路两旁湖水因矿物质浓度不同呈现双色"
      },
      {
        "id": "wp_qh45_3",
        "name": "茫崖翡翠湖(黑独山旁)",
        "lat": 38.252,
        "lon": 90.185,
        "ele": 2900,
        "desc": "宛如镶嵌在黑色矿山中的碧玉翠池"
      },
      {
        "id": "wp_qh45_4",
        "name": "艾肯泉(恶魔之眼喷泉)",
        "lat": 38.152,
        "lon": 89.985,
        "ele": 2920,
        "desc": "高空俯瞰如一只巨大彩色眼睛脉动喷涌硫磺"
      },
      {
        "id": "wp_qh45_5",
        "name": "茫崖花土沟镇集结返程",
        "lat": 38.385,
        "lon": 90.452,
        "ele": 2880,
        "desc": "青新交界重镇，连通若羌出疆"
      }
    ]
  },
  {
    "id": "pub_qh_46",
    "title": "年宝玉则神山湖泊大环线徒步",
    "region": "qinghai",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 52.0,
    "elevation_gain_m": 1950,
    "elevation_max_m": 4600,
    "estimated_duration": "3天2夜",
    "best_season": "6月-8月",
    "downloads_count": 980,
    "description": "果洛藏族自治州久治县神山秘境。仰望果洛山主峰年宝玉则（5369m），徒步探访仙女湖、妖女湖、黑石海，翻越海拔4600米的下藏科达坂，途径日尕玛措。冰蚀悬崖陡峭如刀劈斧削，夏日野花地毯般铺展。",
    "waypoints": [
      {
        "id": "wp_qh46_1",
        "name": "年宝玉则国家地质公园入口",
        "lat": 33.352,
        "lon": 101.185,
        "ele": 3980,
        "desc": "仙女湖畔整备行囊，向妖女湖进发"
      },
      {
        "id": "wp_qh46_2",
        "name": "妖女湖深处灌木滩营地",
        "lat": 33.285,
        "lon": 101.125,
        "ele": 4050,
        "desc": "湖畔乱石与灌木丛，常有棕熊出没痕迹注意防范"
      },
      {
        "id": "wp_qh46_3",
        "name": "下藏科达坂(4600m)",
        "lat": 33.215,
        "lon": 101.052,
        "ele": 4600,
        "desc": "巨型花岗岩流石堆，手足并用攀爬翻越"
      },
      {
        "id": "wp_qh46_4",
        "name": "日尕玛措清澈圣湖",
        "lat": 33.152,
        "lon": 100.985,
        "ele": 4350,
        "desc": "远离喧嚣未开发处女湖"
      },
      {
        "id": "wp_qh46_5",
        "name": "西姆措与出山口下藏科乡",
        "lat": 33.085,
        "lon": 100.892,
        "ele": 3920,
        "desc": "乘接驳车出山完成年宝玉则转山"
      }
    ]
  },
  {
    "id": "pub_qh_47",
    "title": "阿尼玛卿雪山外环线转山徒步",
    "region": "qinghai",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 68.0,
    "elevation_gain_m": 2200,
    "elevation_max_m": 4680,
    "estimated_duration": "4天3夜",
    "best_season": "6月-9月",
    "downloads_count": 650,
    "description": "藏区四大神山之一（海拔6282米）。位于果洛玛沁县。藏传佛教信徒绕山一圈可洗清前世今生罪孽。沿途经过哈龙冰川、黄河源头支流、达玛垭口，全方位仰视雪山晶莹冰川。需携带专业保暖抗风装备与防高反物资。",
    "waypoints": [
      {
        "id": "wp_qh47_1",
        "name": "大武镇雪山乡大日加起点",
        "lat": 34.452,
        "lon": 99.452,
        "ele": 3950,
        "desc": "转山藏民起点，顺时针方向启程"
      },
      {
        "id": "wp_qh47_2",
        "name": "哈龙冰川舌前缘(4350m)",
        "lat": 34.612,
        "lon": 99.385,
        "ele": 4350,
        "desc": "长达数公里的巨大高山悬冰川瀑布"
      },
      {
        "id": "wp_qh47_3",
        "name": "下大坂与达玛垭口(4680m)",
        "lat": 34.785,
        "lon": 99.254,
        "ele": 4680,
        "desc": "狂风肆虐风口，经幡呼啸，撒龙达祈福"
      },
      {
        "id": "wp_qh47_4",
        "name": "格鲁派下大武寺与转山终点",
        "lat": 34.521,
        "lon": 99.125,
        "ele": 4010,
        "desc": "完成全线转山回到起点"
      }
    ]
  },
  {
    "id": "pub_qh_48",
    "title": "甘加秘境·白石崖八角古城穿越",
    "region": "qinghai",
    "terrain": "plateau_grassland",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 95.0,
    "elevation_gain_m": 850,
    "elevation_max_m": 3200,
    "estimated_duration": "1~2天",
    "best_season": "5月-10月",
    "downloads_count": 1120,
    "description": "甘南夏河拉卜楞寺北侧的遗世明珠。造访西汉古八角城（十字空心城墙遗址）、白石崖溶洞（丹尼索瓦古人类遗址）、高耸如屏风的巨型白石崖绝壁与甘加草原。土路与砂石车辙相连，景色苍凉宏大。",
    "waypoints": [
      {
        "id": "wp_qh48_1",
        "name": "夏河拉卜楞寺集合点",
        "lat": 35.202,
        "lon": 102.505,
        "ele": 2980,
        "desc": "世界藏学府，世界最长转经长廊打卡"
      },
      {
        "id": "wp_qh48_2",
        "name": "八角古城观景台",
        "lat": 35.352,
        "lon": 102.612,
        "ele": 3050,
        "desc": "两千年前汉代十字城墙古城堡俯瞰"
      },
      {
        "id": "wp_qh48_3",
        "name": "白石崖溶洞与寺院",
        "lat": 35.421,
        "lon": 102.685,
        "ele": 3280,
        "desc": "千仞白色石灰岩垂直绝壁，溶洞神秘探幽"
      },
      {
        "id": "wp_qh48_4",
        "name": "甘加草原草甸深处",
        "lat": 35.485,
        "lon": 102.752,
        "ele": 3150,
        "desc": "牛羊漫山，土路尽头返回夏河县城"
      }
    ]
  },
  {
    "id": "pub_qh_49",
    "title": "河西走廊历史文化自驾大道",
    "region": "qinghai",
    "terrain": "gobi_gravel",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 1150.0,
    "elevation_gain_m": 1850,
    "elevation_max_m": 2980,
    "estimated_duration": "5~6天",
    "best_season": "5-10月",
    "downloads_count": 3250,
    "description": "华夏文明金戈铁马的壮烈史诗。从兰州出发，穿越乌鞘岭，经武威雷台汉墓马踏飞燕、张掖七彩丹霞与大佛寺、酒泉卫星发射中心分道、天下第一雄关嘉峪关、瓜州大地之子，直抵丝路明珠敦煌莫高窟与鸣沙山月牙泉。",
    "waypoints": [
      {
        "id": "wp_qh49_1",
        "name": "兰州中山桥黄河第一桥",
        "lat": 36.065,
        "lon": 103.812,
        "ele": 1520,
        "desc": "品尝兰州牛肉面，启程跨越乌鞘岭"
      },
      {
        "id": "wp_qh49_2",
        "name": "武威雷台汉墓与凉州故城",
        "lat": 37.935,
        "lon": 102.652,
        "ele": 1530,
        "desc": "马踏飞燕国宝出土之地，汉唐凉州词"
      },
      {
        "id": "wp_qh49_3",
        "name": "张掖七彩丹霞地质公园",
        "lat": 38.982,
        "lon": 100.125,
        "ele": 1780,
        "desc": "夕阳下色彩斑斓犹如上帝打翻调色盘"
      },
      {
        "id": "wp_qh49_4",
        "name": "嘉峪关明代万里长城第一关",
        "lat": 39.812,
        "lon": 98.215,
        "ele": 1680,
        "desc": "河西咽喉锁钥，天下第一雄关"
      },
      {
        "id": "wp_qh49_5",
        "name": "瓜州戈壁清泉与无界大地之子",
        "lat": 40.521,
        "lon": 95.812,
        "ele": 1180,
        "desc": "荒漠中安详熟睡的巨大巨婴雕塑"
      },
      {
        "id": "wp_qh49_6",
        "name": "敦煌莫高窟与鸣沙山月牙泉",
        "lat": 40.142,
        "lon": 94.662,
        "ele": 1140,
        "desc": "千年莫高飞天壁画，大漠清泉相拥奇观"
      }
    ]
  },
  {
    "id": "pub_qh_50",
    "title": "扎尕那-大峪沟甘南秘境徒步",
    "region": "qinghai",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 58.0,
    "elevation_gain_m": 2300,
    "elevation_max_m": 3950,
    "estimated_duration": "3天2夜",
    "best_season": "6月-9月",
    "downloads_count": 850,
    "description": "深藏在甘南迭山山脉腹地的原生态穿越线。从扎尕那石城出发，沿桑成沟峡谷攀升翻越喀拉克垭口，穿经大峪沟九甸峡、旗杆石。峡谷流水潺潺，冷杉白桦层层叠叠，堪称东方阿尔卑斯。",
    "waypoints": [
      {
        "id": "wp_qh50_1",
        "name": "扎尕那代巴村徒步起点",
        "lat": 34.252,
        "lon": 103.225,
        "ele": 3020,
        "desc": "避开旅游主干道切入原生态峡谷"
      },
      {
        "id": "wp_qh50_2",
        "name": "冬才石林露营地",
        "lat": 34.312,
        "lon": 103.185,
        "ele": 3450,
        "desc": "怪石柱林耸立，扎营第一晚"
      },
      {
        "id": "wp_qh50_3",
        "name": "喀拉克达坂垭口(3950m)",
        "lat": 34.352,
        "lon": 103.125,
        "ele": 3950,
        "desc": "碎石大坡翻越点，俯瞰南北峡谷分界"
      },
      {
        "id": "wp_qh50_4",
        "name": "大峪沟阿角沟口",
        "lat": 34.412,
        "lon": 103.085,
        "ele": 2850,
        "desc": "青山绿水间出峡谷，卓尼县接驳返程"
      }
    ]
  },
  {
    "id": "pub_hb_51",
    "title": "太行天路·郭亮与昆山挂壁自驾",
    "region": "huabei",
    "terrain": "canyon_gorge",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 88.0,
    "elevation_gain_m": 950,
    "elevation_max_m": 1660,
    "estimated_duration": "1~2天",
    "best_season": "4-11月",
    "downloads_count": 1750,
    "description": "人工在千仞绝壁上开凿的公路奇迹。从河南新乡万仙山进入，穿过被誉为“世界第九大奇迹”的郭亮绝壁长廊，沿山脊天路通往山西陵川昆山挂壁公路（极窄险峻崖壁公路），再登临王莽岭俯瞰八百里太行群峰云海。挂壁路段狭窄需开启近光灯会车避让。",
    "waypoints": [
      {
        "id": "wp_hb51_1",
        "name": "万仙山景区南门入口",
        "lat": 35.712,
        "lon": 113.612,
        "ele": 850,
        "desc": "核验车牌与门票，入山盘山公路"
      },
      {
        "id": "wp_hb51_2",
        "name": "郭亮挂壁绝壁长廊",
        "lat": 35.735,
        "lon": 113.585,
        "ele": 1120,
        "desc": "全长1250米的人工开凿红岩绝壁挂壁天路"
      },
      {
        "id": "wp_hb51_3",
        "name": "郭亮石头村天池",
        "lat": 35.748,
        "lon": 113.572,
        "ele": 1250,
        "desc": "石磨、石桌、石屋，古朴民俗村落"
      },
      {
        "id": "wp_hb51_4",
        "name": "昆山挂壁公路(晋豫交界)",
        "lat": 35.682,
        "lon": 113.521,
        "ele": 1420,
        "desc": "比郭亮更原始更险窄的绝壁天路，小心擦碰后视镜"
      },
      {
        "id": "wp_hb51_5",
        "name": "王莽岭主峰龟驼峰",
        "lat": 35.652,
        "lon": 113.545,
        "ele": 1665,
        "desc": "太行山最高观景台，观壮丽太行日出与云海"
      }
    ]
  },
  {
    "id": "pub_hb_52",
    "title": "太行大峡谷·林州红旗渠天路",
    "region": "huabei",
    "terrain": "canyon_gorge",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 95.0,
    "elevation_gain_m": 1100,
    "elevation_max_m": 1580,
    "estimated_duration": "2天1夜",
    "best_season": "4-11月",
    "downloads_count": 1180,
    "description": "人工天河与南太行雄险风光结合。由林州红旗渠青年洞引水渠出发，盘山登上太行天路观景台，俯瞰桃花谷飞瀑深潭与王相岩摩天筒梯。红岩嶂谷地貌壁立千仞，壮怀激烈。",
    "waypoints": [
      {
        "id": "wp_hb52_1",
        "name": "红旗渠青年洞分水闸",
        "lat": 36.325,
        "lon": 113.785,
        "ele": 520,
        "desc": "峭壁上人工开凿的红旗渠咽喉工程"
      },
      {
        "id": "wp_hb52_2",
        "name": "桃花谷飞龙峡九连瀑",
        "lat": 36.125,
        "lon": 113.712,
        "ele": 780,
        "desc": "峡谷溪流潺潺，深潭碧绿如玉"
      },
      {
        "id": "wp_hb52_3",
        "name": "太行天路平步青云观景台",
        "lat": 36.085,
        "lon": 113.685,
        "ele": 1420,
        "desc": "俯瞰太行大峡谷U型谷底断崖"
      },
      {
        "id": "wp_hb52_4",
        "name": "梦幻玻璃栈道与旋梯",
        "lat": 36.052,
        "lon": 113.672,
        "ele": 1520,
        "desc": "崖壁悬空栈道，直视谷底深渊"
      },
      {
        "id": "wp_hb52_5",
        "name": "王相岩摩天筒梯终点",
        "lat": 35.985,
        "lon": 113.695,
        "ele": 890,
        "desc": "88米高垂直旋转钢梯挑战胆魄"
      }
    ]
  },
  {
    "id": "pub_hb_53",
    "title": "北京门头沟·京西古道探秘徒步",
    "region": "huabei",
    "terrain": "canyon_gorge",
    "category": "hiking",
    "difficulty": 2,
    "vehicle_req": "on_foot",
    "distance_km": 21.5,
    "elevation_gain_m": 680,
    "elevation_max_m": 880,
    "estimated_duration": "1天",
    "best_season": "3-5月, 9-11月",
    "downloads_count": 1620,
    "description": "北京最具历史沧桑感的文化徒步线路。寻觅马致远笔下“古道西风瘦马”的历史原型。从门头沟圈门出发，沿古香道攀行，途径天梯、峰口庵关隘、令人惊叹的数百年骡马踩踏出的“蹄窝遗迹”，至韭园村马致远故居。适合周末轻量化徒步健身与历史文化溯源。",
    "waypoints": [
      {
        "id": "wp_hb53_1",
        "name": "门头沟圈门古戏楼",
        "lat": 39.925,
        "lon": 116.052,
        "ele": 180,
        "desc": "京西古道起点，登台阶起步爬升"
      },
      {
        "id": "wp_hb53_2",
        "name": "天梯古香道陡坡",
        "lat": 39.918,
        "lon": 116.035,
        "ele": 380,
        "desc": "青石板台阶，坡度较陡，用登山杖借力"
      },
      {
        "id": "wp_hb53_3",
        "name": "峰口庵关隘城门",
        "lat": 39.905,
        "lon": 116.012,
        "ele": 650,
        "desc": "明清运煤古道重要关口"
      },
      {
        "id": "wp_hb53_4",
        "name": "蹄窝遗迹核心区",
        "lat": 39.901,
        "lon": 116.008,
        "ele": 620,
        "desc": "坚硬青石上深达数十厘米的百余个马蹄窝历史印记"
      },
      {
        "id": "wp_hb53_5",
        "name": "王平韭园村马致远故居",
        "lat": 39.952,
        "lon": 115.952,
        "ele": 280,
        "desc": "小桥流水人家，乘公交返城"
      }
    ]
  },
  {
    "id": "pub_hb_54",
    "title": "北京“三峰连穿”越野跑标杆线",
    "region": "huabei",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 24.8,
    "elevation_gain_m": 1850,
    "elevation_max_m": 1291,
    "estimated_duration": "1天",
    "best_season": "4-5月, 9-10月",
    "downloads_count": 2100,
    "description": "北京越野跑与高强度登山者的进阶考核线。自大觉寺古刹启程，登顶阳台山（1276m）、妙峰山娘娘庙金顶（1291m）、萝卜地北尖，下撤至涧沟村或大觉寺闭环。爬升剧烈，乱石路滑，是检验体能与心肺耐力的经典试金石。",
    "waypoints": [
      {
        "id": "wp_hb54_1",
        "name": "大觉寺古刹山门起点",
        "lat": 40.052,
        "lon": 116.098,
        "ele": 120,
        "desc": "古银杏树下启程，碎石台阶快速拉升心率"
      },
      {
        "id": "wp_hb54_2",
        "name": "萝卜地北尖山梁",
        "lat": 40.065,
        "lon": 116.065,
        "ele": 1105,
        "desc": "防火道与山脊小径交汇，远眺京城天际线"
      },
      {
        "id": "wp_hb54_3",
        "name": "阳台山主峰望京楼(1276m)",
        "lat": 40.075,
        "lon": 116.052,
        "ele": 1276,
        "desc": "海淀最高峰，玛尼石堆打卡"
      },
      {
        "id": "wp_xj54_4",
        "name": "妙峰山娘娘庙金顶(1291m)",
        "lat": 40.082,
        "lon": 116.012,
        "ele": 1291,
        "desc": "华北道教名山金顶，香火鼎盛"
      },
      {
        "id": "wp_hb54_5",
        "name": "涧沟村玫瑰谷终点",
        "lat": 40.095,
        "lon": 116.025,
        "ele": 680,
        "desc": "出山品尝妙峰山玫瑰饼与炸灌肠"
      }
    ]
  },
  {
    "id": "pub_hb_55",
    "title": "蔚县小五台山五台连穿山脊线",
    "region": "huabei",
    "terrain": "snow_alpine",
    "category": "hiking",
    "difficulty": 5,
    "vehicle_req": "on_foot",
    "distance_km": 38.0,
    "elevation_gain_m": 3200,
    "elevation_max_m": 2882,
    "estimated_duration": "2天1夜",
    "best_season": "6月中旬-7月中旬(金莲花盛开)",
    "downloads_count": 890,
    "description": "“河北屋脊”与华北户外殿堂级挑战。自赤崖堡出发，连续攻克北台、东台（2882米河北最高峰）、中台、西台、南台。万亩金莲花海与高山草甸在云海中翻腾，山脊线刀削斧劈，风大温低，水源极其匮乏，需严控体能负重。",
    "waypoints": [
      {
        "id": "wp_hb55_1",
        "name": "蔚县赤崖堡村进山点",
        "lat": 39.952,
        "lon": 115.052,
        "ele": 1050,
        "desc": "传统北沟进山，备足3L水与防寒抓绒"
      },
      {
        "id": "wp_hb55_2",
        "name": "北台垭口与北台顶(2837m)",
        "lat": 39.985,
        "lon": 115.085,
        "ele": 2837,
        "desc": "陡峭白石山梁爬升，首个大台顶"
      },
      {
        "id": "wp_hb55_3",
        "name": "东台顶河北第一峰(2882m)",
        "lat": 39.995,
        "lon": 115.125,
        "ele": 2882,
        "desc": "河北最高点玛尼堆，视野穿透燕山太行"
      },
      {
        "id": "wp_hb55_4",
        "name": "中台宿营大草甸(2801m)",
        "lat": 39.982,
        "lon": 115.105,
        "ele": 2801,
        "desc": "高山草甸平台，避风扎营赏日落云海"
      },
      {
        "id": "wp_hb55_5",
        "name": "西台与三岔山脊分水岭",
        "lat": 39.965,
        "lon": 115.075,
        "ele": 2671,
        "desc": "向南台连穿或从下金河口下撤分岔点"
      },
      {
        "id": "wp_hb55_6",
        "name": "南台金莲花坡出山",
        "lat": 39.912,
        "lon": 115.052,
        "ele": 1280,
        "desc": "穿越高山灌木林完成五台连穿"
      }
    ]
  },
  {
    "id": "pub_hb_56",
    "title": "大兴安岭·漠河极北找北公路",
    "region": "huabei",
    "terrain": "forest_mountain",
    "category": "overland",
    "difficulty": 2,
    "vehicle_req": "suv_standard",
    "distance_km": 520.0,
    "elevation_gain_m": 1100,
    "elevation_max_m": 1120,
    "estimated_duration": "3天2夜",
    "best_season": "6-8月森林避暑, 12-2月极寒冰雪",
    "downloads_count": 1520,
    "description": "中国地理最北端的林海寻北史诗。从加格达奇出发深入大兴安岭原始森林腹地，穿经呼中、漠河县城，抵达中国最北村庄“北红村”、北极村以及黑龙江第一湾（江湾如蛟龙盘旋）。冬季气温可破零下40度，极光寻踪胜地。",
    "waypoints": [
      {
        "id": "wp_hb56_1",
        "name": "加格达奇铁道林业枢纽",
        "lat": 50.425,
        "lon": 124.125,
        "ele": 450,
        "desc": "大兴安岭行署首府，检查防冻机油与雪地胎"
      },
      {
        "id": "wp_hb56_2",
        "name": "呼中大兴安岭最高峰大白山",
        "lat": 51.785,
        "lon": 123.582,
        "ele": 1120,
        "desc": "万顷落叶松林海波涛，中国最冷小镇"
      },
      {
        "id": "wp_hb56_3",
        "name": "漠河火灾纪念馆与五·六火灾遗址",
        "lat": 52.972,
        "lon": 122.525,
        "ele": 410,
        "desc": "警钟长鸣，松苑原始森林公园保留地"
      },
      {
        "id": "wp_hb56_4",
        "name": "黑龙江第一湾(龙江巨环)",
        "lat": 53.552,
        "lon": 123.285,
        "ele": 380,
        "desc": "滚滚黑龙江中俄界河深切U型大回旋"
      },
      {
        "id": "wp_hb56_5",
        "name": "中国真正最北村庄北红村",
        "lat": 53.502,
        "lon": 123.112,
        "ele": 320,
        "desc": "未过度商业化原始木刻楞小木屋村落"
      },
      {
        "id": "wp_hb56_6",
        "name": "北极村神州北极广场与最北哨所",
        "lat": 53.485,
        "lon": 122.352,
        "ele": 310,
        "desc": "找到最北邮局寄明信片，极北自驾圆满"
      }
    ]
  },
  {
    "id": "pub_hd_57",
    "title": "徽杭古道经典历史文化徒步",
    "region": "huadong",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 2,
    "vehicle_req": "on_foot",
    "distance_km": 22.0,
    "elevation_gain_m": 850,
    "elevation_max_m": 1050,
    "estimated_duration": "1~2天",
    "best_season": "3-5月油菜花, 9-11月秋色",
    "downloads_count": 2980,
    "description": "中国第一条著名徒步古道，“前世不修，生在徽州，十二三岁，往外一丢”的徽商奋斗血泪路。安徽绩溪伏岭村起步，攀登江南第一关险径，沿清凉峰峡谷石板路过下雪堂、蓝天凹（最高点草甸），终达浙江临安浙川村。石板路完备，适合全家与轻户外入门。",
    "waypoints": [
      {
        "id": "wp_hd57_1",
        "name": "绩溪伏岭镇鱼川村古道入口",
        "lat": 30.125,
        "lon": 118.852,
        "ele": 210,
        "desc": "徽派马头墙脚下出发，步入青石古道"
      },
      {
        "id": "wp_hd57_2",
        "name": "江南第一关(千层石阶栈道)",
        "lat": 30.138,
        "lon": 118.885,
        "ele": 480,
        "desc": "悬崖峭壁绝险开凿，俯瞰逍遥河峡谷深潭"
      },
      {
        "id": "wp_hd57_3",
        "name": "施茶亭与下雪堂农家乐",
        "lat": 30.145,
        "lon": 118.912,
        "ele": 620,
        "desc": "古商道免费茶亭遗迹，午间土鸡汤补给"
      },
      {
        "id": "wp_hd57_4",
        "name": "蓝天凹草甸垭口最高点(1050m)",
        "lat": 30.158,
        "lon": 118.952,
        "ele": 1050,
        "desc": "皖浙省界分水岭，两座险峰间的大草甸"
      },
      {
        "id": "wp_hd57_5",
        "name": "临安浙川村永来古村终点",
        "lat": 30.172,
        "lon": 119.012,
        "ele": 320,
        "desc": "抵达浙江境内，乘车前往杭州完成跨省穿越"
      }
    ]
  },
  {
    "id": "pub_hd_58",
    "title": "江西武功山十万亩高山草甸穿越",
    "region": "huadong",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 42.0,
    "elevation_gain_m": 2400,
    "elevation_max_m": 1918,
    "estimated_duration": "2天1夜",
    "best_season": "5月-10月(绿草如茵与云海帐篷节)",
    "downloads_count": 3650,
    "description": "“天上草原，人间仙境”。中国南方最震撼的高山云中草甸。自沈子村登山，经九龙山、铁蹄峰直达武功山最高金顶（海拔1918米），再沿山脊跌宕起伏穿过吊马桩、发云界至羊狮幕。云海、日出、金色草甸与漫山遍野的徒步帐篷构成绝美国度。",
    "waypoints": [
      {
        "id": "wp_hd58_1",
        "name": "沈子村水电站徒步传统起点",
        "lat": 27.512,
        "lon": 114.185,
        "ele": 380,
        "desc": "避开索道纯重装起步，溯溪竹林爬升"
      },
      {
        "id": "wp_hd58_2",
        "name": "铁蹄峰巨石阵险段",
        "lat": 27.485,
        "lon": 114.152,
        "ele": 1680,
        "desc": "乱石险坡，手脚并用登上山脊线草甸"
      },
      {
        "id": "wp_hd58_3",
        "name": "武功山金顶世纪之碑(1918m)",
        "lat": 27.465,
        "lon": 114.162,
        "ele": 1918,
        "desc": "江西名山之巅，古祭坛群，壮丽云海翻涌"
      },
      {
        "id": "wp_hd58_4",
        "name": "吊马桩木栈道与玻璃桥",
        "lat": 27.452,
        "lon": 114.145,
        "ele": 1580,
        "desc": "山脊大风口，客栈驿站补给温水与干粮"
      },
      {
        "id": "wp_hd58_5",
        "name": "千丈岩与绝望坡大落差",
        "lat": 27.425,
        "lon": 114.125,
        "ele": 1720,
        "desc": "连续近70度陡峭草坡碎石道，极度考验膝盖"
      },
      {
        "id": "wp_hd58_6",
        "name": "发云界客栈聚落群",
        "lat": 27.395,
        "lon": 114.102,
        "ele": 1510,
        "desc": "高山草甸最厚密处，落日晚霞与繁星宿营"
      },
      {
        "id": "wp_hd58_7",
        "name": "龙山村或龙王潭出山终点",
        "lat": 27.352,
        "lon": 114.085,
        "ele": 450,
        "desc": "下撤至萍乡乘车返程"
      }
    ]
  },
  {
    "id": "pub_hd_59",
    "title": "湖北神农架原始森林无人区穿行",
    "region": "huadong",
    "terrain": "forest_mountain",
    "category": "hiking",
    "difficulty": 4,
    "vehicle_req": "on_foot",
    "distance_km": 58.0,
    "elevation_gain_m": 2800,
    "elevation_max_m": 3106,
    "estimated_duration": "3天2夜",
    "best_season": "5月-10月",
    "downloads_count": 820,
    "description": "“华中屋脊”与野人传说迷境。自木鱼镇进入，穿越神秘原始暗针叶林、冷杉林、泥炭藓沼泽，登顶海拔3106米的神农顶（华中第一峰），探访大九湖高山湿地。森林幽深遮天蔽日，空气负氧离子极高，需严格防范迷路与金丝猴、黑熊等野生动物接触。",
    "waypoints": [
      {
        "id": "wp_hd59_1",
        "name": "木鱼镇鸭子垭景区起点",
        "lat": 31.685,
        "lon": 110.452,
        "ele": 1680,
        "desc": "神农架林区探秘起点，随身携带哨子防野兽"
      },
      {
        "id": "wp_hd59_2",
        "name": "神农谷喀斯特溶蚀深谷",
        "lat": 31.725,
        "lon": 110.352,
        "ele": 2820,
        "desc": "云雾缭绕奇峰林立，万级台阶下沉又爬升"
      },
      {
        "id": "wp_hd59_3",
        "name": "神农顶华中屋脊(3106m)",
        "lat": 31.745,
        "lon": 110.305,
        "ele": 3106,
        "desc": "华中最高峰烽火台，眺望秦巴山脉连绵起伏"
      },
      {
        "id": "wp_hd59_4",
        "name": "板壁岩石林与野人出没遗址",
        "lat": 31.735,
        "lon": 110.252,
        "ele": 2580,
        "desc": "怪石嶙峋，箭竹林海生生不息"
      },
      {
        "id": "wp_hd59_5",
        "name": "大九湖国家湿地公园黑水河",
        "lat": 31.552,
        "lon": 110.052,
        "ele": 1730,
        "desc": "高山平原九个清澈湖泊连缀，晨雾如梦如幻"
      }
    ]
  },
  {
    "id": "pub_hd_60",
    "title": "张家界天子山-杨家界野线徒步",
    "region": "huadong",
    "terrain": "canyon_gorge",
    "category": "hiking",
    "difficulty": 3,
    "vehicle_req": "on_foot",
    "distance_km": 32.0,
    "elevation_gain_m": 1650,
    "elevation_max_m": 1260,
    "estimated_duration": "2天1夜",
    "best_season": "4-11月",
    "downloads_count": 1850,
    "description": "三千奇峰拔地而起的砂岩峰林地貌。避开常规拥挤电梯索道，从金鞭溪峡谷切入乱窜坡爬升至袁家界（阿凡达哈利路亚悬浮山原型），沿未开发野径穿行至杨家界乌龙寨、天波府、一步登天绝壁险峰，直达天子山御笔峰。台阶湿滑险峻，需良好平衡感。",
    "waypoints": [
      {
        "id": "wp_hd60_1",
        "name": "国家森林公园老门票站",
        "lat": 29.325,
        "lon": 110.452,
        "ele": 450,
        "desc": "漫步金鞭溪幽谷，猕猴嬉戏"
      },
      {
        "id": "wp_hd60_2",
        "name": "乱窜坡陡峭乱石石阶",
        "lat": 29.352,
        "lon": 110.435,
        "ele": 920,
        "desc": "2000余级台阶直线拔高，穿透峰林"
      },
      {
        "id": "wp_hd60_3",
        "name": "袁家界迷魂台与天下第一桥",
        "lat": 29.358,
        "lon": 110.428,
        "ele": 1050,
        "desc": "电影《阿凡达》哈利路亚乾坤柱取景地"
      },
      {
        "id": "wp_hd60_4",
        "name": "杨家界一步登天绝壁铁梯",
        "lat": 29.382,
        "lon": 110.395,
        "ele": 1180,
        "desc": "直立悬空铁梯攀爬，峰林顶端孤立平台"
      },
      {
        "id": "wp_hd60_5",
        "name": "天子山御笔峰与仙女献花",
        "lat": 29.412,
        "lon": 110.452,
        "ele": 1260,
        "desc": "神工鬼斧石笔冲天，下山乘车完成穿越"
      }
    ]
  },
  {
    "id": "pub_hd_61",
    "title": "恩施大峡谷·清江地缝绝壁栈道",
    "region": "huadong",
    "terrain": "canyon_gorge",
    "category": "hiking",
    "difficulty": 2,
    "vehicle_req": "on_foot",
    "distance_km": 26.0,
    "elevation_gain_m": 1150,
    "elevation_max_m": 1520,
    "estimated_duration": "1~2天",
    "best_season": "4-10月",
    "downloads_count": 1720,
    "description": "喀斯特地貌发育最完全的地下与天上地质博物馆。深度探访云龙地缝深潭飞瀑暗河，攀上七星寨万米绝壁长廊悬空栈道，近观世界奇观“一炷香”（高150米、细如蜡烛屹立千万年的石柱），下行跨越迎客松与母子情深峰。",
    "waypoints": [
      {
        "id": "wp_hd61_1",
        "name": "恩施大峡谷游客服务中心",
        "lat": 30.312,
        "lon": 109.215,
        "ele": 680,
        "desc": "峡谷启程，下行步入云龙地缝地壳裂隙"
      },
      {
        "id": "wp_hd61_2",
        "name": "云龙地缝彩虹瀑布底",
        "lat": 30.305,
        "lon": 109.208,
        "ele": 520,
        "desc": "两岸绝壁垂直相峙，飞瀑奔腾轰鸣"
      },
      {
        "id": "wp_hd61_3",
        "name": "七星寨绝壁长廊悬空栈道",
        "lat": 30.285,
        "lon": 109.195,
        "ele": 1420,
        "desc": "人工悬空栈道挂在近90度赤壁上，直视千米深谷"
      },
      {
        "id": "wp_hd61_4",
        "name": "一炷香天地神迹石柱(150m)",
        "lat": 30.275,
        "lon": 109.182,
        "ele": 1480,
        "desc": "细长石柱历经数次大地震岿然不倒的世界地质奇迹"
      },
      {
        "id": "wp_hd61_5",
        "name": "甘堰塘手扶电梯出口",
        "lat": 30.265,
        "lon": 109.175,
        "ele": 850,
        "desc": "乘亚洲最长户外手扶电梯出山"
      }
    ]
  },
  {
    "id": "pub_hd_62",
    "title": "海南环岛旅游公路海滨自驾线",
    "region": "huanan",
    "terrain": "canyon_gorge",
    "category": "overland",
    "difficulty": 1,
    "vehicle_req": "suv_standard",
    "distance_km": 988.0,
    "elevation_gain_m": 450,
    "elevation_max_m": 320,
    "estimated_duration": "5~6天",
    "best_season": "全年皆宜(10月-次年4月最佳避寒)",
    "downloads_count": 3850,
    "description": "中国首条高标准热带滨海景观旅游公路。贯通海口、文昌航天木兰湾风车海岸、琼海博鳌亚洲论坛、万宁石梅湾/日月湾冲浪圣地、三亚海棠湾亚龙湾、乐东莺歌海千顷盐田、昌江棋子湾奇石海岸至儋州洋浦。椰影婆娑，海风轻抚，尽览南国热带海滨风光。",
    "waypoints": [
      {
        "id": "wp_hd62_1",
        "name": "海口新埠岛海边出发点",
        "lat": 20.085,
        "lon": 110.352,
        "ele": 5,
        "desc": "开启顺时针988公里环岛海景天路"
      },
      {
        "id": "wp_hd62_2",
        "name": "文昌木兰湾虎头灯塔风车海岸",
        "lat": 20.152,
        "lon": 110.852,
        "ele": 25,
        "desc": "亚洲第一高灯塔，白色大风车立于礁石海岸"
      },
      {
        "id": "wp_hd62_3",
        "name": "万宁日月湾与石梅湾山海天路",
        "lat": 18.652,
        "lon": 110.215,
        "ele": 15,
        "desc": "冲浪胜地，碧海白浪，最美沿海公路段"
      },
      {
        "id": "wp_hd62_4",
        "name": "三亚海棠湾亚特兰蒂斯",
        "lat": 18.325,
        "lon": 109.752,
        "ele": 10,
        "desc": "国际旅游度假区，免税城与顶级度假酒店"
      },
      {
        "id": "wp_hd62_5",
        "name": "乐东莺歌海千年银白盐田",
        "lat": 18.512,
        "lon": 108.725,
        "ele": 5,
        "desc": "海南最大海盐场，如雪地结晶倒映晚霞"
      },
      {
        "id": "wp_hd62_6",
        "name": "昌江棋子湾多彩卵石海岸",
        "lat": 19.325,
        "lon": 108.612,
        "ele": 20,
        "desc": "礁石与金黄细沙相伴，海边日落壮阔"
      },
      {
        "id": "wp_hd62_7",
        "name": "儋州洋浦千年古盐田返回海口",
        "lat": 19.752,
        "lon": 109.185,
        "ele": 15,
        "desc": "火山岩玄武岩开凿古盐槽，闭环回到海口"
      }
    ]
  }
]

inserted = 0
updated = 0
now_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

for r in ROUTES:
    wpts_json = json.dumps(r['waypoints'], ensure_ascii=False)
    pts_cnt = len(r['waypoints'])
    
    cur.execute("SELECT id FROM public_roadbooks WHERE id = ?", (r['id'],))
    row = cur.fetchone()
    if row:
        cur.execute('''
            UPDATE public_roadbooks SET
                title = ?, region = ?, terrain = ?, category = ?, difficulty = ?,
                vehicle_req = ?, distance_km = ?, points_count = ?, elevation_gain_m = ?,
                elevation_max_m = ?, estimated_duration = ?, best_season = ?,
                downloads_count = ?, status = 'approved', roadbook_json = ?
            WHERE id = ?
        ''', (
            r['title'], r['region'], r['terrain'], r['category'], r['difficulty'],
            r['vehicle_req'], r['distance_km'], pts_cnt, r['elevation_gain_m'],
            r['elevation_max_m'], r['estimated_duration'], r['best_season'],
            r['downloads_count'], wpts_json, r['id']
        ))
        updated += 1
    else:
        cur.execute('''
            INSERT INTO public_roadbooks (
                id, author_id, author_name, title, region, terrain, category,
                difficulty, vehicle_req, distance_km, points_count, elevation_gain_m,
                elevation_max_m, estimated_duration, best_season, downloads_count,
                status, roadbook_json, created_at, reviewer_name
            ) VALUES (?, 'adm_root', '山海行官方智库', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?, ?, 'ScriptSeed')
        ''', (
            r['id'], r['title'], r['region'], r['terrain'], r['category'],
            r['difficulty'], r['vehicle_req'], r['distance_km'], pts_cnt,
            r['elevation_gain_m'], r['elevation_max_m'], r['estimated_duration'],
            r['best_season'], r['downloads_count'], wpts_json, now_str
        ))
        inserted += 1

conn.commit()
conn.close()

print(f"[√] 注入完成！新增 {inserted} 条，更新 {updated} 条，共计 {len(ROUTES)} 条经典路线已入库就绪。")
