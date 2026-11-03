// ==============================================================================
// 项目名称: 山海行 (TerraWay) 全地形手持离线 GPS 导航系统 - 极简高安全 VPS 服务端
// 语言架构: Go (Golang 1.22+) + Pure-Go SQLite (WAL 模式)
// 核心特性:
// 1. 编译期强类型与内存安全，单二进制静态编译，零 CGO / 零外部动态库依赖；
// 2. 全量 SQL 100% 预编译参数化查询，彻底免疫 SQL 注入；
// 3. 密码采用 Bcrypt 慢哈希加盐加密 + HMAC-SHA256 无状态 JWT 鉴权；
// 4. 内置基于 IP 的防暴力破解限流器 (Rate Limiter) 与全局防崩溃守护 (Panic Recovery)；
// 5. v0.7.7 重磅重构与升级:
//    - 自动无损数据库迁移 (Auto Migration)，智能兼容旧库，确保默认超级管理 admin 100% 入表且可修改密码；
//    - 修复添加管理员失败问题，采用标准 Modal 模态弹窗 + 下拉选择菜单，彻底告别浏览器 prompt 拦截；
//    - 升级传统经典「左侧多级树形导航栏 (Tree Sidebar)」，分类清晰大方；
//    - 权限与安全菜单统一收纳：管理员团队管理、角色权限矩阵，添加/编辑管理员支持下拉菜单选择角色与标准头衔。
// ==============================================================================

package main

import (
	"compress/gzip"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"math"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

var (
	listenAddr = getEnv("TERRAWAY_ADDR", ":8080")
	dataDir    = getEnv("TERRAWAY_DATA_DIR", "./data")
	jwtSecret  = []byte(getEnv("TERRAWAY_JWT_SECRET", "terraway-jwt-secret-key-2026-secure"))
	adminKey   = getEnv("TERRAWAY_ADMIN_KEY", "terraway-admin-2026")
	db         *sql.DB
	publicDb   *sql.DB
)

func getEnv(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

// ============================================================================
// 1. IP 令牌桶防爆破限流器与管理后台防暴破锁
// ============================================================================

type visitor struct {
	tokens   float64
	lastSeen time.Time
}

type rateLimiter struct {
	mu       sync.Mutex
	visitors map[string]*visitor
	rate     float64
	burst    float64
}

func newRateLimiter(rate, burst float64) *rateLimiter {
	rl := &rateLimiter{
		visitors: make(map[string]*visitor),
		rate:     rate,
		burst:    burst,
	}
	go func() {
		for {
			time.Sleep(5 * time.Minute)
			rl.mu.Lock()
			for ip, v := range rl.visitors {
				if time.Since(v.lastSeen) > 10*time.Minute {
					delete(rl.visitors, ip)
				}
			}
			rl.mu.Unlock()
		}
	}()
	return rl
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	v, exists := rl.visitors[ip]
	if !exists {
		rl.visitors[ip] = &visitor{tokens: rl.burst - 1, lastSeen: now}
		return true
	}

	elapsed := now.Sub(v.lastSeen).Seconds()
	v.lastSeen = now
	v.tokens += elapsed * rl.rate
	if v.tokens > rl.burst {
		v.tokens = rl.burst
	}
	if v.tokens < 1.0 {
		return false
	}
	v.tokens -= 1.0
	return true
}

var apiLimiter = newRateLimiter(5.0, 30.0)

type adminLoginLock struct {
	mu       sync.Mutex
	attempts map[string]int
	lockedAt map[string]time.Time
}

var adminLock = &adminLoginLock{
	attempts: make(map[string]int),
	lockedAt: make(map[string]time.Time),
}

func (l *adminLoginLock) checkAllowed(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if lockTime, locked := l.lockedAt[ip]; locked {
		if time.Since(lockTime) < 15*time.Minute {
			return false
		}
		delete(l.lockedAt, ip)
		delete(l.attempts, ip)
	}
	return true
}

func (l *adminLoginLock) recordFailed(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	l.attempts[ip]++
	if l.attempts[ip] >= 5 {
		l.lockedAt[ip] = time.Now()
	}
}

func (l *adminLoginLock) recordSuccess(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	delete(l.attempts, ip)
	delete(l.lockedAt, ip)
}

type adminSessionInfo struct {
	Token       string
	AdminID     string
	Username    string
	DisplayName string
	RoleKey     string
	RoleLevel   int
	ExpiresAt   time.Time
}

type adminSessionManager struct {
	mu       sync.Mutex
	sessions map[string]*adminSessionInfo
}

var adminSessions = &adminSessionManager{sessions: make(map[string]*adminSessionInfo)}

func (s *adminSessionManager) createSession(adminID, username, displayName, roleKey string, roleLevel int) string {
	s.mu.Lock()
	defer s.mu.Unlock()

	b := make([]byte, 32)
	_, _ = rand.Read(b)
	token := hex.EncodeToString(b)
	s.sessions[token] = &adminSessionInfo{
		Token:       token,
		AdminID:     adminID,
		Username:    username,
		DisplayName: displayName,
		RoleKey:     roleKey,
		RoleLevel:   roleLevel,
		ExpiresAt:   time.Now().Add(2 * time.Hour),
	}
	return token
}

func (s *adminSessionManager) getSession(token string) *adminSessionInfo {
	if token == "" {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	sess, ok := s.sessions[token]
	if !ok || time.Now().After(sess.ExpiresAt) {
		delete(s.sessions, token)
		return nil
	}
	sess.ExpiresAt = time.Now().Add(30 * time.Minute)
	return sess
}

func (s *adminSessionManager) revoke(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, token)
}

// ============================================================================
// 2. 数据库初始化与自动无损平滑迁移 (Auto Schema Migration)
// ============================================================================

func initDatabase() error {
	if err := os.MkdirAll(filepath.Join(dataDir, "tracks"), 0750); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(dataDir, "apk_cache"), 0750); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(dataDir, "roadbooks"), 0750); err != nil {
		return err
	}

	dbPath := filepath.Join(dataDir, "terraway_vault.db")
	var err error
	db, err = sql.Open("sqlite", dbPath)
	if err != nil {
		return err
	}

	pragmas := []string{
		"PRAGMA journal_mode=WAL;",
		"PRAGMA synchronous=NORMAL;",
		"PRAGMA busy_timeout=5000;",
		"PRAGMA foreign_keys=ON;",
	}
	for _, p := range pragmas {
		if _, err := db.Exec(p); err != nil {
			return err
		}
	}

	schema := `
	CREATE TABLE IF NOT EXISTS admin_roles (
		role_key TEXT PRIMARY KEY,
		role_name TEXT NOT NULL,
		level INTEGER NOT NULL,
		description TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS admins (
		id TEXT PRIMARY KEY,
		username TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		display_name TEXT NOT NULL,
		role_key TEXT NOT NULL DEFAULT 'super_admin',
		is_active INTEGER DEFAULT 1,
		created_at TEXT NOT NULL,
		last_login_at TEXT
	);

	CREATE TABLE IF NOT EXISTS users (
		id TEXT PRIMARY KEY,
		phone_or_email TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		nickname TEXT NOT NULL,
		avatar_url TEXT DEFAULT '',
		gender TEXT DEFAULT '保密',
		bio TEXT DEFAULT '心向山海，无畏前行',
		vehicle_model TEXT DEFAULT '未登记',
		emergency_contact_name TEXT DEFAULT '',
		emergency_contact_phone TEXT DEFAULT '',
		total_distance_m REAL DEFAULT 0,
		routes_count INTEGER DEFAULT 0,
		is_verified INTEGER DEFAULT 0,
		status INTEGER DEFAULT 1,
		created_at TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS user_tickets (
		id TEXT PRIMARY KEY,
		user_account TEXT NOT NULL,
		ticket_type TEXT NOT NULL,
		contact_info TEXT NOT NULL,
		message TEXT NOT NULL,
		status TEXT NOT NULL DEFAULT 'pending',
		admin_reply TEXT DEFAULT '',
		created_at TEXT NOT NULL,
		resolved_at TEXT
	);

	CREATE TABLE IF NOT EXISTS user_tracks (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL,
		name TEXT NOT NULL,
		distance_m REAL DEFAULT 0,
		points_count INTEGER DEFAULT 0,
		storage_path TEXT NOT NULL,
		uploaded_at TEXT NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_tracks_user ON user_tracks(user_id);

	CREATE TABLE IF NOT EXISTS user_roadbooks (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL,
		name TEXT NOT NULL,
		points_count INTEGER DEFAULT 0,
		share_code TEXT,
		storage_path TEXT NOT NULL,
		uploaded_at TEXT NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_roadbooks_user ON user_roadbooks(user_id);
	CREATE INDEX IF NOT EXISTS idx_roadbooks_code ON user_roadbooks(share_code);

	CREATE TABLE IF NOT EXISTS app_releases (
		version_code INTEGER PRIMARY KEY,
		version_name TEXT NOT NULL,
		apk_url TEXT NOT NULL,
		apk_sha256 TEXT DEFAULT '',
		apk_size_mb REAL DEFAULT 18.5,
		changelog_zh TEXT NOT NULL,
		changelog_en TEXT NOT NULL,
		is_forced INTEGER DEFAULT 0,
		release_date TEXT NOT NULL
	);`

	if _, err := db.Exec(schema); err != nil {
		return err
	}

	// --------------------------------------------------------------------------
	// 关键：自动检测并迁移现有旧表字段 (修复之前升级导致的 no such column 错误)
	// --------------------------------------------------------------------------
	migrateAdminColumns()
	migrateUserColumns()

	// 预置系统四大法定角色
	rolesInit := []struct {
		key, name, desc string
		level           int
	}{
		{"super_admin", "超级总管理员", "全系统最高控制权，可分配/注销管理员、发布新版 App 与系统运维", 100},
		{"admin", "系统管理员", "日常技术与运维，可管理普通用户、处理工单、管理路书，不可修改超级管理员", 50},
		{"operator", "业务操作员", "客服专员，专门负责查阅处理密码找回工单、重置临时密码，无发版与管理管理员权限", 20},
		{"auditor", "线路审核员", "路线安全审核领队，仅可查阅与审核公开路书与 6 位短码，无用户管理权限", 10},
	}
	for _, r := range rolesInit {
		_, _ = db.Exec(`
			INSERT OR REPLACE INTO admin_roles (role_key, role_name, level, description)
			VALUES (?, ?, ?, ?)`, r.key, r.name, r.level, r.desc)
	}

	// 确保超级管理员 admin 100% 存在且可管理修改
	var adminExists int
	_ = db.QueryRow(`SELECT COUNT(*) FROM admins WHERE username = 'admin'`).Scan(&adminExists)
	if adminExists == 0 {
		hash, err := bcrypt.GenerateFromPassword([]byte(adminKey), bcrypt.DefaultCost)
		if err == nil {
			_, _ = db.Exec(`
				INSERT INTO admins (id, username, password_hash, display_name, role_key, is_active, created_at)
				VALUES (?, ?, ?, ?, ?, 1, ?)`,
				"adm_root", "admin", string(hash), "超级管理员", "super_admin", time.Now().Format("2006-01-02 15:04:05"),
			)
			log.Printf("[INIT] 默认超级管理员 admin 创建成功，初始密码与 adminKey 一致")
		}
	} else {
		// 确保 admin 的 role_key 绝对是 super_admin
		_, _ = db.Exec(`UPDATE admins SET role_key = 'super_admin' WHERE username = 'admin'`)
	}

	// 预置基准版本 v0.7.7 (version_code = 22)
	_, _ = db.Exec(`
		INSERT OR IGNORE INTO app_releases (
			version_code, version_name, apk_url, apk_sha256, apk_size_mb,
			changelog_zh, changelog_en, is_forced, release_date
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		20,
		"0.7.7",
		"https://github.com/qingmi2001/terraway-app/releases/latest/download/terraway_gps_v0.7.7.apk",
		"85a3acfbc3f7223e85fbfbdb6e2c2ddd28283732b6447743f9b5ef3b49f691b0",
		18.5,
		"1. 服务端重构左侧多级树形导航，强化 RBAC 权限与角色管理\n2. 修复超级管理员 admin 密码修改与添加管理员弹窗交互\n3. 数据库无损自动迁移兼容",
		"1. Redesigned admin dashboard with tree sidebar\n2. Fixed admin password update & modal dialogs\n3. Database schema auto-migration",
		0,
		time.Now().Format("2006-01-02"),
	)

	
	// -------------------------------------------------------------
	// 物理隔离数据库: 公共线路广场数据库 (terraway_public.db)
	// 仅存储官方精选、社区审核通过的公共路书与地理分类元数据，保障高频只读分发与 CDN 缓存
	// -------------------------------------------------------------
	publicDbPath := filepath.Join(dataDir, "terraway_public.db")
	var errPub error
	publicDb, errPub = sql.Open("sqlite", publicDbPath)
	if errPub != nil {
		return errPub
	}
	for _, p := range pragmas {
		if _, err := publicDb.Exec(p); err != nil {
			return err
		}
	}

	publicSchema := `
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
	CREATE INDEX IF NOT EXISTS idx_pub_region ON public_roadbooks(region);
	CREATE INDEX IF NOT EXISTS idx_pub_category ON public_roadbooks(category);
	CREATE INDEX IF NOT EXISTS idx_pub_status ON public_roadbooks(status);
`
	if _, err := publicDb.Exec(publicSchema); err != nil {
		return err
	}


	// -------------------------------------------------------------
	// 1. 基础数据字典主数据表 (Master Data Dictionary Engine)
	// 解耦地理归属大区、地形地貌、运动场景、车辆装备与难度评级，实现高内聚低耦合
	// -------------------------------------------------------------
	dictSchema := `
	CREATE TABLE IF NOT EXISTS system_dictionaries (
		id TEXT PRIMARY KEY,
		dict_type TEXT NOT NULL,       -- region / terrain / category / vehicle_req / difficulty
		dict_code TEXT NOT NULL,       -- 唯一标识码 (如 neimenggu, sand_dune, offroad)
		dict_label TEXT NOT NULL,      -- 显示名称 (如 内蒙古大区, 流动沙丘/刀锋)
		dict_desc TEXT DEFAULT '',     -- 业务说明 / 安全避险规范 / 到站判定米数
		sort_order INTEGER DEFAULT 0,
		is_active INTEGER DEFAULT 1,
		meta_json TEXT DEFAULT '{}',   -- 扩展元数据 (如中心坐标、默认半径等)
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(dict_type, dict_code)
	);
	CREATE INDEX IF NOT EXISTS idx_dict_type ON system_dictionaries(dict_type);

	-- -------------------------------------------------------------
	-- 2. 团队发布与临时协助路书表 (Team / Squad Roadbooks)
	-- 用于车队自驾编队、荒野互助、搜救应急协作，支持 6 位专属口令与时效控制
	-- -------------------------------------------------------------
	CREATE TABLE IF NOT EXISTS team_roadbooks (
		id TEXT PRIMARY KEY,
		team_name TEXT NOT NULL,
		creator_id TEXT NOT NULL,
		creator_name TEXT NOT NULL,
		squad_code TEXT UNIQUE NOT NULL,      -- 6位专属短码 (如 TW8899)
		mission_type TEXT NOT NULL DEFAULT 'fleet_travel', -- fleet_travel(车队编队) / rescue(应急搜救) / activity(活动专线)
		points_count INTEGER DEFAULT 0,
		distance_km REAL DEFAULT 0.0,
		roadbook_json TEXT NOT NULL,          -- 标准途经点序列 JSON
		expire_at DATETIME,                   -- 有效期截止时间
		status TEXT DEFAULT 'active',         -- active(生效中) / closed(已归档关闭) / expired(已过期)
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	CREATE INDEX IF NOT EXISTS idx_team_code ON team_roadbooks(squad_code);
	CREATE INDEX IF NOT EXISTS idx_team_status ON team_roadbooks(status);
	`
	if _, err := publicDb.Exec(dictSchema); err != nil {
		return err
	}

	// 初始化预置数据字典 (仅在首次创建或空表时灌注工业级标准主数据)
	seedSystemDictionaries()
	seedPublicRoadbooks()



	return nil
}

// -----------------------------------------------------------------------------
// 字典主数据引擎初始化 (Master Data Seeding)
// 包含地理大区、地形地貌、场景模式、车辆准入与难度星级五大体系
// -----------------------------------------------------------------------------
func seedSystemDictionaries() {
	var count int
	_ = publicDb.QueryRow("SELECT COUNT(*) FROM system_dictionaries").Scan(&count)
	if count > 0 {
		return
	}

	type DItem struct {
		dType, code, label, desc string
		order                    int
		meta                     string
	}

	items := []DItem{
		// 1. 地理大区与省份字典 (Regions)
		{"region", "neimenggu", "内蒙古", "巴丹吉林沙漠、库布齐穿沙、腾格里、乌兰布和、大兴安岭原始林区", 1, `{"center":"40.8,111.7","radio":"438.500"}`},
		{"region", "xinjiang", "新疆", "独库公路、塔克拉玛干、阿尔金山、哈密大海道、白龙堆雅丹", 2, `{"center":"43.8,87.6","radio":"438.500"}`},
		{"region", "xizang", "西藏", "阿里大北线、克里雅古道、丙察察、萨普神山、双湖无人区", 3, `{"center":"29.6,91.1","radio":"433.000"}`},
		{"region", "qinghai", "青海", "可可西里外围、柴达木盆地、茫崖翡翠湖、俄博梁雅丹火星营地", 4, `{"center":"36.6,101.7","radio":"438.500"}`},
		{"region", "chuanxi", "川西", "格聂南线、贡嘎大环线、党岭葫芦海、洛克之路、甲根坝", 5, `{"center":"30.5,102.0","radio":"433.000"}`},
		{"region", "gansu", "甘肃", "河西走廊、祁连山冷龙岭、鸣沙山月牙泉、扎尕那大峡谷", 6, `{"center":"36.0,103.8","radio":"438.500"}`},
		{"region", "huabei", "华北", "塞罕坝林场、老掌沟大好河山、太行山挂壁公路、蔚县空中草原", 7, `{"center":"39.9,116.4","radio":"438.500"}`},
		{"region", "yunnan", "云南", "雨崩神瀑徒步、高黎贡山、怒江美丽公路、独龙江穿越", 8, `{"center":"25.0,102.7","radio":"433.000"}`},
		{"region", "dongbei", "东北大兴安岭", "呼伦贝尔中俄边防卡线、阿尔山天池、莫尔道嘎林海", 9, `{"center":"50.2,124.1","radio":"438.500"}`},

		// 2. 地形地貌字典 (Terrains)
		{"terrain", "sand_dune", "高大沙丘/刀锋", "大角度冲坡、滚刀锋、侧翻高危区，需降压放气至0.8bar并插高旗杆", 1, `{"danger_level":5}`},
		{"terrain", "sand_sea", "连绵流动沙海", "软沙易陷车，需匀速借势前行，禁止急踩刹车", 2, `{"danger_level":4}`},
		{"terrain", "gobi_gravel", "戈壁碎石路", "尖锐暗石丛生，极易爆胎扎胎，强制要求加厚全地形AT/MT胎", 3, `{"danger_level":3}`},
		{"terrain", "alpine_meadow", "高山草甸", "雨季极度泥泞湿滑，暗沟暗坑遍布，禁止单车轻易驶离主车辙", 4, `{"danger_level":3}`},
		{"terrain", "river_fording", "河道涉水", "暗流淘沙、进水熄火与底盘冲刷，过河前必须下水探测深度与流速", 5, `{"danger_level":4}`},
		{"terrain", "ice_rock", "冰雪岩石", "低附着力、暗冰与侧滑失控，需防滑链、脱困板与冰爪", 6, `{"danger_level":5}`},
		{"terrain", "yadan", "雅丹风蚀区", "地磁异常与地貌极度雷同，严禁单车深入，极易迷失方向", 7, `{"danger_level":5}`},
		{"terrain", "forest_mud", "原始森林泥泞", "烂泥深槽托底、倒木拦路，必备高位进气涉水喉与绞盘树抱带", 8, `{"danger_level":4}`},

		// 3. 运动场景与活动规范字典 (Categories)
		{"category", "offroad", "越野自驾 4x4", "重度非铺装与越野脱困，到站判定半径默认 120 米，颠簸自适应滤波", 1, `{"arrival_radius":120}`},
		{"category", "hiking", "山林重装徒步", "人行慢速山道，到站判定半径默认 30 米，微速高灵敏度平滑滤波", 2, `{"arrival_radius":30}`},
		{"category", "cycling", "山地骑行 MTB", "中速林道与公路，到站判定半径默认 50 米，弯道提前语音预警", 3, `{"arrival_radius":50}`},
		{"category", "thru", "无人区穿越", "极端荒野长距离远征，到站判定半径默认 200 米，双星互验防漂移", 4, `{"arrival_radius":200}`},
		{"category", "camping", "探险露营", "水源与避风营地重点标绘，到站判定半径默认 60 米", 5, `{"arrival_radius":60}`},
		{"category", "sar", "应急搜救协作", "搜救救援专线，到站判定半径默认 30 米，最高频打点与状态互联", 6, `{"arrival_radius":30}`},

		// 4. 车辆与装备准入规范字典 (Vehicle Requirements)
		{"vehicle_req", "suv_awd", "城市四驱 SUV", "承载式车身适时四驱，仅限平整砂石与初级非铺装路面", 1, `{"min_ground_clearance":200}`},
		{"vehicle_req", "at_tire", "标准硬派 AT 胎", "带大梁非承载车身、低速四驱(4L)与全地形AT胎", 2, `{"min_ground_clearance":220}`},
		{"vehicle_req", "dual_diff_lock", "双差速锁+绞盘必备", "前后机械差速锁、12000磅前绞盘、高强度底盘护板", 3, `{"min_ground_clearance":240}`},
		{"vehicle_req", "extreme_lifted", "重度升高+涉水喉", "升高2寸以上、氮气避震、加厚MT泥地胎与涉水喉", 4, `{"min_ground_clearance":260}`},
		{"vehicle_req", "satellite_phone_req", "强制卫星通信设备", "天通一号/北斗卫星电话、双备胎与50%冗余应急饮用水", 5, `{"emergency_water_days":3}`},

		// 5. 探险安全难度星级字典 (Difficulty)
		{"difficulty", "diff_1", "1星 (休闲观光)", "常规铺装或平整砂石路，手机信号全覆盖，城市SUV即可通行", 1, `{}`},
		{"difficulty", "diff_2", "2星 (初级越野)", "部分坑洼碎石，需具备基础非铺装驾驶经验", 2, `{}`},
		{"difficulty", "diff_3", "3星 (中级穿越)", "无手机信号覆盖，存在陷车打滑风险，建议双车结伴", 3, `{}`},
		{"difficulty", "diff_4", "4星 (硬派探险)", "恶劣大荒野、刀锋沙山与涉水暗流，强制配备差速锁与绞盘", 4, `{}`},
		{"difficulty", "diff_5", "5星 (极限无人区)", "生命禁区、极限脱困与自救考验，强制携带卫星电话与充足物资", 5, `{}`},
	}

	stmt, err := publicDb.Prepare(`
		INSERT OR IGNORE INTO system_dictionaries 
		(id, dict_type, dict_code, dict_label, dict_desc, sort_order, is_active, meta_json)
		VALUES (?, ?, ?, ?, ?, ?, 1, ?)`)
	if err != nil {
		return
	}
	defer stmt.Close()

	for _, item := range items {
		id := fmt.Sprintf("dict_%s_%s", item.dType, item.code)
		_, _ = stmt.Exec(id, item.dType, item.code, item.label, item.desc, item.order, item.meta)
	}
	log.Printf("[DICT] 系统五大基础数据字典 (大区/地形/场景/装备/难度) 预置完成")
}


func migrateAdminColumns() {
	rows, err := db.Query(`PRAGMA table_info(admins)`)
	if err != nil {
		return
	}
	defer rows.Close()

	hasRoleKey := false
	hasRole := false
	for rows.Next() {
		var cid int
		var name, typeStr string
		var notNull, pk int
		var dfltValue any
		if err := rows.Scan(&cid, &name, &typeStr, &notNull, &dfltValue, &pk); err == nil {
			if name == "role_key" {
				hasRoleKey = true
			}
			if name == "role" {
				hasRole = true
			}
		}
	}

	if !hasRoleKey {
		_, _ = db.Exec(`ALTER TABLE admins ADD COLUMN role_key TEXT NOT NULL DEFAULT 'super_admin'`)
		if hasRole {
			_, _ = db.Exec(`UPDATE admins SET role_key = role WHERE role IS NOT NULL AND role != ''`)
		}
		log.Printf("[MIGRATE] admins 表已成功自动补齐 role_key 字段")
	}
}

func migrateUserColumns() {
	rows, err := db.Query(`PRAGMA table_info(users)`)
	if err != nil {
		return
	}
	defer rows.Close()

	existing := make(map[string]bool)
	for rows.Next() {
		var cid int
		var name, typeStr string
		var notNull, pk int
		var dfltValue any
		if err := rows.Scan(&cid, &name, &typeStr, &notNull, &dfltValue, &pk); err == nil {
			existing[name] = true
		}
	}

	colsToAdd := map[string]string{
		"avatar_url":              "TEXT DEFAULT ''",
		"gender":                  "TEXT DEFAULT '保密'",
		"bio":                     "TEXT DEFAULT '心向山海，无畏前行'",
		"vehicle_model":           "TEXT DEFAULT '未登记'",
		"emergency_contact_name":  "TEXT DEFAULT ''",
		"emergency_contact_phone": "TEXT DEFAULT ''",
		"total_distance_m":        "REAL DEFAULT 0",
		"routes_count":            "INTEGER DEFAULT 0",
		"is_verified":             "INTEGER DEFAULT 0",
		"status":                  "INTEGER DEFAULT 1",
	}

	for col, colDef := range colsToAdd {
		if !existing[col] {
			_, _ = db.Exec(fmt.Sprintf(`ALTER TABLE users ADD COLUMN %s %s`, col, colDef))
		}
	}
}

// ============================================================================
// 3. 安全中间件、JWT 签发校验与权限判定
// ============================================================================

func withSecurityMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("[PANIC RECOVERED] %v", rec)
				writeJSON(w, http.StatusInternalServerError, map[string]any{
					"code":    500,
					"message": "服务器内部安全保护拦截",
				})
			}
		}()

		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Admin-Key")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		clientIP := extractClientIP(r)
		if !apiLimiter.allow(clientIP) {
			writeJSON(w, http.StatusTooManyRequests, map[string]any{
				"code":    429,
				"message": "请求过于频繁，请稍后再试",
			})
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, 15<<20)
		next(w, r)
	}
}

func extractClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func generateJWT(userID, account string) (string, error) {
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	claimsMap := map[string]any{
		"sub": userID,
		"acc": account,
		"exp": time.Now().Add(30 * 24 * time.Hour).Unix(),
	}
	claimsBytes, err := json.Marshal(claimsMap)
	if err != nil {
		return "", err
	}
	claims := base64.RawURLEncoding.EncodeToString(claimsBytes)
	unsigned := header + "." + claims

	mac := hmac.New(sha256.New, jwtSecret)
	mac.Write([]byte(unsigned))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return unsigned + "." + sig, nil
}

func verifyJWT(r *http.Request) (string, error) {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(auth, "Bearer ") {
		return "", fmt.Errorf("missing bearer token")
	}
	token := strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", fmt.Errorf("invalid token format")
	}

	unsigned := parts[0] + "." + parts[1]
	mac := hmac.New(sha256.New, jwtSecret)
	mac.Write([]byte(unsigned))
	expectedSig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(parts[2]), []byte(expectedSig)) {
		return "", fmt.Errorf("invalid token signature")
	}

	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", err
	}
	var claims map[string]any
	if err := json.Unmarshal(claimsBytes, &claims); err != nil {
		return "", err
	}
	exp, _ := claims["exp"].(float64)
	if time.Now().Unix() > int64(exp) {
		return "", fmt.Errorf("token expired")
	}
	userID, _ := claims["sub"].(string)
	if userID == "" {
		return "", fmt.Errorf("empty user id")
	}
	return userID, nil
}

func checkAdminRolePermission(r *http.Request, minLevel int) (*adminSessionInfo, bool) {
	// 1. 若携带合法的 X-Admin-Key，直接按最高超级管理权限 (level 100) 放行
	reqKey := strings.TrimSpace(r.Header.Get("X-Admin-Key"))
	if reqKey != "" && subtle.ConstantTimeCompare([]byte(reqKey), []byte(adminKey)) == 1 {
		return &adminSessionInfo{
			Token:       "master_root_key",
			AdminID:     "adm_root",
			Username:    "admin",
			DisplayName: "Master Root Key",
			RoleKey:     "super_admin",
			RoleLevel:   100,
		}, true
	}

	// 2. 检查 Header 中的 X-Admin-Session 或 Authorization Bearer 或 URL query token
	token := strings.TrimSpace(r.Header.Get("X-Admin-Session"))
	if token == "" {
		auth := strings.TrimSpace(r.Header.Get("Authorization"))
		if strings.HasPrefix(auth, "Bearer ") {
			token = strings.TrimPrefix(auth, "Bearer ")
		}
	}
	if token == "" {
		token = strings.TrimSpace(r.URL.Query().Get("token"))
	}
	if token != "" {
		sess := adminSessions.getSession(token)
		if sess != nil && sess.RoleLevel >= minLevel {
			return sess, true
		}
	}

	// 3. 检查 Web 会话 Cookie
	cookie, err := r.Cookie("tw_admin_session")
	if err == nil && cookie != nil {
		sess := adminSessions.getSession(cookie.Value)
		if sess != nil && sess.RoleLevel >= minLevel {
			return sess, true
		}
	}

	return nil, false
}

func getRoleLevel(roleKey string) int {
	var lvl int
	err := db.QueryRow(`SELECT level FROM admin_roles WHERE role_key = ?`, roleKey).Scan(&lvl)
	if err != nil {
		return 0
	}
	return lvl
}

func randomID(prefix string, byteLen int) string {
	b := make([]byte, byteLen)
	_, _ = rand.Read(b)
	return prefix + hex.EncodeToString(b)
}

func randomShareCode() string {
	const chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	var sb strings.Builder
	for i := 0; i < 6; i++ {
		sb.WriteByte(chars[int(b[i])%len(chars)])
	}
	return sb.String()
}

// ============================================================================
// 4. 移动端 App 业务接口
// ============================================================================

func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"status":  "ok",
		"service": "TerraWay Vault & OTA Server v0.7.7",
		"time":    time.Now().Format(time.RFC3339),
	})
}

func handleCheckUpdate(w http.ResponseWriter, r *http.Request) {
	row := db.QueryRow(`
		SELECT version_code, version_name, apk_url, apk_sha256, apk_size_mb,
		       changelog_zh, changelog_en, is_forced, release_date
		FROM app_releases
		ORDER BY version_code DESC
		LIMIT 1`)

	var (
		versionCode int
		versionName string
		apkURL      string
		apkSha256   string
		apkSizeMb   float64
		changelogZh string
		changelogEn string
		isForced    int
		releaseDate string
	)
	if err := row.Scan(
		&versionCode, &versionName, &apkURL, &apkSha256, &apkSizeMb,
		&changelogZh, &changelogEn, &isForced, &releaseDate,
	); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"code": 0,
			"data": map[string]any{
				"version_code": 20,
				"version_name": "0.7.7",
				"apk_url":      "",
				"is_forced":    false,
			},
		})
		return
	}

	// 强制锁定：凡有新版发布，对外下发的下载直链强制锁定为自建 VPS 高速直链，杜绝跳往 GitHub 404
	vpsDownloadLink := "https://api.terraway.cn/api/v1/app/download/latest"

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "ok",
		"data": map[string]any{
			"version_code": versionCode,
			"version_name": versionName,
			"apk_url":      vpsDownloadLink,
			"apk_sha256":   apkSha256,
			"apk_size_mb":  apkSizeMb,
			"changelog_zh": changelogZh,
			"changelog_en": changelogEn,
			"is_forced":    isForced == 1,
			"release_date": releaseDate,
		},
	})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"code": 405, "message": "Method Not Allowed"})
		return
	}

	var req struct {
		PhoneOrEmail string `json:"phone_or_email"`
		Password     string `json:"password"`
		Nickname     string `json:"nickname"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "请求格式错误"})
		return
	}
	account := strings.TrimSpace(req.PhoneOrEmail)
	if len(account) < 3 || len(req.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "账号需至少 3 位，密码需至少 6 位"})
		return
	}
	nickname := strings.TrimSpace(req.Nickname)
	if nickname == "" {
		nickname = account
	}

	hashBytes, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "密码安全加密失败"})
		return
	}

	userID := randomID("usr_", 12)
	now := time.Now().Format("2006-01-02 15:04:05")
	_, err = db.Exec(`
		INSERT INTO users (id, phone_or_email, password_hash, nickname, created_at)
		VALUES (?, ?, ?, ?, ?)`,
		userID, account, string(hashBytes), nickname, now,
	)
	if err != nil {
		writeJSON(w, http.StatusConflict, map[string]any{"code": 409, "message": "该账号已注册，请直接切换登录"})
		return
	}

	token, _ := generateJWT(userID, account)
	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "注册并连接云端保险箱成功",
		"data": map[string]any{
			"token":          token,
			"phone_or_email": account,
			"nickname":       nickname,
		},
	})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"code": 405, "message": "Method Not Allowed"})
		return
	}

	var req struct {
		PhoneOrEmail string `json:"phone_or_email"`
		Password     string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "请求格式错误"})
		return
	}
	account := strings.TrimSpace(req.PhoneOrEmail)

	var userID, passHash, nickname string
	var status int
	err := db.QueryRow(`
		SELECT id, password_hash, nickname, status FROM users WHERE phone_or_email = ?`, account,
	).Scan(&userID, &passHash, &nickname, &status)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(passHash), []byte(req.Password)) != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "账号或密码不正确"})
		return
	}
	if status == 0 {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "该账号已被停用，请联系客服处理"})
		return
	}

	token, _ := generateJWT(userID, account)
	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "登录云端保险箱成功",
		"data": map[string]any{
			"token":          token,
			"phone_or_email": account,
			"nickname":       nickname,
		},
	})
}

func handleUserPasswordChange(w http.ResponseWriter, r *http.Request) {
	userID, err := verifyJWT(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未登录"})
		return
	}

	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.NewPassword) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "新密码至少6位"})
		return
	}

	var currentHash string
	err = db.QueryRow(`SELECT password_hash FROM users WHERE id = ?`, userID).Scan(&currentHash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(currentHash), []byte(req.OldPassword)) != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "原密码输入错误"})
		return
	}

	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "加密失败"})
		return
	}

	_, _ = db.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, string(newHash), userID)
	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "密码修改成功！"})
}

func handleUserTicketSubmit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"code": 405, "message": "Method Not Allowed"})
		return
	}

	var req struct {
		Account     string `json:"account"`
		TicketType  string `json:"ticket_type"`
		ContactInfo string `json:"contact_info"`
		Message     string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Account == "" || req.Message == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "请填写完整账号与申诉内容"})
		return
	}

	ticketID := randomID("tkt_", 8)
	now := time.Now().Format("2006-01-02 15:04:05")
	tType := req.TicketType
	if tType == "" {
		tType = "password_reset"
	}

	_, err := db.Exec(`
		INSERT INTO user_tickets (id, user_account, ticket_type, contact_info, message, status, created_at)
		VALUES (?, ?, ?, ?, ?, 'pending', ?)`,
		ticketID, strings.TrimSpace(req.Account), tType, strings.TrimSpace(req.ContactInfo), strings.TrimSpace(req.Message), now,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "提交工单失败"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "申诉工单已送达！管理员查阅后将为您重置密码或回复联络。",
		"ticket":  ticketID,
	})
}

func handleUploadTracks(w http.ResponseWriter, r *http.Request) {
	userID, err := verifyJWT(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "请先登录云端账户"})
		return
	}

	var req struct {
		Tracks []map[string]any `json:"tracks"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "轨迹数据格式无效"})
		return
	}

	savedCount := 0
	totalAddedDist := 0.0
	for _, trk := range req.Tracks {
		trkID, _ := trk["id"].(string)
		if trkID == "" {
			trkID = randomID("trk_", 10)
		}
		safeID := filepath.Base(trkID)
		name, _ := trk["name"].(string)
		if name == "" {
			name = "未命名轨迹"
		}
		dist, _ := trk["dist"].(float64)
		totalAddedDist += dist
		pts, _ := trk["pts"].([]any)

		storagePath := filepath.Join(dataDir, "tracks", fmt.Sprintf("%s_%s.json.gz", userID, safeID))
		rawBytes, err := json.Marshal(trk)
		if err != nil || writeGzipFile(storagePath, rawBytes) != nil {
			continue
		}

		_, err = db.Exec(`
			INSERT OR REPLACE INTO user_tracks (id, user_id, name, distance_m, points_count, storage_path, uploaded_at)
			VALUES (?, ?, ?, ?, ?, ?, ?)`,
			safeID, userID, name, dist, len(pts), storagePath, time.Now().Format("2006-01-02 15:04:05"),
		)
		if err == nil {
			savedCount++
		}
	}

	if totalAddedDist > 0 {
		_, _ = db.Exec(`UPDATE users SET total_distance_m = total_distance_m + ? WHERE id = ?`, totalAddedDist, userID)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": fmt.Sprintf("已安全加密备份 %d 条轨迹至云端", savedCount),
		"count":   savedCount,
	})
}

func handleListTracks(w http.ResponseWriter, r *http.Request) {
	userID, err := verifyJWT(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "请先登录云端账户"})
		return
	}

	rows, err := db.Query(`
		SELECT storage_path FROM user_tracks WHERE user_id = ? ORDER BY uploaded_at DESC LIMIT 100`, userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "查询轨迹失败"})
		return
	}
	defer rows.Close()

	var result []map[string]any
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err == nil {
			if raw, err := readGzipFile(path); err == nil {
				var m map[string]any
				if json.Unmarshal(raw, &m) == nil {
					result = append(result, m)
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": result,
	})
}

func handleUploadRoadbooks(w http.ResponseWriter, r *http.Request) {
	userID, err := verifyJWT(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "请先登录云端账户"})
		return
	}

	var req struct {
		Roadbooks []map[string]any `json:"roadbooks"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "路书格式错误"})
		return
	}

	saved := 0
	for _, rb := range req.Roadbooks {
		rbID, _ := rb["id"].(string)
		if rbID == "" {
			rbID = randomID("rb_", 10)
		}
		safeID := filepath.Base(rbID)
		name, _ := rb["name"].(string)
		pts, _ := rb["points"].([]any)

		storagePath := filepath.Join(dataDir, "roadbooks", fmt.Sprintf("%s_%s.json.gz", userID, safeID))
		rawBytes, err := json.Marshal(rb)
		if err != nil || writeGzipFile(storagePath, rawBytes) != nil {
			continue
		}

		_, err = db.Exec(`
			INSERT OR REPLACE INTO user_roadbooks (id, user_id, name, points_count, storage_path, uploaded_at)
			VALUES (?, ?, ?, ?, ?, ?)`,
			safeID, userID, name, len(pts), storagePath, time.Now().Format("2006-01-02 15:04:05"),
		)
		if err == nil {
			saved++
		}
	}

	_, _ = db.Exec(`UPDATE users SET routes_count = (SELECT COUNT(*) FROM user_roadbooks WHERE user_id = ?) WHERE id = ?`, userID, userID)

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": fmt.Sprintf("成功备份 %d 条路书至云端", saved),
	})
}

func handleListRoadbooks(w http.ResponseWriter, r *http.Request) {
	userID, err := verifyJWT(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "请先登录云端账户"})
		return
	}

	rows, err := db.Query(`
		SELECT storage_path FROM user_roadbooks WHERE user_id = ? ORDER BY uploaded_at DESC LIMIT 100`, userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "读取路书失败"})
		return
	}
	defer rows.Close()

	var result []map[string]any
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err == nil {
			if raw, err := readGzipFile(path); err == nil {
				var m map[string]any
				if json.Unmarshal(raw, &m) == nil {
					result = append(result, m)
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": result,
	})
}

func handleShareRoadbook(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Roadbook map[string]any `json:"roadbook"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Roadbook == nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "无效的路书数据"})
		return
	}

	code := randomShareCode()
	name, _ := req.Roadbook["name"].(string)
	pts, _ := req.Roadbook["points"].([]any)
	storagePath := filepath.Join(dataDir, "roadbooks", fmt.Sprintf("share_%s.json.gz", code))

	rawBytes, err := json.Marshal(req.Roadbook)
	if err != nil || writeGzipFile(storagePath, rawBytes) != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "保存分享路书失败"})
		return
	}

	_, _ = db.Exec(`
		INSERT OR REPLACE INTO user_roadbooks (id, user_id, name, points_count, share_code, storage_path, uploaded_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		"share_"+code, "public_squad", name, len(pts), code, storagePath, time.Now().Format("2006-01-02 15:04:05"),
	)

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": map[string]any{
			"share_code": code,
		},
	})
}

func handleFetchRoadbookByCode(w http.ResponseWriter, r *http.Request) {
	code := strings.ToUpper(strings.TrimSpace(strings.TrimPrefix(r.URL.Path, "/api/v1/roadbook/fetch/")))
	if len(code) < 4 || len(code) > 12 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "无效的 6 位短码"})
		return
	}

	var path string
	err := db.QueryRow(`SELECT storage_path FROM user_roadbooks WHERE share_code = ? LIMIT 1`, code).Scan(&path)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"code": 404, "message": "未找到该短码对应的车队路书"})
		return
	}

	raw, err := readGzipFile(path)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"code": 404, "message": "路书文件不存在"})
		return
	}
	var rb map[string]any
	_ = json.Unmarshal(raw, &rb)
	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": rb,
	})
}

// ============================================================================
// 5. 管理员 Web 控制台页面与左侧树形导航 (/admin)
// ============================================================================

func handleAdminWeb(w http.ResponseWriter, r *http.Request) {
	clientIP := extractClientIP(r)

	if r.URL.Path == "/admin/logout" {
		cookie, _ := r.Cookie("tw_admin_session")
		if cookie != nil {
			adminSessions.revoke(cookie.Value)
		}
		http.SetCookie(w, &http.Cookie{
			Name:     "tw_admin_session",
			Value:    "",
			Path:     "/",
			MaxAge:   -1,
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
		})
		http.Redirect(w, r, "/admin", http.StatusSeeOther)
		return
	}

	if r.Method == http.MethodPost && r.URL.Path == "/admin/login" {
		if !adminLock.checkAllowed(clientIP) {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(renderAdminLoginPage("输错密码次数过多，该 IP 已被安全锁定 15 分钟！")))
			return
		}

		_ = r.ParseForm()
		userIn := strings.TrimSpace(r.FormValue("username"))
		passIn := strings.TrimSpace(r.FormValue("password"))

		// 1. 紧急救援通道 (Master Key)
		if subtle.ConstantTimeCompare([]byte(passIn), []byte(adminKey)) == 1 ||
			subtle.ConstantTimeCompare([]byte(userIn), []byte(adminKey)) == 1 {
			adminLock.recordSuccess(clientIP)
			token := adminSessions.createSession("adm_root", "admin", "超级管理员(Root)", "super_admin", 100)
			setAdminCookie(w, token)
			http.Redirect(w, r, "/admin", http.StatusSeeOther)
			return
		}

		// 2. admins 表账号核验
		var adminID, uName, passHash, dispName, roleKey string
		var isActive int
		err := db.QueryRow(`
			SELECT id, username, password_hash, display_name, role_key, is_active
			FROM admins WHERE username = ?`, userIn,
		).Scan(&adminID, &uName, &passHash, &dispName, &roleKey, &isActive)

		if err == nil && isActive == 1 && bcrypt.CompareHashAndPassword([]byte(passHash), []byte(passIn)) == nil {
			adminLock.recordSuccess(clientIP)
			_, _ = db.Exec(`UPDATE admins SET last_login_at = ? WHERE id = ?`, time.Now().Format("2006-01-02 15:04:05"), adminID)
			level := getRoleLevel(roleKey)
			token := adminSessions.createSession(adminID, uName, dispName, roleKey, level)
			setAdminCookie(w, token)
			http.Redirect(w, r, "/admin", http.StatusSeeOther)
			return
		}

		adminLock.recordFailed(clientIP)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(renderAdminLoginPage("账号或密码错误（默认管理员为 admin / 初始密钥）！")))
		return
	}

	sess, ok := checkAdminRolePermission(r, 10)
	if !ok {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(renderAdminLoginPage("")))
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(renderAdminDashboardHTML(sess.Token, sess.DisplayName, sess.RoleKey, sess.RoleLevel)))
}

func setAdminCookie(w http.ResponseWriter, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     "tw_admin_session",
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   7200,
	})
}

func renderAdminLoginPage(errMsg string) string {
	errHtml := ""
	if errMsg != "" {
		errHtml = fmt.Sprintf(`<div style="background:#331111;border:1px solid #ff4444;color:#ff8888;padding:10px;border-radius:6px;margin-bottom:16px;font-size:13px;">⚠️ %s</div>`, html.EscapeString(errMsg))
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>山海行 (TerraWay) 管理后台认证</title>
  <style>
    body { background: #080808; color: #eee; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; margin: 0; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
    .card { background: #121212; border: 1.5px solid #00ff66; border-radius: 10px; padding: 28px; width: 100%%; max-width: 380px; box-shadow: 0 4px 24px rgba(0,255,102,0.15); }
    h2 { margin: 0 0 6px 0; font-size: 20px; color: #fff; font-family: monospace; display: flex; align-items: center; gap: 8px; }
    p { margin: 0 0 20px 0; font-size: 12px; color: #888; }
    input[type=text], input[type=password] { width: 100%%; box-sizing: border-box; background: #1c1c1c; border: 1px solid #333; color: #fff; padding: 12px; border-radius: 6px; font-size: 14px; margin-bottom: 14px; outline: none; }
    input:focus { border-color: #00ff66; }
    button { width: 100%%; background: #00ff66; color: #000; border: none; padding: 12px; border-radius: 6px; font-size: 14px; font-weight: bold; cursor: pointer; }
    button:hover { background: #00dd55; }
    .badge { background: #003311; color: #00ff66; font-size: 10px; padding: 2px 6px; border-radius: 4px; font-weight: bold; }
    .hint { font-size: 11px; color: #666; margin-top: 12px; line-height: 1.4; }
  </style>
</head>
<body>
  <div class="card">
    <h2>🧭 山海行 <span class="badge">RBAC VAULT</span></h2>
    <p>TerraWay All-Terrain GPS · 独立多管理员认证</p>
    %s
    <form method="POST" action="/admin/login">
      <label style="font-size:12px;color:#aaa;display:block;margin-bottom:6px;">管理员账号 (Username):</label>
      <input type="text" name="username" placeholder="请输入管理员账号 (默认: admin)" required autofocus autocomplete="off">
      <label style="font-size:12px;color:#aaa;display:block;margin-bottom:6px;">管理员密码 (Password):</label>
      <input type="password" name="password" placeholder="请输入管理员密码" required autocomplete="off">
      <button type="submit">安全登录验证</button>
    </form>
    <div class="hint">💡 默认管理员为 <b>admin</b>，初始密码为服务器生成的管理员密钥。万一遗失密码，可直接输入 Master Key 紧急登入。</div>
  </div>

</body>
</html>`, errHtml)
}

// 采用经典「左侧多级树形导航栏 (Tree Sidebar)」布局的后台主界面
func renderAdminDashboardHTML(adminToken, adminDisplayName, roleKey string, roleLevel int) string {
	roleBadge := "超级管理员"
	if roleLevel == 50 {
		roleBadge = "系统管理员"
	} else if roleLevel == 20 {
		roleBadge = "业务操作员"
	} else if roleLevel == 10 {
		roleBadge = "线路审核员"
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>山海行 (TerraWay) 管理控制台</title>
  <style>
    * { box-sizing: border-box; }
    body { background: #0a0a0a; color: #e5e5e5; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; margin: 0; padding: 0; display: flex; height: 100vh; overflow: hidden; }

    /* 1. 左侧树形侧边栏 */
    .sidebar { width: 230px; background: #111111; border-right: 1px solid #222; display: flex; flex-direction: column; flex-shrink: 0; }
    .brand { padding: 18px 16px; border-bottom: 1px solid #222; display: flex; align-items: center; gap: 8px; }
    .brand h1 { margin: 0; font-size: 16px; color: #00ff66; font-family: monospace; }
    .brand span { font-size: 10px; background: #003311; color: #00ff66; padding: 2px 5px; border-radius: 4px; font-weight: bold; }

    .nav-tree { flex: 1; overflow-y: auto; padding: 12px 8px; }
    .tree-group-title { font-size: 11px; color: #666; font-weight: bold; padding: 10px 10px 4px 10px; text-transform: uppercase; letter-spacing: 0.5px; }
    .tree-node { display: flex; align-items: center; gap: 8px; padding: 8px 12px; color: #aaa; text-decoration: none; border-radius: 6px; font-size: 12.5px; margin-bottom: 2px; cursor: pointer; transition: all 0.15s; }
    .tree-node:hover { background: #1a1a1a; color: #fff; }
    .tree-node.active { background: #0c2d15; color: #00ff66; font-weight: bold; border-left: 3px solid #00ff66; }

    .sidebar-footer { padding: 14px 16px; border-top: 1px solid #222; font-size: 11.5px; color: #888; background: #0d0d0d; }
    .logout-btn { color: #ff6666; text-decoration: none; font-size: 11px; margin-left: 6px; }
    .logout-btn:hover { text-decoration: underline; }

    /* 2. 右侧主工作区 */
    .main-area { flex: 1; display: flex; flex-direction: column; overflow: hidden; background: #0a0a0a; }
    .top-bar { height: 50px; background: #111111; border-bottom: 1px solid #222; display: flex; align-items: center; justify-content: space-between; padding: 0 20px; flex-shrink: 0; }
    .breadcrumb { font-size: 13px; color: #fff; font-weight: bold; display: flex; align-items: center; gap: 6px; }
    .content-box { flex: 1; overflow-y: auto; padding: 20px; }

    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin-bottom: 20px; }
    .stat-card { background: #141414; border: 1px solid #262626; border-radius: 8px; padding: 14px; }
    .stat-val { font-size: 24px; font-weight: 900; color: #00ff66; margin-top: 4px; font-family: monospace; }
    .stat-label { font-size: 11.5px; color: #888; }

    .section { background: #141414; border: 1px solid #222; border-radius: 8px; padding: 18px; display: none; }
    .section.active { display: block; }
    h2 { font-size: 15px; margin: 0 0 14px 0; color: #fff; border-left: 3px solid #00ff66; padding-left: 8px; }

    table { width: 100%%; border-collapse: collapse; font-size: 12px; }
    th { text-align: left; padding: 9px; background: #181818; color: #888; font-weight: 600; border-bottom: 1px solid #262626; }
    td { padding: 9px; border-bottom: 1px solid #1c1c1c; }
    tr:hover { background: #181818; }

    .badge-code { background: #1a271d; color: #00ff66; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-weight: bold; border: 1px solid #004d1f; }
    .badge-role { background: #1e293b; color: #38bdf8; padding: 2px 6px; border-radius: 4px; font-size: 10.5px; }
    .badge-pending { background: #3b2005; color: #f59e0b; padding: 2px 6px; border-radius: 4px; font-size: 10.5px; }
    .badge-resolved { background: #0c2d15; color: #00ff66; padding: 2px 6px; border-radius: 4px; font-size: 10.5px; }
    .badge-verified { background: #261d08; color: #ffcc00; padding: 1px 5px; border-radius: 3px; font-size: 10px; font-weight: bold; }

    .btn-action { padding: 4px 8px; border-radius: 4px; font-size: 11px; cursor: pointer; border: none; }
    .btn-edit { background: #0066cc; color: #fff; margin-right: 4px; }
    .btn-del { background: #661111; color: #ff8888; }
    .btn-reset { background: #f59e0b; color: #000; font-weight: bold; margin-right: 4px; }
    .btn-submit { background: #00ff66; color: #000; font-weight: bold; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 12.5px; }
    .btn-submit:hover { background: #00dd55; }
    .btn-cancel { background: #333; color: #ccc; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 12.5px; margin-left: 8px; }

    .form-group { margin-bottom: 12px; }
    label { display: block; font-size: 12px; color: #aaa; margin-bottom: 5px; }
    input[type=text], input[type=password], input[type=number], select, textarea { width: 100%%; background: #1a1a1a; border: 1px solid #333; color: #fff; padding: 9px; border-radius: 6px; font-size: 12.5px; outline: none; }
    input:focus, select:focus, textarea:focus { border-color: #00ff66; }

    /* 3. 模态弹窗 (替代 prompt) */
    .modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.75); display: none; align-items: center; justify-content: center; z-index: 999; }
    .modal-card { background: #141414; border: 1.5px solid #00ff66; border-radius: 10px; width: 100%%; max-width: 440px; padding: 20px; box-shadow: 0 4px 24px rgba(0,0,0,0.8); }
    .modal-title { font-size: 15px; font-weight: bold; color: #fff; margin-bottom: 14px; }
  </style>
</head>
<body>
  <!-- 1. 左侧树形侧边栏 -->
  <div class="sidebar">
    <div class="brand">
      <h1>🧭 山海行</h1>
      <span>v0.7.7</span>
    </div>

    <div class="nav-tree">
      <div class="tree-group-title">系统大盘</div>
      <div class="tree-node active" onclick="switchNav('statsView', '系统概览 / 数据大盘', this)">📊 数据总览</div>

      <div class="tree-group-title">路线与路书 (三维独立体系)</div>
      <div class="tree-node" onclick="switchNav('publicRoadbooksView', '路书管理 / 公共精选路线 (已审核发布)', this); loadPublicRoadbooks();">🌐 公共精选路线</div>
      <div class="tree-node" onclick="switchNav('teamRoadbooksView', '路书管理 / 团队发布与协助 (6位短码)', this); loadTeamRoadbooks();">👥 团队发布协助</div>
      <div class="tree-node" onclick="switchNav('personalRoadbooksView', '路书管理 / 个人私有备份 (私密存储)', this); loadPersonalRoadbooks();">🔒 个人私有备份</div>

      <div class="tree-group-title">基础数据字典 (Master Data)</div>
      <div class="tree-node" onclick="switchNav('dictView', '字典主数据 / 地理大区与省份', this, 'region');">🏔️ 地理大区字典</div>
      <div class="tree-node" onclick="switchNav('dictView', '字典主数据 / 地形地貌特征', this, 'terrain');">🏜️ 地形地貌字典</div>
      <div class="tree-node" onclick="switchNav('dictView', '字典主数据 / 运动场景与模式', this, 'category');">🏃 运动场景字典</div>
      <div class="tree-node" onclick="switchNav('dictView', '字典主数据 / 车辆与装备准入规范', this, 'vehicle_req');">🚙 车辆装备准入</div>

      <div class="tree-group-title">用户与会员</div>
      <div class="tree-node" onclick="switchNav('usersView', '用户管理 / 探险者档案', this)">👥 会员档案</div>
      <div class="tree-node" onclick="switchNav('ticketsView', '用户管理 / 密码找回工单', this)">📨 找回密码工单</div>

      <div class="tree-group-title">权限与安全</div>
      <div class="tree-node" onclick="switchNav('adminsView', '管理权限 / 管理员团队', this)">🛡️ 管理员团队</div>
      <div class="tree-node" onclick="switchNav('rolesView', '管理权限 / 角色权限矩阵', this)">📜 角色权限矩阵</div>

      <div class="tree-group-title">发布与运维</div>
      <div class="tree-node" onclick="switchNav('releaseView', '运维发布 / App 版本下发', this)">🚀 App 版本发布</div>
    </div>

    <div class="sidebar-footer">
      <div>当前管理员: <b style="color:#00ff66;">%s</b></div>
      <div style="margin-top:4px;"><span class="badge-role">%s (L%d)</span> <a href="/admin/logout" class="logout-btn">退出</a></div>
    </div>
  </div>

  <!-- 2. 右侧主工作区 -->
  <div class="main-area">
    <div class="top-bar">
      <div class="breadcrumb" id="activeBreadcrumb">系统概览 / 数据大盘</div>
      <div style="font-size:11.5px;color:#888;">VPS 运行正常 · 数据库 WAL 就绪</div>
    </div>

    <div class="content-box">
      <!-- 视图 1: 数据大盘 -->
      <div id="statsView" class="section active">
        <div class="stats-grid">
          <div class="stat-card">
            <div class="stat-label">注册探险者总数</div>
            <div class="stat-val" id="statUsers">--</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">待处理申诉工单</div>
            <div class="stat-val" id="statPendingTickets" style="color:#f59e0b;">--</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">云端备份路书</div>
            <div class="stat-val" id="statRoadbooks">--</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">云端备份轨迹</div>
            <div class="stat-val" id="statTracks">--</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">当前在线发布版本</div>
            <div class="stat-val" id="statVersion" style="color:#ffaa00;">--</div>
          </div>
        </div>
      </div>

      <!-- 视图 2: 会员档案 -->
      <div id="usersView" class="section">
        <h2>探险者会员档案 (已接入丰富字段)</h2>
        <table>
          <thead>
            <tr>
              <th>账号</th>
              <th>呼号昵称</th>
              <th>座驾车型</th>
              <th>紧急联系人</th>
              <th>总里程</th>
              <th>认证</th>
              <th>状态</th>
              <th>注册时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="userTableBody">
            <tr><td colspan="9" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 3: 密码找回工单 -->
      <div id="ticketsView" class="section">
        <h2>用户密码找回与申诉工单</h2>
        <table>
          <thead>
            <tr>
              <th>编号</th>
              <th>账号</th>
              <th>类型</th>
              <th>联系方式</th>
              <th>申诉说明</th>
              <th>状态</th>
              <th>提交时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="ticketTableBody">
            <tr><td colspan="8" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 4A: 公共精选路线 (已审核发布) -->
      <div id="publicRoadbooksView" class="section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <div>
            <h2 style="margin:0;">🌐 公共精选路线管理 (全网开放/离线下载)</h2>
            <div style="font-size:12px;color:#888;margin-top:4px;">官方认证精选路网，支持大区/地形/场景筛选，支持一键导出 GPX 1.1 与导入入库</div>
          </div>
          <button class="btn-submit" onclick="openImportModal('public')">+ 导入 GPX / JSON 路线</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>路线标题</th>
              <th>大区归属</th>
              <th>地形地貌</th>
              <th>运动场景</th>
              <th>难度星级</th>
              <th>车辆装备准入</th>
              <th>总里程</th>
              <th>航点数</th>
              <th>全网下载</th>
              <th>发布时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="publicRoadbooksTableBody">
            <tr><td colspan="11" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 4B: 团队发布与协助 (6位短码协同) -->
      <div id="teamRoadbooksView" class="section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <div>
            <h2 style="margin:0;">👥 团队发布与协助专线 (Squad Code & Dispatch)</h2>
            <div style="font-size:12px;color:#888;margin-top:4px;">用于车队自驾编队、荒野救援与活动专线，带 6 位极简口令与时效自动归档</div>
          </div>
          <button class="btn-submit" onclick="openImportModal('team')">+ 发起团队协作 / 导入 GPX</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>车队 / 路线名称</th>
              <th>6位协作短码</th>
              <th>任务类型</th>
              <th>航点数</th>
              <th>总里程</th>
              <th>时效到期</th>
              <th>状态</th>
              <th>创建时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="teamRoadbooksTableBody">
            <tr><td colspan="9" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 4C: 个人私有备份 (私密存储) -->
      <div id="personalRoadbooksView" class="section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <div>
            <h2 style="margin:0;">🔒 个人私有路线备份 (Personal Vault)</h2>
            <div style="font-size:12px;color:#888;margin-top:4px;">探险者个人实地录制的私密轨迹，保护隐私，支持导出与配额维护</div>
          </div>
          <button class="btn-submit" onclick="openImportModal('personal')">+ 代导入个人备份</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>路线名称</th>
              <th>归属用户</th>
              <th>航点数</th>
              <th>备份时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="personalRoadbooksTableBody">
            <tr><td colspan="5" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 4D: 基础数据字典管理 (Master Data Engine) -->
      <div id="dictView" class="section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <div>
            <h2 style="margin:0;" id="dictTitle">📚 基础数据字典管理</h2>
            <div style="font-size:12px;color:#888;margin-top:4px;">高内聚低耦合：地理大区、地形地貌、场景模式与车辆装备要求独立动态管理</div>
          </div>
          <button class="btn-submit" onclick="openAddDictModal()">+ 新增字典项</button>
        </div>
        <div style="display:flex;gap:8px;margin-bottom:12px;" id="dictTabButtons">
          <button class="btn-edit" data-type="region" onclick="switchDictTab('region')">🏔️ 地理大区</button>
          <button class="btn-edit" data-type="terrain" onclick="switchDictTab('terrain')">🏜️ 地形地貌</button>
          <button class="btn-edit" data-type="category" onclick="switchDictTab('category')">🏃 场景模式</button>
          <button class="btn-edit" data-type="vehicle_req" onclick="switchDictTab('vehicle_req')">🚙 车辆装备</button>
          <button class="btn-edit" data-type="difficulty" onclick="switchDictTab('difficulty')">⭐ 难度星级</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>字典类型</th>
              <th>标识编码 (Code)</th>
              <th>显示名称 (Label)</th>
              <th>业务说明 / 安全规范</th>
              <th>排序号</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="dictTableBody">
            <tr><td colspan="7" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 5: 管理员团队 (用户要求：权限角色放到管理菜单下，支持下拉菜单选择) -->
      <div id="adminsView" class="section">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <h2 style="margin:0;">管理员团队 (RBAC 分级权限隔离)</h2>
          <button class="btn-submit" onclick="openAddAdminModal()">+ 添加新管理员</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>管理员账号</th>
              <th>职务/头衔</th>
              <th>角色等级</th>
              <th>职责说明</th>
              <th>状态</th>
              <th>创建时间</th>
              <th>最后登录</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="adminTableBody">
            <tr><td colspan="8" style="text-align:center;color:#666;">加载中...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 6: 角色权限矩阵 -->
      <div id="rolesView" class="section">
        <h2>法定角色权限分级矩阵 (不可越权)</h2>
        <table>
          <thead>
            <tr>
              <th>角色代码</th>
              <th>角色名称</th>
              <th>权限等级 (Level)</th>
              <th>权限范围与隔离定义</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="font-family:monospace;color:#00ff66;">super_admin</td>
              <td><b>超级总管理员</b></td>
              <td><span class="badge-role">Level 100</span></td>
              <td>全系统最高权限；可分配所有管理员角色、注销子管理员、发布新版本 App、操作所有业务。</td>
            </tr>
            <tr>
              <td style="font-family:monospace;color:#38bdf8;">admin</td>
              <td><b>系统管理员</b></td>
              <td><span class="badge-role">Level 50</span></td>
              <td>负责日常运营；可管理会员、处理工单、管理路书与发布版本；<b>受权限保护，低级别管理员绝不可越权修改其密码</b>。</td>
            </tr>
            <tr>
              <td style="font-family:monospace;color:#f59e0b;">operator</td>
              <td><b>业务操作员</b></td>
              <td><span class="badge-role">Level 20</span></td>
              <td>客服支持专员；查阅处理用户密码找回留言、协助一键重置用户临时密码、查看数据大盘。</td>
            </tr>
            <tr>
              <td style="font-family:monospace;color:#aaa;">auditor</td>
              <td><b>线路审核员</b></td>
              <td><span class="badge-role">Level 10</span></td>
              <td>越野路线审核领队；仅可查阅与审核公开路书与 6 位车队短码。</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 视图 7: App 版本发布推送 -->
      <div id="releaseView" class="section">
        <h2>发布新版本 App (发布后手机打开立即弹窗提醒升级)</h2>
        <form id="releaseForm" onsubmit="submitRelease(event)" style="max-width:650px;">
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
            <div class="form-group">
              <label>版本构建号 (Version Code, 如 20):</label>
              <input type="number" id="relCode" required placeholder="20">
            </div>
            <div class="form-group">
              <label>版本号 (Version Name, 如 0.7.5):</label>
              <input type="text" id="relName" required placeholder="0.7.7">
            </div>
          </div>
          <div class="form-group">
            <label>新版 APK 下载直链 (可填写 GitHub Release 直链):</label>
            <input type="text" id="relUrl" required placeholder="https://github.com/qingmi2001/terraway-app/releases/latest/download/terraway_gps_v0.7.7.apk">
          </div>
          <div class="form-group">
            <label>安装包大小 (MB):</label>
            <input type="number" step="0.1" id="relSize" placeholder="18.5" value="18.5">
          </div>
          <div class="form-group">
            <label>更新说明 (中文):</label>
            <textarea id="relChangelogZh" rows="3" placeholder="1. 升级左侧多级树形管理后台&#10;2. 修复超级管理员 admin 密码修改与添加交互"></textarea>
          </div>
          <div class="form-group">
            <label>更新说明 (英文 Changelog):</label>
            <textarea id="relChangelogEn" rows="2" placeholder="1. Redesigned tree sidebar admin UI&#10;2. Fixed admin management modal dialogs"></textarea>
          </div>
          <div class="form-group">
            <label style="display:inline-flex;align-items:center;gap:6px;cursor:pointer;">
              <input type="checkbox" id="relForced"> 强制更新模式 (用户必须升级后才能继续使用)
            </label>
          </div>
          <button type="submit" class="btn-submit">立即上架发布新版本</button>
        </form>
      </div>
    </div>
  </div>

  <!-- 3. 添加管理员 Modal 模态弹窗 (下拉菜单选择) -->
  <div id="addAdminModal" class="modal-overlay" style="display:none;">
    <div class="modal-card">
      <div class="modal-title">+ 添加新管理员账号</div>
      <div class="form-group">
        <label>管理员登录账号 (英文字母/数字):</label>
        <input type="text" id="addAdminUname" placeholder="例如: zhangsan" required>
      </div>
      <div class="form-group">
        <label>初始登录密码 (至少 6 位):</label>
        <input type="password" id="addAdminPass" placeholder="设置初始密码" required>
      </div>
      <div class="form-group">
        <label>标准管理头衔/职务 (下拉选择):</label>
        <select id="addAdminTitle">
          <option value="总系统架构师">总系统架构师</option>
          <option value="技术运维主管" selected>技术运维主管</option>
          <option value="探险活动运营专员">探险活动运营专员</option>
          <option value="越野路线审核领队">越野路线审核领队</option>
          <option value="客户支持管家">客户支持管家</option>
        </select>
      </div>
      <div class="form-group">
        <label>权限角色等级 (下拉选择):</label>
        <select id="addAdminRole">
          <option value="admin" selected>admin (系统管理员 · Level 50)</option>
          <option value="operator">operator (业务操作员 · Level 20)</option>
          <option value="auditor">auditor (线路审核员 · Level 10)</option>
          <option value="super_admin">super_admin (超级管理员 · Level 100)</option>
        </select>
      </div>
      <div style="margin-top:16px;text-align:right;">
        <button class="btn-submit" onclick="submitAddAdmin()">确认创建</button>
        <button class="btn-cancel" onclick="closeModal('addAdminModal')">取消</button>
      </div>
    </div>
  </div>

  <!-- 4. 重置管理员密码 / 改名 Modal -->
  <div id="editAdminModal" class="modal-overlay" style="display:none;">
    <div class="modal-card">
      <div class="modal-title">修改管理员密码与职务</div>
      <input type="hidden" id="editAdminId">
      <div class="form-group">
        <label>当前账号:</label>
        <input type="text" id="editAdminUname" disabled style="background:#222;color:#888;">
      </div>
      <div class="form-group">
        <label>设置新密码 (留空则不修改):</label>
        <input type="password" id="editAdminNewPass" placeholder="至少 6 位新密码">
      </div>
      <div class="form-group">
        <label>管理头衔/职务 (下拉选择):</label>
        <select id="editAdminTitle">
          <option value="总系统架构师">总系统架构师</option>
          <option value="技术运维主管">技术运维主管</option>
          <option value="探险活动运营专员">探险活动运营专员</option>
          <option value="越野路线审核领队">越野路线审核领队</option>
          <option value="客户支持管家">客户支持管家</option>
        </select>
      </div>
      <div style="margin-top:16px;text-align:right;">
        <button class="btn-submit" onclick="submitEditAdmin()">确认保存修改</button>
        <button class="btn-cancel" onclick="closeModal('editAdminModal')">取消</button>
      </div>
    </div>
  </div>
  <!-- 模态弹窗: 导入 GPX / JSON 路线 -->
  <div id="importRoadbookModal" class="modal-overlay" style="display:none;">
    <div class="modal-card" style="max-width:540px;">
      <div class="modal-title" style="color:#00ff66;">📥 导入路线数据 (支持标准 GPX 1.1 / JSON)</div>
      <form id="importRouteForm" onsubmit="submitImportRoute(event)">
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">导入目标体系:</label>
          <select id="impTargetType" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;" onchange="onImportTargetChange()">
            <option value="public">🌐 公共精选路线 (经审核发布至全网)</option>
            <option value="team">👥 团队发布协助 (生成 6 位协同短码)</option>
            <option value="personal">🔒 个人私有备份 (归属指定用户)</option>
          </select>
        </div>
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">路线标题 (留空则从 GPX 中自动读取):</label>
          <input type="text" id="impTitle" placeholder="如: 巴丹吉林必鲁图峰穿行线" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div id="publicExtraFields" style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px;">
          <div>
            <label style="display:block;font-size:11px;color:#aaa;margin-bottom:2px;">大区归属:</label>
            <select id="impRegion" style="width:100%%;padding:6px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;">
              <option value="neimenggu">内蒙古</option>
              <option value="xinjiang">新疆</option>
              <option value="xizang">西藏</option>
              <option value="chuanxi">川西</option>
              <option value="qinghai">青海</option>
              <option value="huabei">华北</option>
            </select>
          </div>
          <div>
            <label style="display:block;font-size:11px;color:#aaa;margin-bottom:2px;">运动场景:</label>
            <select id="impCategory" style="width:100%%;padding:6px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;">
              <option value="offroad">越野自驾 4x4</option>
              <option value="hiking">山林重装徒步</option>
              <option value="cycling">山地骑行 MTB</option>
              <option value="thru">无人区穿越</option>
            </select>
          </div>
        </div>
        <div id="teamExtraFields" style="display:none;margin-bottom:12px;">
          <label style="display:block;font-size:11px;color:#aaa;margin-bottom:2px;">6位团队短码 (留空自动生成):</label>
          <input type="text" id="impSquadCode" placeholder="如: TW8899" style="width:100%%;padding:6px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div id="personalExtraFields" style="display:none;margin-bottom:12px;">
          <label style="display:block;font-size:11px;color:#aaa;margin-bottom:2px;">归属用户账号/ID (默认 admin):</label>
          <input type="text" id="impTargetUser" placeholder="用户手机或 ID" style="width:100%%;padding:6px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div class="form-group" style="margin-bottom:14px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">选择 GPX 文件或直接粘贴文本:</label>
          <input type="file" id="impFile" accept=".gpx,.xml,.json" style="margin-bottom:6px;font-size:12px;color:#aaa;" onchange="handleFileSelect(event)">
          <textarea id="impGpxText" required rows="6" placeholder="粘贴标准 GPX 1.1 XML 或 TerraWay JSON 坐标点数据..." style="width:100%%;padding:8px;background:#1a1a1a;border:1px solid #333;color:#00ff66;font-family:monospace;font-size:11px;border-radius:6px;box-sizing:border-box;"></textarea>
        </div>
        <div style="display:flex;justify-content:flex-end;gap:10px;margin-top:16px;">
          <button type="button" class="btn-cancel" onclick="closeModal('importRoadbookModal')">取消</button>
          <button type="submit" class="btn-submit">解析并写入库</button>
        </div>
      </form>
    </div>
  </div>

  <!-- 模态弹窗: 新增/编辑数据字典项 -->
  <div id="dictModal" class="modal-overlay" style="display:none;">
    <div class="modal-card" style="max-width:480px;">
      <div class="modal-title" style="color:#00ff66;" id="dictModalTitle">⚙️ 新增字典主数据</div>
      <form id="dictForm" onsubmit="submitSaveDict(event)">
        <input type="hidden" id="dictItemType">
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">字典类型 (Category):</label>
          <select id="dictSelectType" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;">
            <option value="region">🏔️ 地理大区与省份 (region)</option>
            <option value="terrain">🏜️ 地形地貌特征 (terrain)</option>
            <option value="category">🏃 运动场景模式 (category)</option>
            <option value="vehicle_req">🚙 车辆与装备准入 (vehicle_req)</option>
            <option value="difficulty">⭐ 探险难度星级 (difficulty)</option>
          </select>
        </div>
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">标识编码 (Code, 如 neimenggu / sand_dune):</label>
          <input type="text" id="dictCode" required placeholder="英文字母或下划线" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">显示名称 (Label, 如 内蒙古 / 流动沙丘):</label>
          <input type="text" id="dictLabel" required placeholder="界面友好显示名称" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div class="form-group" style="margin-bottom:12px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">业务说明 / 规范要求:</label>
          <textarea id="dictDesc" rows="3" placeholder="如通行准入建议、救援通联频点或到站半径..." style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;"></textarea>
        </div>
        <div class="form-group" style="margin-bottom:14px;">
          <label style="display:block;font-size:12px;color:#aaa;margin-bottom:4px;">显示排序号 (越小越靠前):</label>
          <input type="number" id="dictSort" value="10" style="width:100%%;padding:8px;background:#1e1e1e;border:1px solid #333;color:#fff;border-radius:6px;box-sizing:border-box;">
        </div>
        <div style="display:flex;justify-content:flex-end;gap:10px;margin-top:16px;">
          <button type="button" class="btn-cancel" onclick="closeModal('dictModal')">取消</button>
          <button type="submit" class="btn-submit">保存字典项</button>
        </div>
      </form>
    </div>
  </div>


  <!-- 5. 工单处理并重置密码 Modal -->
  <div id="resolveTicketModal" class="modal-overlay" style="display:none;">
    <div class="modal-card">
      <div class="modal-title">处理工单并重置用户密码</div>
      <input type="hidden" id="ticketId">
      <div class="form-group">
        <label>申诉账号:</label>
        <input type="text" id="ticketAccount" disabled style="background:#222;color:#888;">
      </div>
      <div class="form-group">
        <label>重置临时密码 (留空则不重置):</label>
        <input type="text" id="ticketTempPass" value="12345678">
      </div>
      <div class="form-group">
        <label>处理回复说明:</label>
        <input type="text" id="ticketReply" value="已协助重置密码为 12345678，请尽快登录修改">
      </div>
      <div style="margin-top:16px;text-align:right;">
        <button class="btn-submit" onclick="submitResolveTicket()">完成处理</button>
        <button class="btn-cancel" onclick="closeModal('resolveTicketModal')">取消</button>
      </div>
    </div>
  </div>

  <script>
    var adminSessionToken = "%s";
    var currentAdminLevel = %d;
    var currentDictType = 'region';

    // 核心统一 API 请求封装 (双重鉴权保证: Header Token + Cookie)
    async function apiFetch(url, options) {
      options = options || {};
      options.headers = options.headers || {};
      if (adminSessionToken) {
        options.headers['X-Admin-Session'] = adminSessionToken;
      }
      options.credentials = 'include';
      try {
        const res = await fetch(url, options);
        if (res.status === 401) {
          console.warn('登录会话过期或未授权');
        }
        return res;
      } catch (err) {
        console.error('网络请求失败:', url, err);
        throw err;
      }
    }

    // 经典树形导航切换逻辑 (双保险: class + inline display)
    function switchNav(viewId, breadcrumbText, el, dictType) {
      try {
        document.querySelectorAll('.tree-node').forEach(function(n) { 
          n.classList.remove('active'); 
        });
        document.querySelectorAll('.section').forEach(function(s) { 
          s.classList.remove('active'); 
          s.style.display = 'none';
        });
        if (el) el.classList.add('active');
        const targetSec = document.getElementById(viewId);
        if (targetSec) {
          targetSec.classList.add('active');
          targetSec.style.display = 'block';
        }
        const bc = document.getElementById('activeBreadcrumb');
        if (bc && breadcrumbText) {
          bc.innerText = breadcrumbText;
        }

        // 切换视图时自适应触发数据拉取
        if (viewId === 'statsView') {
          loadStats();
        } else if (viewId === 'publicRoadbooksView') {
          loadPublicRoadbooks();
        } else if (viewId === 'teamRoadbooksView') {
          loadTeamRoadbooks();
        } else if (viewId === 'personalRoadbooksView') {
          loadPersonalRoadbooks();
        } else if (viewId === 'dictView') {
          switchDictTab(dictType || 'region');
        } else if (viewId === 'usersView') {
          loadUsers();
        } else if (viewId === 'ticketsView') {
          loadTickets();
        } else if (viewId === 'adminsView') {
          loadAdmins();
        }
      } catch (err) {
        console.error('switchNav 导航切换异常:', err);
      }
    }

    // 字典分类标签切换
    function switchDictTab(dType) {
      currentDictType = dType || 'region';
      document.querySelectorAll('#dictTabButtons button').forEach(function(b) {
        if (b.getAttribute('data-type') === currentDictType) {
          b.style.borderColor = '#00ff66';
          b.style.color = '#00ff66';
          b.style.background = '#0c2d15';
        } else {
          b.style.borderColor = '#333';
          b.style.color = '#aaa';
          b.style.background = '#1a1a1a';
        }
      });
      loadDictItems(currentDictType);
    }

    // 通用弹窗显示/隐藏控制
    function openModal(id) {
      const el = document.getElementById(id);
      if (el) el.style.display = 'flex';
    }

    function closeModal(id) {
      const el = document.getElementById(id);
      if (el) el.style.display = 'none';
    }

    // 1. 系统概览数据大盘
    async function loadStats() {
      try {
        const res = await apiFetch('/api/v1/admin/stats');
        const data = await res.json();
        if (data.code === 0 && data.data) {
          if (document.getElementById('statUsers')) document.getElementById('statUsers').innerText = data.data.total_users;
          if (document.getElementById('statPendingTickets')) document.getElementById('statPendingTickets').innerText = data.data.pending_tickets;
          if (document.getElementById('statRoadbooks')) document.getElementById('statRoadbooks').innerText = data.data.total_roadbooks;
          if (document.getElementById('statTracks')) document.getElementById('statTracks').innerText = data.data.total_tracks;
          if (document.getElementById('statVersion')) document.getElementById('statVersion').innerText = data.data.latest_version || '0.7.7';
        }
      } catch (e) {
        console.error('loadStats 异常:', e);
      }
    }

    // 2. 探险者档案列表
    async function loadUsers() {
      const tbody = document.getElementById('userTableBody');
      if (!tbody) return;
      try {
        const res = await apiFetch('/api/v1/admin/users');
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(u) {
            var statusTag = u.status === 1 ? '<span class="badge-active">正常</span>' : '<span class="badge-inactive">封禁</span>';
            var distKm = (u.total_distance_m / 1000).toFixed(1);
            return '<tr>' +
              '<td style="font-weight:bold;color:#fff;">' + u.nickname + '</td>' +
              '<td style="font-family:monospace;color:#38bdf8;">' + u.phone_or_email + '</td>' +
              '<td>' + (u.vehicle_model || '未登记') + '</td>' +
              '<td>' + (u.emergency_contact_phone ? u.emergency_contact_name + ' (' + u.emergency_contact_phone + ')' : '--') + '</td>' +
              '<td style="color:#00ff66;">' + distKm + ' km</td>' +
              '<td>' + (u.is_verified ? '<span class="badge-verified">已实名</span>' : '<span style="color:#666;">未认证</span>') + '</td>' +
              '<td>' + statusTag + '</td>' +
              '<td style="color:#888;">' + (u.created_at || '--') + '</td>' +
              '<td>' +
                '<button class="btn-action btn-edit" onclick="promptResetPassword(\'' + u.id + '\', \'' + u.nickname + '\')">重设密码</button> ' +
                (u.status === 1 ?
                  '<button class="btn-action btn-del" style="color:#f59e0b;" onclick="toggleUserStatus(\'' + u.id + '\', 0)">封禁</button>' :
                  '<button class="btn-action btn-edit" style="color:#00ff66;" onclick="toggleUserStatus(\'' + u.id + '\', 1)">解封</button>') +
              '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:#666;">暂无注册探险者数据</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    async function promptResetPassword(uid, uname) {
      const newPass = prompt('请输入用户【' + uname + '】的新登录密码:');
      if (!newPass || newPass.trim() === '') return;
      try {
        const res = await apiFetch('/api/v1/admin/user/update', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({user_id: uid, new_password: newPass.trim()})
        });
        const d = await res.json();
        alert(d.message);
        loadUsers();
      } catch (e) {
        alert('修改失败: ' + e);
      }
    }

    async function toggleUserStatus(uid, newStatus) {
      const actionName = newStatus === 1 ? '解封' : '封禁';
      if (!confirm('确定要' + actionName + '该探险者账号吗？')) return;
      try {
        const res = await apiFetch('/api/v1/admin/user/update', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({user_id: uid, status: newStatus})
        });
        const d = await res.json();
        alert(d.message);
        loadUsers();
      } catch (e) {
        alert('操作失败: ' + e);
      }
    }

    // 3. 找回密码工单列表
    async function loadTickets() {
      const tbody = document.getElementById('ticketTableBody');
      if (!tbody) return;
      try {
        const res = await apiFetch('/api/v1/admin/tickets');
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(t) {
            var stTag = t.status === 'resolved' ? '<span class="badge-resolved">已办结</span>' : '<span class="badge-pending">待处理</span>';
            var opBtn = t.status === 'pending' ?
              '<button class="btn-action btn-submit" style="font-size:11px;padding:3px 8px;" onclick="resolveTicket(\'' + t.id + '\', \'' + t.user_account + '\')">重置密码并办结</button>' :
              '<span style="color:#666;">无</span>';
            return '<tr>' +
              '<td style="font-family:monospace;color:#fff;">' + t.user_account + '</td>' +
              '<td>' + t.contact_info + '</td>' +
              '<td style="color:#aaa;max-width:280px;">' + t.message + '</td>' +
              '<td style="color:#888;">' + (t.created_at || '--') + '</td>' +
              '<td>' + stTag + '</td>' +
              '<td style="color:#aaa;">' + (t.admin_reply || '--') + '</td>' +
              '<td>' + opBtn + '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#666;">暂无待处理申诉工单</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    async function resolveTicket(ticketId, account) {
      const tempPass = prompt('请输入为用户【' + account + '】重设的临时密码:');
      if (!tempPass || tempPass.trim() === '') return;
      const replyMsg = prompt('请输入答复说明 (将随工单反馈给用户):', '您的密码已重设为: ' + tempPass.trim() + '，请尽快登入修改。');
      try {
        const res = await apiFetch('/api/v1/admin/ticket/resolve', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            ticket_id: ticketId,
            new_password: tempPass.trim(),
            admin_reply: replyMsg ? replyMsg.trim() : ''
          })
        });
        const d = await res.json();
        alert(d.message);
        loadTickets();
        loadStats();
      } catch (e) {
        alert('处理异常: ' + e);
      }
    }

    // 4. 公共精选路线列表
    async function loadPublicRoadbooks() {
      const tbody = document.getElementById('publicRoadbooksTableBody');
      if (!tbody) return;
      tbody.innerHTML = '<tr><td colspan="11" style="text-align:center;color:#666;">正在加载公共精选路线...</td></tr>';
      try {
        const res = await apiFetch('/api/v1/roadbook/public/list?page_size=100');
        const data = await res.json();
        if (data.code === 200 && data.data && data.data.items && data.data.items.length > 0) {
          tbody.innerHTML = data.data.items.map(function(r) {
            return '<tr>' +
              '<td style="font-weight:bold;color:#fff;">' + r.title + '</td>' +
              '<td><span class="badge-role">' + r.region + '</span></td>' +
              '<td style="color:#aaa;">' + r.terrain + '</td>' +
              '<td><span class="badge-code">' + r.category + '</span></td>' +
              '<td style="color:#f59e0b;">' + '⭐'.repeat(r.difficulty || 3) + '</td>' +
              '<td style="color:#aaa;">' + r.vehicle_req + '</td>' +
              '<td style="color:#00ff66;">' + r.distance_km + ' km</td>' +
              '<td style="color:#38bdf8;">' + r.points_count + ' 点</td>' +
              '<td style="color:#a855f7;">' + r.downloads_count + ' 次</td>' +
              '<td style="color:#666;font-size:11px;">' + (r.created_at ? r.created_at.slice(0, 10) : '') + '</td>' +
              '<td>' +
                '<button class="btn-action btn-edit" onclick="exportRoute(\'public\', \'' + r.id + '\', \'gpx\')">📥 GPX</button> ' +
                '<button class="btn-action btn-edit" onclick="exportRoute(\'public\', \'' + r.id + '\', \'json\')">JSON</button> ' +
                '<button class="btn-action btn-del" onclick="deleteRoute(\'public\', \'' + r.id + '\')">删除</button>' +
              '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="11" style="text-align:center;color:#666;">暂无审核发布的公共路线，请点击右上角导入</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="11" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    // 5. 团队协助路线列表
    async function loadTeamRoadbooks() {
      const tbody = document.getElementById('teamRoadbooksTableBody');
      if (!tbody) return;
      tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:#666;">正在加载团队协助路线...</td></tr>';
      try {
        const res = await apiFetch('/api/v1/admin/roadbooks/team');
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(r) {
            return '<tr>' +
              '<td style="font-weight:bold;color:#fff;">' + r.team_name + '</td>' +
              '<td><span class="badge-code" style="font-size:13px;padding:3px 8px;letter-spacing:1px;">' + r.squad_code + '</span></td>' +
              '<td><span class="badge-role">' + r.mission_type + '</span></td>' +
              '<td style="color:#38bdf8;">' + r.points_count + ' 点</td>' +
              '<td style="color:#00ff66;">' + r.distance_km + ' km</td>' +
              '<td style="color:#f59e0b;font-size:11px;">' + (r.expire_at ? r.expire_at.slice(0, 16) : '永久有效') + '</td>' +
              '<td><span class="badge-resolved">' + r.status + '</span></td>' +
              '<td style="color:#666;font-size:11px;">' + (r.created_at ? r.created_at.slice(0, 10) : '') + '</td>' +
              '<td>' +
                '<button class="btn-action btn-edit" onclick="exportRoute(\'team\', \'' + r.id + '\', \'gpx\')">📥 GPX</button> ' +
                '<button class="btn-action btn-del" onclick="deleteRoute(\'team\', \'' + r.id + '\')">删除</button>' +
              '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:#666;">暂无团队协助路线，点击右上角发起</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    // 6. 个人私有备份列表
    async function loadPersonalRoadbooks() {
      const tbody = document.getElementById('personalRoadbooksTableBody');
      if (!tbody) return;
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#666;">正在加载个人备份列表...</td></tr>';
      try {
        const res = await apiFetch('/api/v1/admin/roadbooks');
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(r) {
            return '<tr>' +
              '<td style="font-weight:bold;color:#fff;">' + r.name + '</td>' +
              '<td style="color:#38bdf8;">' + r.user_id + '</td>' +
              '<td style="color:#00ff66;">' + r.points_count + ' 点</td>' +
              '<td style="color:#aaa;">' + r.uploaded_at + '</td>' +
              '<td>' +
                '<button class="btn-action btn-edit" onclick="exportRoute(\'personal\', \'' + r.id + '\', \'gpx\')">📥 GPX</button> ' +
                '<button class="btn-action btn-del" onclick="deleteRoute(\'personal\', \'' + r.id + '\')">删除</button>' +
              '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#666;">暂无探险者个人备份</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    // 7. 基础数据字典项目列表
    async function loadDictItems(dType) {
      currentDictType = dType || 'region';
      const titleEl = document.getElementById('dictTitle');
      if (titleEl) {
        const typeLabels = {
          'region': '🏔️ 地理大区与省份字典',
          'terrain': '🏜️ 地形地貌特征字典',
          'category': '🏃 运动场景与模式字典',
          'vehicle_req': '🚙 车辆与装备准入规范字典',
          'difficulty': '⭐ 探险难度星级字典'
        };
        titleEl.innerText = typeLabels[currentDictType] || ('📚 基础数据字典管理 · ' + currentDictType.toUpperCase());
      }

      const tbody = document.getElementById('dictTableBody');
      if (!tbody) return;
      tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#666;">正在加载字典项...</td></tr>';
      try {
        const res = await apiFetch('/api/v1/dict/list?type=' + encodeURIComponent(currentDictType));
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(d) {
            return '<tr>' +
              '<td style="font-family:monospace;color:#38bdf8;">' + d.dict_type + '</td>' +
              '<td style="font-family:monospace;color:#00ff66;">' + d.dict_code + '</td>' +
              '<td style="font-weight:bold;color:#fff;">' + d.dict_label + '</td>' +
              '<td style="color:#aaa;max-width:320px;">' + (d.dict_desc || '--') + '</td>' +
              '<td style="color:#f59e0b;">' + d.sort_order + '</td>' +
              '<td><span class="badge-resolved">' + (d.is_active ? '启用' : '停用') + '</span></td>' +
              '<td>' +
                '<button class="btn-action btn-edit" onclick="editDictItem(\'' + d.dict_type + '\', \'' + d.dict_code + '\', \'' + d.dict_label + '\', \'' + (d.dict_desc || '').replace(/'/g, "\\'") + '\', ' + d.sort_order + ')">编辑</button> ' +
                '<button class="btn-action btn-del" onclick="deleteDictItem(\'' + d.id + '\')">删除</button>' +
              '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#666;">暂无该分类的字典项，点击右上角新增</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    // 8. 管理员团队列表
    async function loadAdmins() {
      const tbody = document.getElementById('adminTableBody');
      if (!tbody) return;
      try {
        const res = await apiFetch('/api/v1/admin/admins');
        const data = await res.json();
        if (data.code === 0 && data.data && data.data.length > 0) {
          tbody.innerHTML = data.data.map(function(a) {
            var stTag = a.is_active === 1 ? '<span class="badge-resolved">启用</span>' : '<span class="badge-inactive">停用</span>';
            var isRoot = a.username === 'admin';
            var opBtns = '<button class="btn-action btn-edit" onclick="openEditAdminModal(\'' + a.id + '\', \'' + a.username + '\', \'' + a.display_name + '\', \'' + a.role_key + '\')">修改</button> ';
            if (!isRoot && currentAdminLevel >= 100) {
              opBtns += '<button class="btn-action btn-del" onclick="deleteAdmin(\'' + a.id + '\', \'' + a.username + '\')">删除</button>';
            }
            return '<tr>' +
              '<td style="font-family:monospace;font-weight:bold;color:#fff;">' + a.username + '</td>' +
              '<td style="color:#00ff66;">' + a.display_name + '</td>' +
              '<td><span class="badge-role">' + a.role_name + ' (L' + a.role_level + ')</span></td>' +
              '<td style="color:#aaa;max-width:260px;">' + (a.description || '--') + '</td>' +
              '<td>' + stTag + '</td>' +
              '<td style="color:#888;">' + (a.created_at || '--') + '</td>' +
              '<td style="color:#888;">' + (a.last_login_at || '尚未登录') + '</td>' +
              '<td>' + opBtns + '</td>' +
            '</tr>';
          }).join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:#666;">暂无管理员数据</td></tr>';
        }
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:#ff6666;">加载失败: ' + e + '</td></tr>';
      }
    }

    // 弹窗交互：打开路线导入 Modal
    function openImportModal(targetType) {
      if (document.getElementById('impTargetType')) document.getElementById('impTargetType').value = targetType || 'public';
      if (document.getElementById('impTitle')) document.getElementById('impTitle').value = '';
      if (document.getElementById('impGpxText')) document.getElementById('impGpxText').value = '';
      onImportTargetChange();
      openModal('importRoadbookModal');
    }

    function onImportTargetChange() {
      var sel = document.getElementById('impTargetType');
      if (!sel) return;
      var t = sel.value;
      var pub = document.getElementById('publicExtraFields');
      var team = document.getElementById('teamExtraFields');
      var per = document.getElementById('personalExtraFields');
      if (pub) pub.style.display = (t === 'public' ? 'grid' : 'none');
      if (team) team.style.display = (t === 'team' ? 'block' : 'none');
      if (per) per.style.display = (t === 'personal' ? 'block' : 'none');
    }

    function handleFileSelect(evt) {
      var file = evt.target.files[0];
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function(e) {
        if (document.getElementById('impGpxText')) {
          document.getElementById('impGpxText').value = e.target.result;
        }
      };
      reader.readAsText(file);
    }

    async function submitImportRoute(evt) {
      evt.preventDefault();
      var tType = document.getElementById('impTargetType') ? document.getElementById('impTargetType').value : 'public';
      var title = document.getElementById('impTitle') ? document.getElementById('impTitle').value.trim() : '';
      var gpxText = document.getElementById('impGpxText') ? document.getElementById('impGpxText').value.trim() : '';
      var reg = document.getElementById('impRegion') ? document.getElementById('impRegion').value : '';
      var cat = document.getElementById('impCategory') ? document.getElementById('impCategory').value : '';
      var code = document.getElementById('impSquadCode') ? document.getElementById('impSquadCode').value.trim() : '';
      var user = document.getElementById('impTargetUser') ? document.getElementById('impTargetUser').value.trim() : '';

      if (!gpxText) {
        alert('请选择GPX文件或粘贴路线内容！');
        return;
      }

      var payload = {
        target_type: tType,
        title: title,
        content: gpxText,
        region: reg,
        category: cat,
        squad_code: code,
        user_id: user
      };

      try {
        const res = await apiFetch('/api/v1/admin/roadbooks/import', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        alert(data.message);
        if (data.code === 0) {
          closeModal('importRoadbookModal');
          if (tType === 'public') loadPublicRoadbooks();
          else if (tType === 'team') loadTeamRoadbooks();
          else if (tType === 'personal') loadPersonalRoadbooks();
          loadStats();
        }
      } catch (e) {
        alert('导入发生异常: ' + e);
      }
    }

    // 路线导出与删除
    function exportRoute(type, id, format) {
      var url = '/api/v1/admin/roadbooks/export?type=' + encodeURIComponent(type) + '&id=' + encodeURIComponent(id) + '&format=' + encodeURIComponent(format);
      if (adminSessionToken) {
        url += '&token=' + encodeURIComponent(adminSessionToken);
      }
      window.open(url, '_blank');
    }

    async function deleteRoute(type, id) {
      if (!confirm('确定彻底删除该条路线吗？此操作无法撤销！')) return;
      try {
        const res = await apiFetch('/api/v1/admin/roadbooks/delete', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({type: type, id: id})
        });
        const d = await res.json();
        alert(d.message);
        if (type === 'public') loadPublicRoadbooks();
        else if (type === 'team') loadTeamRoadbooks();
        else if (type === 'personal') loadPersonalRoadbooks();
        loadStats();
      } catch (e) {
        alert('删除失败: ' + e);
      }
    }

    // 字典新增/编辑
    function openAddDictModal() {
      if (document.getElementById('dictModalTitle')) document.getElementById('dictModalTitle').innerText = '⚙️ 新增字典主数据';
      if (document.getElementById('dictSelectType')) document.getElementById('dictSelectType').value = currentDictType;
      if (document.getElementById('dictCode')) {
        document.getElementById('dictCode').value = '';
        document.getElementById('dictCode').readOnly = false;
      }
      if (document.getElementById('dictLabel')) document.getElementById('dictLabel').value = '';
      if (document.getElementById('dictDesc')) document.getElementById('dictDesc').value = '';
      if (document.getElementById('dictSort')) document.getElementById('dictSort').value = '10';
      openModal('dictModal');
    }

    function editDictItem(type, code, label, desc, sort) {
      if (document.getElementById('dictModalTitle')) document.getElementById('dictModalTitle').innerText = '⚙️ 编辑字典主数据';
      if (document.getElementById('dictSelectType')) document.getElementById('dictSelectType').value = type;
      if (document.getElementById('dictCode')) {
        document.getElementById('dictCode').value = code;
        document.getElementById('dictCode').readOnly = true;
      }
      if (document.getElementById('dictLabel')) document.getElementById('dictLabel').value = label;
      if (document.getElementById('dictDesc')) document.getElementById('dictDesc').value = desc;
      if (document.getElementById('dictSort')) document.getElementById('dictSort').value = sort;
      openModal('dictModal');
    }

    async function submitSaveDict(evt) {
      evt.preventDefault();
      var dType = document.getElementById('dictSelectType').value;
      var code = document.getElementById('dictCode').value.trim();
      var label = document.getElementById('dictLabel').value.trim();
      var desc = document.getElementById('dictDesc').value.trim();
      var sort = parseInt(document.getElementById('dictSort').value) || 10;

      try {
        const res = await apiFetch('/api/v1/admin/dict/save', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            dict_type: dType,
            dict_code: code,
            dict_label: label,
            dict_desc: desc,
            sort_order: sort
          })
        });
        const d = await res.json();
        alert(d.message);
        if (d.code === 0) {
          closeModal('dictModal');
          loadDictItems(dType);
        }
      } catch (e) {
        alert('保存失败: ' + e);
      }
    }

    async function deleteDictItem(dictId) {
      if (!confirm('确定删除该字典条目吗？若该条目已在路书中被引用可能影响筛选显示！')) return;
      try {
        const res = await apiFetch('/api/v1/admin/dict/delete', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({id: dictId})
        });
        const d = await res.json();
        alert(d.message);
        loadDictItems(currentDictType);
      } catch (e) {
        alert('删除失败: ' + e);
      }
    }

    // 管理员管理
    function openAddAdminModal() {
      if (currentAdminLevel < 100) {
        alert('仅超级管理员 (Level 100) 具备添加新管理员权限！');
        return;
      }
      if (document.getElementById('addAdminUname')) document.getElementById('addAdminUname').value = '';
      if (document.getElementById('addAdminPass')) document.getElementById('addAdminPass').value = '';
      openModal('addAdminModal');
    }

    async function submitAddAdmin() {
      const uname = document.getElementById('addAdminUname').value.trim();
      const pass = document.getElementById('addAdminPass').value.trim();
      const title = document.getElementById('addAdminTitle').value;
      const role = document.getElementById('addAdminRole').value;

      if (!uname || !pass) {
        alert('账号和密码不能为空！');
        return;
      }
      try {
        const res = await apiFetch('/api/v1/admin/admins/create', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({username: uname, password: pass, display_name: title, role_key: role})
        });
        const d = await res.json();
        alert(d.message);
        if (d.code === 0) {
          closeModal('addAdminModal');
          loadAdmins();
        }
      } catch (e) {
        alert('创建失败: ' + e);
      }
    }

    function openEditAdminModal(id, uname, title, roleKey) {
      if (document.getElementById('editAdminId')) document.getElementById('editAdminId').value = id;
      if (document.getElementById('editAdminUname')) document.getElementById('editAdminUname').value = uname;
      if (document.getElementById('editAdminTitle')) document.getElementById('editAdminTitle').value = title;
      if (document.getElementById('editAdminNewPass')) document.getElementById('editAdminNewPass').value = '';
      openModal('editAdminModal');
    }

    async function submitEditAdmin() {
      const id = document.getElementById('editAdminId').value;
      const title = document.getElementById('editAdminTitle').value;
      const pass = document.getElementById('editAdminNewPass') ? document.getElementById('editAdminNewPass').value.trim() : '';

      try {
        const res = await apiFetch('/api/v1/admin/admins/update', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({id: id, display_name: title, new_password: pass})
        });
        const d = await res.json();
        alert(d.message);
        if (d.code === 0) {
          closeModal('editAdminModal');
          loadAdmins();
        }
      } catch (e) {
        alert('更新失败: ' + e);
      }
    }

    async function deleteAdmin(id, uname) {
      if (!confirm('确定彻底注销管理员【' + uname + '】吗？此操作不可逆！')) return;
      try {
        const res = await apiFetch('/api/v1/admin/admins/delete', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({id: id})
        });
        const d = await res.json();
        alert(d.message);
        loadAdmins();
      } catch (e) {
        alert('删除失败: ' + e);
      }
    }

    async function submitRelease(e) {
      e.preventDefault();
      const payload = {
        version_code: parseInt(document.getElementById('relCode').value),
        version_name: document.getElementById('relName').value.trim(),
        apk_url: document.getElementById('relUrl').value.trim(),
        apk_size_mb: parseFloat(document.getElementById('relSize').value) || 18.5,
        changelog_zh: document.getElementById('relChangelogZh').value.trim(),
        changelog_en: document.getElementById('relChangelogEn').value.trim(),
        is_forced: document.getElementById('relForced').checked
      };

      try {
        const res = await apiFetch('/api/v1/admin/release', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(payload)
        });
        const d = await res.json();
        alert(d.message);
        loadStats();
      } catch (e) {
        alert('发布异常: ' + e);
      }
    }

    // 页面初始化自适应加载各模块数据
    function initDashboard() {
      loadStats();
      loadUsers();
      loadTickets();
      loadPublicRoadbooks();
      loadTeamRoadbooks();
      loadPersonalRoadbooks();
      loadDictItems('region');
      loadAdmins();
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initDashboard);
    } else {
      initDashboard();
    }

  </script>
</body>
</html>`, html.EscapeString(adminDisplayName), html.EscapeString(roleBadge), roleLevel, adminToken, roleLevel)
}

// GET /api/v1/admin/stats
func handleAdminStats(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 10)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	var usersCount, rbCount, trkCount, pendingTickets int
	var latestVer string

	_ = db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&usersCount)
	_ = db.QueryRow(`SELECT COUNT(*) FROM user_roadbooks`).Scan(&rbCount)
	_ = db.QueryRow(`SELECT COUNT(*) FROM user_tracks`).Scan(&trkCount)
	_ = db.QueryRow(`SELECT COUNT(*) FROM user_tickets WHERE status = 'pending'`).Scan(&pendingTickets)
	_ = db.QueryRow(`SELECT version_name FROM app_releases ORDER BY version_code DESC LIMIT 1`).Scan(&latestVer)
	if latestVer == "" {
		latestVer = "0.7.7"
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": map[string]any{
			"total_users":     usersCount,
			"pending_tickets": pendingTickets,
			"total_roadbooks": rbCount,
			"total_tracks":    trkCount,
			"latest_version":  latestVer,
		},
	})
}

// GET /api/v1/admin/users
func handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	rows, err := db.Query(`
		SELECT id, phone_or_email, nickname, COALESCE(avatar_url,''), gender, bio,
		       vehicle_model, emergency_contact_name, emergency_contact_phone,
		       total_distance_m, is_verified, status, created_at
		FROM users ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "读取用户列表失败"})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, acc, nick, av, gender, bio, veh, emName, emPhone, createdAt string
		var dist float64
		var isVer, status int
		if err := rows.Scan(
			&id, &acc, &nick, &av, &gender, &bio,
			&veh, &emName, &emPhone,
			&dist, &isVer, &status, &createdAt,
		); err == nil {
			list = append(list, map[string]any{
				"id":                      id,
				"phone_or_email":          acc,
				"nickname":                nick,
				"avatar_url":              av,
				"gender":                  gender,
				"bio":                     bio,
				"vehicle_model":           veh,
				"emergency_contact_name":  emName,
				"emergency_contact_phone": emPhone,
				"total_distance_m":        dist,
				"is_verified":             isVer,
				"status":                  status,
				"created_at":              createdAt,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": list,
	})
}

// POST /api/v1/admin/user/update
func handleAdminUserUpdate(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	var req struct {
		ID       string `json:"id"`
		Nickname string `json:"nickname"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数错误"})
		return
	}

	if req.Nickname != "" {
		_, _ = db.Exec(`UPDATE users SET nickname = ? WHERE id = ?`, req.Nickname, req.ID)
	}
	if len(req.Password) >= 6 {
		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err == nil {
			_, _ = db.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, string(hash), req.ID)
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "用户资料/密码已成功更新！",
	})
}

// POST /api/v1/admin/user/delete
func handleAdminUserDelete(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 50)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "权限不足：至少需要系统管理员级别"})
		return
	}

	var req struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数错误"})
		return
	}

	_, _ = db.Exec(`DELETE FROM users WHERE id = ?`, req.ID)
	_, _ = db.Exec(`DELETE FROM user_tracks WHERE user_id = ?`, req.ID)
	_, _ = db.Exec(`DELETE FROM user_roadbooks WHERE user_id = ?`, req.ID)

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "用户及其云端数据已彻底注销删除！",
	})
}

// GET /api/v1/admin/tickets
func handleAdminTickets(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	rows, err := db.Query(`
		SELECT id, user_account, ticket_type, contact_info, message, status, COALESCE(admin_reply,''), created_at, COALESCE(resolved_at,'')
		FROM user_tickets ORDER BY CASE WHEN status = 'pending' THEN 0 ELSE 1 END, created_at DESC LIMIT 100`)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "读取工单失败"})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, acc, ttype, cinfo, msg, status, reply, ctime, rtime string
		if err := rows.Scan(&id, &acc, &ttype, &cinfo, &msg, &status, &reply, &ctime, &rtime); err == nil {
			list = append(list, map[string]any{
				"id":           id,
				"user_account": acc,
				"ticket_type":  ttype,
				"contact_info": cinfo,
				"message":      msg,
				"status":       status,
				"admin_reply":  reply,
				"created_at":   ctime,
				"resolved_at":  rtime,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": list,
	})
}

// POST /api/v1/admin/ticket/resolve
func handleAdminTicketResolve(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	var req struct {
		ID            string `json:"id"`
		UserAccount   string `json:"user_account"`
		ResetPassword string `json:"reset_password"`
		Reply         string `json:"reply"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数错误"})
		return
	}

	if len(req.ResetPassword) >= 6 && req.UserAccount != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(req.ResetPassword), bcrypt.DefaultCost)
		if err == nil {
			_, _ = db.Exec(`UPDATE users SET password_hash = ? WHERE phone_or_email = ?`, string(hash), req.UserAccount)
		}
	}

	now := time.Now().Format("2006-01-02 15:04:05")
	_, err := db.Exec(`
		UPDATE user_tickets
		SET status = 'resolved', admin_reply = ?, resolved_at = ?
		WHERE id = ?`, req.Reply, now, req.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "更新工单失败"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "工单已办结回复，密码重置已完成！",
	})
}

// GET /api/v1/admin/admins
func handleAdminListAdmins(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 10)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	rows, err := db.Query(`
		SELECT a.id, a.username, a.display_name, a.role_key, COALESCE(r.role_name, '未知角色'), COALESCE(r.level, 0), COALESCE(r.description, ''),
		       a.is_active, a.created_at, COALESCE(a.last_login_at, '')
		FROM admins a
		LEFT JOIN admin_roles r ON a.role_key = r.role_key
		ORDER BY r.level DESC, a.created_at ASC`)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "读取管理员列表失败"})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, uname, dname, rkey, rname, rdesc, createdAt, lastLogin string
		var rlevel, isActive int
		if err := rows.Scan(&id, &uname, &dname, &rkey, &rname, &rlevel, &rdesc, &isActive, &createdAt, &lastLogin); err == nil {
			list = append(list, map[string]any{
				"id":            id,
				"username":      uname,
				"display_name":  dname,
				"role_key":      rkey,
				"role_name":     rname,
				"role_level":    rlevel,
				"role_desc":     rdesc,
				"is_active":     isActive,
				"created_at":    createdAt,
				"last_login_at": lastLogin,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": list,
	})
}

// POST /api/v1/admin/admins/create
func handleAdminCreateAdmin(w http.ResponseWriter, r *http.Request) {
	caller, ok := checkAdminRolePermission(r, 100)
	if !ok || caller.RoleLevel < 100 {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足：仅超级管理员具备新建管理员权限"})
		return
	}

	var req struct {
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		RoleKey     string `json:"role_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数格式错误"})
		return
	}
	u := strings.TrimSpace(req.Username)
	if len(u) < 3 || len(req.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "账号至少3位，密码至少6位"})
		return
	}
	dname := strings.TrimSpace(req.DisplayName)
	if dname == "" {
		dname = "技术运维主管"
	}
	rkey := strings.TrimSpace(req.RoleKey)
	if rkey != "super_admin" && rkey != "admin" && rkey != "operator" && rkey != "auditor" {
		rkey = "admin"
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "密码哈希失败"})
		return
	}

	adminID := randomID("adm_", 8)
	now := time.Now().Format("2006-01-02 15:04:05")
	_, err = db.Exec(`
		INSERT INTO admins (id, username, password_hash, display_name, role_key, is_active, created_at)
		VALUES (?, ?, ?, ?, ?, 1, ?)`,
		adminID, u, string(hash), dname, rkey, now,
	)
	if err != nil {
		writeJSON(w, http.StatusConflict, map[string]any{"code": 409, "message": "该管理员账号已存在，不能重复添加"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": fmt.Sprintf("新管理员【%s (%s)】已成功创建入表！", dname, u),
	})
}

// POST /api/v1/admin/admins/update (修复 admin 自身密码修改与超级管理改密)
func handleAdminUpdateAdmin(w http.ResponseWriter, r *http.Request) {
	caller, ok := checkAdminRolePermission(r, 50)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	var req struct {
		ID          string `json:"id"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数错误"})
		return
	}

	var targetLevel int
	var targetUser string
	err := db.QueryRow(`
		SELECT COALESCE(r.level, 0), a.username FROM admins a
		LEFT JOIN admin_roles r ON a.role_key = r.role_key
		WHERE a.id = ?`, req.ID).Scan(&targetLevel, &targetUser)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"code": 404, "message": "目标管理员不存在"})
		return
	}

	// 权限判断放行规则：
	// 1. 如果调用者是超级管理员 (Level 100)，可以修改包含 admin 在内的所有管理员密码与职务！
	// 2. 如果是管理员修改自身账号，允许放行！
	// 3. 其余情况：低等级禁止修改高等级
	isSelf := (caller.Username == targetUser)
	isSuper := (caller.RoleLevel >= 100)
	if !isSuper && !isSelf && (caller.RoleLevel <= targetLevel) {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "越权拦截：您的角色等级无权修改高级别管理员资料！"})
		return
	}

	if req.DisplayName != "" {
		_, _ = db.Exec(`UPDATE admins SET display_name = ? WHERE id = ?`, req.DisplayName, req.ID)
	}
	if len(req.Password) >= 6 {
		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err == nil {
			_, _ = db.Exec(`UPDATE admins SET password_hash = ? WHERE id = ?`, string(hash), req.ID)
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": fmt.Sprintf("管理员【%s】的密码/职务已成功更新！", targetUser),
	})
}

// POST /api/v1/admin/admins/delete
func handleAdminDeleteAdmin(w http.ResponseWriter, r *http.Request) {
	caller, ok := checkAdminRolePermission(r, 100)
	if !ok || caller.RoleLevel < 100 {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足：仅超级管理员具备注销管理员权限"})
		return
	}

	var req struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数错误"})
		return
	}

	var uname string
	_ = db.QueryRow(`SELECT username FROM admins WHERE id = ?`, req.ID).Scan(&uname)
	if uname == "admin" || req.ID == "adm_root" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "默认主管理员账号 (admin) 受到系统核心保护，不可删除！"})
		return
	}

	_, _ = db.Exec(`DELETE FROM admins WHERE id = ?`, req.ID)
	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": "管理员权限已彻底注销移除！",
	})
}

func handleAdminRoadbooks(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 10)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	rows, err := db.Query(`
		SELECT id, user_id, name, points_count, COALESCE(share_code, ''), uploaded_at
		FROM user_roadbooks ORDER BY uploaded_at DESC LIMIT 200`)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "查询路书失败"})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, uid, name, code, upAt string
		var pts int
		if err := rows.Scan(&id, &uid, &name, &pts, &code, &upAt); err == nil {
			list = append(list, map[string]any{
				"id":           id,
				"user_id":      uid,
				"name":         name,
				"points_count": pts,
				"share_code":   code,
				"uploaded_at":  upAt,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code": 0,
		"data": list,
	})
}

func handleAdminPublishRelease(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 50)
	if !ok {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足：至少需要系统管理员级别方可发布新版 App"})
		return
	}

	var req struct {
		VersionCode int     `json:"version_code"`
		VersionName string  `json:"version_name"`
		ApkURL      string  `json:"apk_url"`
		ApkSha256   string  `json:"apk_sha256"`
		ApkSizeMb   float64 `json:"apk_size_mb"`
		ChangelogZh string  `json:"changelog_zh"`
		ChangelogEn string  `json:"changelog_en"`
		IsForced    bool    `json:"is_forced"`
		ReleaseDate string  `json:"release_date"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VersionCode <= 0 || req.VersionName == "" || req.ApkURL == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数不完整：需提供 version_code, version_name, apk_url"})
		return
	}
	if req.ReleaseDate == "" {
		req.ReleaseDate = time.Now().Format("2006-01-02")
	}
	if req.ApkSizeMb <= 0 {
		req.ApkSizeMb = 18.5
	}
	forcedInt := 0
	if req.IsForced {
		forcedInt = 1
	}

	// 自动从 GitHub 离线缓存 APK 并清理旧版
	finalApkURL := req.ApkURL
	if (strings.HasPrefix(req.ApkURL, "http://") || strings.HasPrefix(req.ApkURL, "https://")) && !strings.Contains(req.ApkURL, "api.terraway.cn") {
		vpsURL, sizeMb, sha, err := downloadAndCacheApk(req.ApkURL, req.VersionName)
		if err == nil {
			finalApkURL = vpsURL
			if sizeMb > 0 {
				req.ApkSizeMb = sizeMb
			}
			if sha != "" {
				req.ApkSha256 = sha
			}
		} else {
			log.Printf("[APK CACHE WARNING] 自动拉取 GitHub APK 异常 (%v)，继续使用原始直链", err)
		}
	}

	_, err := db.Exec(`
		INSERT OR REPLACE INTO app_releases (
			version_code, version_name, apk_url, apk_sha256, apk_size_mb,
			changelog_zh, changelog_en, is_forced, release_date
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		req.VersionCode, req.VersionName, finalApkURL, req.ApkSha256, req.ApkSizeMb,
		req.ChangelogZh, req.ChangelogEn, forcedInt, req.ReleaseDate,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "写入版本发布记录失败"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"code":    0,
		"message": fmt.Sprintf("新版本 v%s (code=%d) 已成功发布上架！手机端打开即会自动弹窗提醒覆盖升级。", req.VersionName, req.VersionCode),
	})
}

func writeGzipFile(path string, data []byte) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0640)
	if err != nil {
		return err
	}
	defer f.Close()
	gw := gzip.NewWriter(f)
	if _, err := gw.Write(data); err != nil {
		gw.Close()
		return err
	}
	return gw.Close()
}

func readGzipFile(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	gr, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gr.Close()
	return io.ReadAll(gr)
}


// ============================================================================
// 7. APK 自动下载离线缓存与旧版本自动清理
// ============================================================================

func downloadAndCacheApk(rawURL, versionName string) (string, float64, string, error) {
	cacheDir := filepath.Join(dataDir, "apk_cache")
	_ = os.MkdirAll(cacheDir, 0750)

	targetFilename := fmt.Sprintf("terraway_gps_v%s.apk", versionName)
	targetPath := filepath.Join(cacheDir, targetFilename)

	// 1. 发起 HTTP GET 请求拉取 APK (自动跟随 GitHub 302 重定向)
	client := &http.Client{Timeout: 90 * time.Second}
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return "", 0, "", err
	}
	req.Header.Set("User-Agent", "TerraWay-Server-Cache/v0.7.7")

	resp, err := client.Do(req)
	if err != nil {
		return "", 0, "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", 0, "", fmt.Errorf("HTTP status %d", resp.StatusCode)
	}

	// 2. 自动清理旧版本：扫描并删除 apk_cache 目录下的所有历史 APK
	entries, _ := os.ReadDir(cacheDir)
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".apk") && entry.Name() != targetFilename {
			oldPath := filepath.Join(cacheDir, entry.Name())
			_ = os.Remove(oldPath)
			log.Printf("[CLEANUP] 已自动清理删除历史版本安装包: %s", entry.Name())
		}
	}

	// 3. 流式写入本地并同步计算 SHA-256 与文件大小
	tempPath := targetPath + ".tmp"
	f, err := os.OpenFile(tempPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return "", 0, "", err
	}

	hasher := sha256.New()
	multiWriter := io.MultiWriter(f, hasher)
	written, err := io.Copy(multiWriter, resp.Body)
	f.Close()
	if err != nil {
		_ = os.Remove(tempPath)
		return "", 0, "", err
	}

	_ = os.Rename(tempPath, targetPath)
	sizeMb := float64(written) / (1024.0 * 1024.0)
	shaHex := hex.EncodeToString(hasher.Sum(nil))
	log.Printf("[APK CACHE] 成功从 GitHub 自动缓存新版 APK: %s (%.2f MB, SHA: %s)", targetFilename, sizeMb, shaHex)

	// 生成 VPS 专属直链与固定最新直链
	vpsDownloadURL := "https://api.terraway.cn/api/v1/app/download/latest"
	return vpsDownloadURL, sizeMb, shaHex, nil
}

func handleDownloadLatestApk(w http.ResponseWriter, r *http.Request) {
	cacheDir := filepath.Join(dataDir, "apk_cache")
	_ = os.MkdirAll(cacheDir, 0750)
	entries, err := os.ReadDir(cacheDir)
	
	// 若本地缓存暂无文件，尝试从数据库读取原始外部链接并现场即时拉取缓存
	if err != nil || len(entries) == 0 {
		var rawURL, vName string
		err := db.QueryRow(`SELECT apk_url, version_name FROM app_releases ORDER BY version_code DESC LIMIT 1`).Scan(&rawURL, &vName)
		if err == nil && (strings.HasPrefix(rawURL, "http://") || strings.HasPrefix(rawURL, "https://")) && !strings.Contains(rawURL, "api.terraway.cn") {
			_, _, _, _ = downloadAndCacheApk(rawURL, vName)
			entries, _ = os.ReadDir(cacheDir)
		}
	}

	if len(entries) == 0 {
		http.Error(w, "暂无可用安装包，请联系管理员", http.StatusNotFound)
		return
	}

	var latestName string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".apk") {
			latestName = e.Name()
			break
		}
	}

	if latestName == "" {
		http.Error(w, "未找到已缓存的安装包", http.StatusNotFound)
		return
	}

	serveApkFile(w, r, filepath.Join(cacheDir, latestName), latestName)
}

func handleDownloadApkByFilename(w http.ResponseWriter, r *http.Request) {
	fname := filepath.Base(r.URL.Path)
	if fname == "" || !strings.HasSuffix(fname, ".apk") {
		http.Error(w, "无效的安装包请求", http.StatusBadRequest)
		return
	}

	filePath := filepath.Join(dataDir, "apk_cache", fname)
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		http.Error(w, "安装包不存在或已下架", http.StatusNotFound)
		return
	}

	serveApkFile(w, r, filePath, fname)
}

func serveApkFile(w http.ResponseWriter, r *http.Request, filePath, filename string) {
	f, err := os.Open(filePath)
	if err != nil {
		http.Error(w, "读取安装包失败", http.StatusInternalServerError)
		return
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		http.Error(w, "读取文件状态失败", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", "attachment; filename=" + filename)
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeContent(w, r, filename, fi.ModTime(), f)
}



// 自适应预填充国内经典顶级越野/徒步/自驾公共精选路书 (共计 62 条覆盖全国各大片区)
func seedPublicRoadbooks() {
	var count int
	_ = publicDb.QueryRow("SELECT COUNT(*) FROM public_roadbooks").Scan(&count)
	if count > 0 {
		return
	}
	log.Printf("[INFO] public_roadbooks 库为空，自适应注入 %d 条国内顶级经典越野、徒步与自驾官方精选路书...", 62)

	type routeSeed struct {
		ID        string
		Title     string
		Region    string
		Terrain   string
		Category  string
		Diff      int
		Vehicle   string
		DistKm    float64
		EleGain   float64
		EleMax    float64
		Duration  string
		Season    string
		Downloads int
		Desc      string
		WptsJSON  string
	}

	seeds := []routeSeed{
		{
			ID:        "pub_nm_01",
			Title:     "巴丹吉林沙漠穿行越野线",
			Region:    "neimenggu",
			Terrain:   "desert_dune",
			Category:  "offroad",
			Diff:      5,
			Vehicle:   "4x4_extreme",
			DistKm:    182.5,
			EleGain:   850,
			EleMax:    1611,
			Duration:  "3天2夜",
			Season:    "5-10月",
			Downloads: 892,
			Desc:      "中国最美沙漠核心穿越线。跨越世界最高沙峰“必鲁图沙峰”，探访沙漠奇观音德日图神泉、仙女峰与庙海子。全线为重度流动高大沙丘，沙刀与暗沙梁密布，极易陷车翻滚，必须硬派高底盘四驱双锁车型且由两台以上车队同行，配齐防沙旗、放气减压表（胎压需降至0.6-0.8 bar）及脱困防滑板。",
			WptsJSON:  "[{\"id\": \"wp_nm01_1\", \"name\": \"巴丹吉林地质公园入口\", \"lat\": 39.3512, \"lon\": 102.3214, \"ele\": 1210, \"desc\": \"入沙检查登记，放胎压至0.8bar，插沙旗\"}, {\"id\": \"wp_nm01_2\", \"name\": \"巴丹湖营地\", \"lat\": 39.423, \"lon\": 102.385, \"ele\": 1235, \"desc\": \"首个沙漠湖泊，淡水补给与首晚露营点\"}, {\"id\": \"wp_nm01_3\", \"name\": \"音德日图神泉湖\", \"lat\": 39.754, \"lon\": 102.432, \"ele\": 1280, \"desc\": \"咸水湖中涌现百眼淡水泉，地质奇观，禁止冲滩\"}, {\"id\": \"wp_nm01_4\", \"name\": \"必鲁图沙峰脚下\", \"lat\": 39.812, \"lon\": 102.473, \"ele\": 1390, \"desc\": \"世界最高沙峰基座，坡度达45度，需大动力冲顶\"}, {\"id\": \"wp_nm01_5\", \"name\": \"必鲁图珠峰观景台\", \"lat\": 39.825, \"lon\": 102.481, \"ele\": 1611, \"desc\": \"俯瞰数个彩色盐湖群，信号微弱，注意防风\"}, {\"id\": \"wp_nm01_6\", \"name\": \"庙海子沙漠绿洲\", \"lat\": 39.789, \"lon\": 102.408, \"ele\": 1260, \"desc\": \"藏传佛教巴丹吉林庙，补给燃油水饮中继站\"}, {\"id\": \"wp_nm01_7\", \"name\": \"诺尔图湖畔\", \"lat\": 39.712, \"lon\": 102.355, \"ele\": 1245, \"desc\": \"沙漠最大湖泊，沙山倒影极佳出片点\"}, {\"id\": \"wp_nm01_8\", \"name\": \"雅布赖镇出沙口\", \"lat\": 39.601, \"lon\": 102.185, \"ele\": 1205, \"desc\": \"出沙公路连接点，给轮胎充气，完成穿越\"}]",
		},
		{
			ID:        "pub_nm_02",
			Title:     "克什克腾旗·达里诺尔湖大环线",
			Region:    "neimenggu",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "at_tire",
			DistKm:    328.0,
			EleGain:   420,
			EleMax:    1420,
			Duration:  "2天1夜",
			Season:    "6-9月",
			Downloads: 645,
			Desc:      "内蒙古经典草原自驾大环线。串联贡格尔草原、热水塘温泉、达里湖（达里诺尔）、砧子山古岩画以及阿斯哈图石林第四纪冰川花岗岩石臼地貌。路况以柏油路、铺装碎石及草原车辙道为主，四驱SUV或更换AT胎即可轻松通达。",
			WptsJSON:  "[{\"id\": \"wp_nm02_1\", \"name\": \"经棚镇起点\", \"lat\": 43.265, \"lon\": 117.538, \"ele\": 1020, \"desc\": \"克什克腾旗首府，完成油料与食物采购\"}, {\"id\": \"wp_nm02_2\", \"name\": \"热水塘地热温泉\", \"lat\": 43.372, \"lon\": 117.485, \"ele\": 1090, \"desc\": \"著名硫磺温泉小镇，疗养歇脚\"}, {\"id\": \"wp_nm02_3\", \"name\": \"达里诺尔湖北岸\", \"lat\": 43.328, \"lon\": 116.654, \"ele\": 1226, \"desc\": \"候鸟天堂，火山熔岩堰塞湖，观夕阳晚霞\"}, {\"id\": \"wp_nm02_4\", \"name\": \"砧子山古岩画\", \"lat\": 43.361, \"lon\": 116.602, \"ele\": 1310, \"desc\": \"孤峰突起火山口遗迹，古突厥岩画\"}, {\"id\": \"wp_nm02_5\", \"name\": \"贡格尔草原腹地\", \"lat\": 43.452, \"lon\": 116.985, \"ele\": 1150, \"desc\": \"风车群与河曲草原，土路车辙注意减速\"}, {\"id\": \"wp_nm02_6\", \"name\": \"阿斯哈图石林\", \"lat\": 44.053, \"lon\": 117.265, \"ele\": 1420, \"desc\": \"第四纪冰川遗迹石林群，地质公园打卡\"}, {\"id\": \"wp_nm02_7\", \"name\": \"黄岗梁大兴安岭主峰\", \"lat\": 43.725, \"lon\": 117.489, \"ele\": 1380, \"desc\": \"大兴安岭最高峰森林秋景与盘山弯道\"}, {\"id\": \"wp_nm02_8\", \"name\": \"经棚终点闭环\", \"lat\": 43.265, \"lon\": 117.538, \"ele\": 1020, \"desc\": \"返回起点完成环线\"}]",
		},
		{
			ID:        "pub_nm_03",
			Title:     "库布齐沙漠东段重装徒步穿越",
			Region:    "neimenggu",
			Terrain:   "desert_dune",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    46.8,
			EleGain:   320,
			EleMax:    1230,
			Duration:  "2天1夜",
			Season:    "4-5月, 9-10月",
			Downloads: 520,
			Desc:      "国内最适合新手晋升进阶的重装沙漠徒步路线。由响沙湾西行穿越连绵沙丘至恩格贝生态示范区，沿途横穿断续沙梁与草滩。需备足每日至少4L饮用水、雪套（防沙套）、GPS离线导航手持设备、防风沙护目镜与抗风沙帐篷。",
			WptsJSON:  "[{\"id\": \"wp_nm03_1\", \"name\": \"响沙湾入沙点\", \"lat\": 40.298, \"lon\": 109.985, \"ele\": 1080, \"desc\": \"穿戴雪套，配足4L水源，校准手持罗盘\"}, {\"id\": \"wp_nm03_2\", \"name\": \"一号绿洲锁边林\", \"lat\": 40.325, \"lon\": 109.852, \"ele\": 1120, \"desc\": \"人工草方格防护林边缘，微弱手机信号\"}, {\"id\": \"wp_nm03_3\", \"name\": \"龙头拐高大沙梁\", \"lat\": 40.362, \"lon\": 109.689, \"ele\": 1230, \"desc\": \"沙梁顶脊线行走阻力较小，沿背风坡滑行\"}, {\"id\": \"wp_nm03_4\", \"name\": \"沙心露营地\", \"lat\": 40.395, \"lon\": 109.521, \"ele\": 1180, \"desc\": \"避风低洼平地扎营，重装打地钉固定防风绳\"}, {\"id\": \"wp_nm03_5\", \"name\": \"黑赖沟断流河床\", \"lat\": 40.428, \"lon\": 109.385, \"ele\": 1100, \"desc\": \"沙石混杂河床，注意防陷泥沼\"}, {\"id\": \"wp_nm03_6\", \"name\": \"恩格贝生态区终点\", \"lat\": 40.485, \"lon\": 109.215, \"ele\": 1030, \"desc\": \"抵达绿洲，洗去沙尘，联系接驳车返程\"}]",
		},
		{
			ID:        "pub_nm_04",
			Title:     "呼伦贝尔大草原·中俄边防自驾",
			Region:    "neimenggu",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    680.0,
			EleGain:   380,
			EleMax:    820,
			Duration:  "4天3夜",
			Season:    "6-8月, 9月中下旬",
			Downloads: 1120,
			Desc:      "中国北疆最辽阔温情的边防公路自驾之旅。沿额尔古纳河（中俄界河）顺流而下，途经天下第一曲水莫日格勒河、白桦林、黑山头骑马场、边境卡线（五卡/七卡/九卡）、室韦俄罗斯民族乡直至满洲里国门。全程景观开阔壮丽，路况良好，普通家用SUV即可顺畅通行。",
			WptsJSON:  "[{\"id\": \"wp_nm04_1\", \"name\": \"海拉尔出发\", \"lat\": 49.215, \"lon\": 119.754, \"ele\": 610, \"desc\": \"租车/自驾集合，补给冷库牛羊肉与行囊\"}, {\"id\": \"wp_nm04_2\", \"name\": \"莫日格勒河九曲观景台\", \"lat\": 49.421, \"lon\": 119.985, \"ele\": 650, \"desc\": \"天下第一曲水，草原俯瞰蜿蜒河道\"}, {\"id\": \"wp_nm04_3\", \"name\": \"额尔古纳湿地公园\", \"lat\": 50.245, \"lon\": 120.178, \"ele\": 580, \"desc\": \"亚洲第一湿地灌木丛群落\"}, {\"id\": \"wp_nm04_4\", \"name\": \"黑山头马术训练营\", \"lat\": 50.215, \"lon\": 119.562, \"ele\": 530, \"desc\": \"日落山俯瞰额尔古纳河日落，体验骑马\"}, {\"id\": \"wp_nm04_5\", \"name\": \"七卡边防中俄界河公路\", \"lat\": 50.852, \"lon\": 119.921, \"ele\": 510, \"desc\": \"边防巡逻X904县道，近观对岸俄境木屋\"}, {\"id\": \"wp_nm04_6\", \"name\": \"室韦俄罗斯民族乡\", \"lat\": 51.345, \"lon\": 119.892, \"ele\": 520, \"desc\": \"住木刻楞小木屋，品尝俄式大列巴与蓝莓酱\"}, {\"id\": \"wp_nm04_7\", \"name\": \"满洲里口岸国门\", \"lat\": 49.598, \"lon\": 117.438, \"ele\": 590, \"desc\": \"国门景区，中俄蒙三国异域风情夜景\"}]",
		},
		{
			ID:        "pub_nm_05",
			Title:     "乌兰布统草原越野穿越线",
			Region:    "neimenggu",
			Terrain:   "forest_mountain",
			Category:  "offroad",
			Diff:      3,
			Vehicle:   "4x4_high_clearance",
			DistKm:    125.0,
			EleGain:   480,
			EleMax:    1580,
			Duration:  "2天1夜",
			Season:    "5-10月, 12-2月雪原",
			Downloads: 780,
			Desc:      "京津冀越野车友的“后花园与练兵场”。涵盖塞罕坝界河、蛤蟆坝摄影天堂、透亮沟涉水穿越、影视基地以及野鸭湖。春夏季绿浪翻滚，秋季层林尽染，冬季则是天然大雪原漂移越野圣地。透亮沟包含多处卵石浅滩涉水，需检查进气口与排气管离地间隙。",
			WptsJSON:  "[{\"id\": \"wp_nm05_1\", \"name\": \"御道口牧场入山口\", \"lat\": 42.125, \"lon\": 117.025, \"ele\": 1320, \"desc\": \"承德入塞罕坝国家森林公园门禁\"}, {\"id\": \"wp_nm05_2\", \"name\": \"乌兰布统古战场遗迹\", \"lat\": 42.582, \"lon\": 117.214, \"ele\": 1410, \"desc\": \"康熙亲征噶尔丹历史遗迹点\"}, {\"id\": \"wp_nm05_3\", \"name\": \"影视基地北沟\", \"lat\": 42.632, \"lon\": 117.285, \"ele\": 1460, \"desc\": \"百部影视剧取景地，起伏丘陵草甸车辙道\"}, {\"id\": \"wp_nm05_4\", \"name\": \"蛤蟆坝摄影平台\", \"lat\": 42.715, \"lon\": 117.382, \"ele\": 1510, \"desc\": \"沟谷错落农耕草原结合，晨雾与牛羊炊烟\"}, {\"id\": \"wp_nm05_5\", \"name\": \"透亮沟涉水段\", \"lat\": 42.685, \"lon\": 117.452, \"ele\": 1380, \"desc\": \"连续卵石涉水滩，挂低速四驱稳油门通过\"}, {\"id\": \"wp_nm05_6\", \"name\": \"暖水河红松林出口\", \"lat\": 42.541, \"lon\": 117.158, \"ele\": 1350, \"desc\": \"湿地蜿蜒河流，出山接承围公路\"}]",
		},
		{
			ID:        "pub_nm_06",
			Title:     "浑善达克沙地腹地穿越线",
			Region:    "neimenggu",
			Terrain:   "desert_dune",
			Category:  "offroad",
			Diff:      4,
			Vehicle:   "4x4_high_clearance",
			DistKm:    218.0,
			EleGain:   350,
			EleMax:    1380,
			Duration:  "2天1夜",
			Season:    "5-10月",
			Downloads: 460,
			Desc:      "被誉为“塞外水乡沙地”的典型半固定沙丘穿行路线。沙丘高大且植被丰富，暗藏多处沼泽湿地与柳丛泥塘（俗称烂泥潭）。需要掌握沙丘滚刀梁切入技巧，避开水草丰茂的隐蔽泥淖，极度考验驾驶者的选线眼力和领航默契。",
			WptsJSON:  "[{\"id\": \"wp_nm06_1\", \"name\": \"正蓝旗上都镇起点\", \"lat\": 42.254, \"lon\": 116.012, \"ele\": 1210, \"desc\": \"元上都遗址旁集结，放胎压至1.0bar\"}, {\"id\": \"wp_nm06_2\", \"name\": \"小扎格斯台淖尔湖\", \"lat\": 42.482, \"lon\": 115.892, \"ele\": 1265, \"desc\": \"沙漠中的淡水湖，沙山与芦苇相映成趣\"}, {\"id\": \"wp_nm06_3\", \"name\": \"榆树林沙梁分水岭\", \"lat\": 42.651, \"lon\": 115.752, \"ele\": 1340, \"desc\": \"沙地疏林景观，沙脊骑梁行驶注意对向盲区\"}, {\"id\": \"wp_nm06_4\", \"name\": \"高格斯台河涉水点\", \"lat\": 42.812, \"lon\": 115.621, \"ele\": 1250, \"desc\": \"河床较软，切勿停车怠速，紧跟前车车辙\"}, {\"id\": \"wp_nm06_5\", \"name\": \"哈毕日嘎镇公路出沙口\", \"lat\": 42.985, \"lon\": 115.421, \"ele\": 1190, \"desc\": \"驶入国道，补气洗车完成穿越\"}]",
		},
		{
			ID:        "pub_nm_07",
			Title:     "乌兰哈达火山地质巡游线",
			Region:    "neimenggu",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    85.0,
			EleGain:   260,
			EleMax:    1450,
			Duration:  "1天",
			Season:    "4-10月, 适合太空服出片",
			Downloads: 960,
			Desc:      "内蒙古察哈尔右翼后旗火山群地质探索。由3号北炼丹炉（修有木栈道）、4号黑脑包（火山石柱）、5号中炼丹炉（保存最完整火山口锥体）及6号南炼丹炉组成。犹如漫步火星地表，适合轻越野、摄影露营与星空夜拍。",
			WptsJSON:  "[{\"id\": \"wp_nm07_1\", \"name\": \"察右后旗白音察干集结点\", \"lat\": 41.452, \"lon\": 113.185, \"ele\": 1380, \"desc\": \"国道补给，租借宇航服拍照道具\"}, {\"id\": \"wp_nm07_2\", \"name\": \"3号火山(北炼丹炉)\", \"lat\": 41.582, \"lon\": 113.215, \"ele\": 1420, \"desc\": \"设有木栈道可登顶火山口俯瞰平原\"}, {\"id\": \"wp_nm07_3\", \"name\": \"4号火山(黑脑包玛瑙滩)\", \"lat\": 41.552, \"lon\": 113.225, \"ele\": 1410, \"desc\": \"黑色玄武岩地质构造，地面有火山玛瑙碎石\"}, {\"id\": \"wp_nm07_4\", \"name\": \"5号火山(中炼丹炉最美锥体)\", \"lat\": 41.521, \"lon\": 113.235, \"ele\": 1450, \"desc\": \"保存最完好火山锥，夕阳落日熔岩奇观\"}, {\"id\": \"wp_nm07_5\", \"name\": \"6号火山(南炼丹炉开采遗迹)\", \"lat\": 41.485, \"lon\": 113.245, \"ele\": 1430, \"desc\": \"半截被开采的火山口截面，宛如太空基地\"}]",
		},
		{
			ID:        "pub_nm_08",
			Title:     "额济纳胡杨林·黑城弱水穿越",
			Region:    "neimenggu",
			Terrain:   "desert_dune",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "at_tire",
			DistKm:    195.0,
			EleGain:   180,
			EleMax:    1020,
			Duration:  "2天1夜",
			Season:    "9月下旬-10月中旬",
			Downloads: 1250,
			Desc:      "阿拉善大漠深处金色奇迹之路。金秋十月胡杨树叶金黄璀璨，串联达来呼布镇一至八道桥、西夏黑城遗址古城堡、弱水金沙湾与怪树林千年枯木。夜宿大漠露营观赏绝美银河。",
			WptsJSON:  "[{\"id\": \"wp_nm08_1\", \"name\": \"达来呼布镇一道桥\", \"lat\": 41.958, \"lon\": 101.052, \"ele\": 940, \"desc\": \"额济纳旗政府所在地，胡杨林国家级保护区起点\"}, {\"id\": \"wp_nm08_2\", \"name\": \"四道桥英雄林\", \"lat\": 41.985, \"lon\": 101.152, \"ele\": 950, \"desc\": \"电影《英雄》取景地，古老苍劲金黄胡杨\"}, {\"id\": \"wp_nm08_3\", \"name\": \"八道桥巴丹吉林沙漠北缘\", \"lat\": 42.012, \"lon\": 101.285, \"ele\": 980, \"desc\": \"沙漠与胡杨交界处，滑沙驼队出片\"}, {\"id\": \"wp_nm08_4\", \"name\": \"居延海芦苇湿地日出点\", \"lat\": 42.315, \"lon\": 101.452, \"ele\": 900, \"desc\": \"老子化胡西出之地，晨曦群鸟翔集\"}, {\"id\": \"wp_nm08_5\", \"name\": \"黑城古遗址(西夏黑水城)\", \"lat\": 41.752, \"lon\": 101.125, \"ele\": 920, \"desc\": \"丝路最完整古城城堡遗址，黄沙掩埋佛塔\"}, {\"id\": \"wp_nm08_6\", \"name\": \"怪树林千年不倒枯木群\", \"lat\": 41.725, \"lon\": 101.105, \"ele\": 930, \"desc\": \"“生而一千年不死，死而一千年不倒”，晚霞悲壮\"}]",
		},
		{
			ID:        "pub_xj_09",
			Title:     "独库公路全线壮美自驾 (G217)",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    561.0,
			EleGain:   2650,
			EleMax:    3390,
			Duration:  "2~3天",
			Season:    "6月中旬-10月初",
			Downloads: 2840,
			Desc:      "“一天经历四季，十里不同天”。贯穿天山南北的英雄之路，连接北疆独山子与南疆库车。翻越哈希勒根达坂、玉希莫勒盖达坂、铁力买提达坂3座雪山垭口，途径乔尔玛烈士陵园、巴音布鲁克天鹅湖与库车大峡谷。仅限7座及以下小客车通行，需密切关注气候封路通知。",
			WptsJSON:  "[{\"id\": \"wp_xj09_1\", \"name\": \"独山子大峡谷入口(零公里)\", \"lat\": 44.312, \"lon\": 84.885, \"ele\": 850, \"desc\": \"独库公路起点，检查刹车油水，加满汽油\"}, {\"id\": \"wp_xj09_2\", \"name\": \"哈希勒根防雪走廊(3390m)\", \"lat\": 43.782, \"lon\": 84.625, \"ele\": 3390, \"desc\": \"北段最高海拔雪山达坂，常年积雪\"}, {\"id\": \"wp_xj09_3\", \"name\": \"乔尔玛革命烈士陵园\", \"lat\": 43.654, \"lon\": 84.512, \"ele\": 2180, \"desc\": \"缅怀筑路筑梦筑脊梁的168名解放军烈士\"}, {\"id\": \"wp_xj09_4\", \"name\": \"那拉提草原连通岔口\", \"lat\": 43.325, \"lon\": 84.015, \"ele\": 1650, \"desc\": \"空中草原与巩乃斯森林交汇口\"}, {\"id\": \"wp_xj09_5\", \"name\": \"巴音布鲁克天鹅湖\", \"lat\": 43.025, \"lon\": 84.152, \"ele\": 2450, \"desc\": \"开都河日落九个太阳奇观，高原湿地\"}, {\"id\": \"wp_xj09_6\", \"name\": \"铁力买提达坂隧道\", \"lat\": 42.482, \"lon\": 83.585, \"ele\": 3220, \"desc\": \"穿透天山南北分水岭，驶出即进入南疆热风\"}, {\"id\": \"wp_xj09_7\", \"name\": \"大龙池·小龙池\", \"lat\": 42.152, \"lon\": 83.254, \"ele\": 2390, \"desc\": \"高山冰碛堰塞湖，碧蓝如翡翠\"}, {\"id\": \"wp_xj09_8\", \"name\": \"库车天山大峡谷终点\", \"lat\": 41.985, \"lon\": 83.052, \"ele\": 1600, \"desc\": \"红褐色克孜利亚地貌，终点库车南疆人文\"}]",
		},
		{
			ID:        "pub_xj_10",
			Title:     "喀喇昆仑公路 (G314·中巴友谊路)",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    415.0,
			EleGain:   3450,
			EleMax:    4733,
			Duration:  "2天1夜",
			Season:    "5-10月",
			Downloads: 1980,
			Desc:      "世界上最高最惊险的国际公路之一。从古城喀什出发，横跨帕米尔高原，仰望慕士塔格峰（7546m）、公格尔九别峰，驻足白沙湖梦幻蓝白倒影与卡拉库里湖，穿过塔什库尔干石头城与金草滩，直至海拔4733米的红其拉甫国门口岸。需在喀什预先办理边防通行证。",
			WptsJSON:  "[{\"id\": \"wp_xj10_1\", \"name\": \"喀什古城西大门\", \"lat\": 39.472, \"lon\": 75.985, \"ele\": 1280, \"desc\": \"查验边防通行证，备好氧气袋与抗高反装备\"}, {\"id\": \"wp_xj10_2\", \"name\": \"奥依塔克红山峡谷\", \"lat\": 39.125, \"lon\": 75.452, \"ele\": 2100, \"desc\": \"丹霞赤壁地貌，公路开始攀升进入帕米尔\"}, {\"id\": \"wp_xj10_3\", \"name\": \"布伦口白沙湖观景台\", \"lat\": 38.752, \"lon\": 75.052, \"ele\": 3300, \"desc\": \"银白沙山与碧水交融，帕米尔高原明珠\"}, {\"id\": \"wp_xj10_4\", \"name\": \"卡拉库里湖(慕士塔格峰下)\", \"lat\": 38.452, \"lon\": 75.045, \"ele\": 3690, \"desc\": \"近距离仰视慕士塔格峰与公格尔峰\"}, {\"id\": \"wp_xj10_5\", \"name\": \"塔什库尔干石头城金草滩\", \"lat\": 37.775, \"lon\": 75.228, \"ele\": 3100, \"desc\": \"塔吉克族自治县，金草滩湿地夜宿\"}, {\"id\": \"wp_xj10_6\", \"name\": \"瓦罕走廊岔口界碑\", \"lat\": 37.215, \"lon\": 75.385, \"ele\": 3890, \"desc\": \"玄奘法师东归之路古道入口\"}, {\"id\": \"wp_xj10_7\", \"name\": \"红其拉甫前哨国门\", \"lat\": 36.852, \"lon\": 75.428, \"ele\": 4733, \"desc\": \"中国最西端口岸界碑，气候严寒严禁剧烈运动\"}]",
		},
		{
			ID:        "pub_xj_11",
			Title:     "盘龙古道“今日走过所有弯路”",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      3,
			Vehicle:   "suv_standard",
			DistKm:    38.0,
			EleGain:   1150,
			EleMax:    4210,
			Duration:  "半天",
			Season:    "5-10月",
			Downloads: 2450,
			Desc:      "帕米尔高原悬崖上的疯狂发卡弯。连接塔县与瓦恰乡的盘山天路，全长30多公里，拥有超过600多个弯道，落差超千米，海拔最高达4200米。“今日走过了人生所有的弯路，从此人生尽是坦途”。建议低速挡行驶，禁止空挡滑行。",
			WptsJSON:  "[{\"id\": \"wp_xj11_1\", \"name\": \"瓦恰公路西入口(大盘龙起点)\", \"lat\": 37.685, \"lon\": 75.312, \"ele\": 3080, \"desc\": \"网红标牌打卡，检查刹车盘片温度\"}, {\"id\": \"wp_xj11_2\", \"name\": \"大盘龙盘山观景平台\", \"lat\": 37.662, \"lon\": 75.352, \"ele\": 3680, \"desc\": \"俯瞰密集整齐的S弯天路，如黑色巨龙卧雪峰\"}, {\"id\": \"wp_xj11_3\", \"name\": \"盘龙古道最高垭口(4210m)\", \"lat\": 37.635, \"lon\": 75.385, \"ele\": 4210, \"desc\": \"最高峰拍照，风力强劲注意随身物品\"}, {\"id\": \"wp_xj11_4\", \"name\": \"小盘龙密集发卡弯\", \"lat\": 37.612, \"lon\": 75.421, \"ele\": 3520, \"desc\": \"更小半径的急转弯，必须鸣笛慢速通过\"}, {\"id\": \"wp_xj11_5\", \"name\": \"瓦恰乡杏花村出口\", \"lat\": 37.585, \"lon\": 75.485, \"ele\": 2890, \"desc\": \"驶入安静质朴的塔吉克小村庄\"}]",
		},
		{
			ID:        "pub_xj_12",
			Title:     "伊昭公路白石峰穿越线 (S237)",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      3,
			Vehicle:   "at_tire",
			DistKm:    180.0,
			EleGain:   1950,
			EleMax:    3120,
			Duration:  "1天",
			Season:    "6月-10月(每年仅夏季通车)",
			Downloads: 1150,
			Desc:      "伊犁仅次于独库公路的险峻天路。从伊宁出发经察布查尔翻越乌孙山白石峰达坂直达昭苏大草原。崖壁陡峭，临渊而建，弯急坡陡，雨雾天易发生落石与暗冰。限座7座及以下小车通行。",
			WptsJSON:  "[{\"id\": \"wp_xj12_1\", \"name\": \"察布查尔县锡伯自治县起点\", \"lat\": 43.835, \"lon\": 81.145, \"ele\": 620, \"desc\": \"伊犁河谷平原向乌孙山攀升起点\"}, {\"id\": \"wp_xj12_2\", \"name\": \"安格列特达坂盘山道\", \"lat\": 43.512, \"lon\": 81.185, \"ele\": 2450, \"desc\": \"连续Z字发卡弯，陡峭崖壁视野开阔\"}, {\"id\": \"wp_xj12_3\", \"name\": \"白石峰观景台(3120m)\", \"lat\": 43.421, \"lon\": 81.195, \"ele\": 3120, \"desc\": \"白色石灰岩巨峰拔地而起，巍峨雄奇\"}, {\"id\": \"wp_xj12_4\", \"name\": \"乌孙山南坡高山草甸\", \"lat\": 43.325, \"lon\": 81.162, \"ele\": 2350, \"desc\": \"下山进入平坦辽阔的昭苏盆地\"}, {\"id\": \"wp_xj12_5\", \"name\": \"昭苏天马文化园终点\", \"lat\": 43.158, \"lon\": 81.125, \"ele\": 1820, \"desc\": \"万马奔腾，天马故乡昭苏县城\"}]",
		},
		{
			ID:        "pub_xj_13",
			Title:     "乌孙古道南北重装徒步穿越",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    128.0,
			EleGain:   3800,
			EleMax:    3860,
			Duration:  "6天5夜",
			Season:    "8月下旬-10月初",
			Downloads: 890,
			Desc:      "中国十大徒步路线之冠。北起特克斯琼库什台，南出阿克苏拜城黑英山。沿途翻越包扎墩达坂与阿克布拉克达坂，溜索飞渡汹涌的科克苏河，途经高山绝美堰塞湖“天堂湖（阿克库勒湖）”。全线无补给、无信号，过河数十次水深至大腿，需携带卫星电话、过河朔溪鞋、潜水袜及高强度专业轻量化装备。",
			WptsJSON:  "[{\"id\": \"wp_xj13_1\", \"name\": \"琼库什台村牧业点\", \"lat\": 43.125, \"lon\": 82.254, \"ele\": 2050, \"desc\": \"徒步起点，称重背包（建议控制在18kg以内）\"}, {\"id\": \"wp_xj13_2\", \"name\": \"包扎墩达坂垭口(3660m)\", \"lat\": 42.895, \"lon\": 82.215, \"ele\": 3660, \"desc\": \"乱石碎坡陡峭攀升，碎石滑坠高风险\"}, {\"id\": \"wp_xj13_3\", \"name\": \"科克苏河溜索飞渡点\", \"lat\": 42.752, \"lon\": 82.152, \"ele\": 2180, \"desc\": \"水流湍急严禁徒步渡河，必须使用滑轮溜索过河\"}, {\"id\": \"wp_xj13_4\", \"name\": \"天堂湖(阿克库勒湖)\", \"lat\": 42.582, \"lon\": 82.025, \"ele\": 3100, \"desc\": \"深邃湛蓝湖泊，栈道贴壁行走注意重心稳定\"}, {\"id\": \"wp_xj13_5\", \"name\": \"阿克布拉克达坂(3860m)\", \"lat\": 42.495, \"lon\": 81.985, \"ele\": 3860, \"desc\": \"终年积雪达坂，暴风雪风险极高\"}, {\"id\": \"wp_xj13_6\", \"name\": \"博孜克日格河谷涉水区\", \"lat\": 42.325, \"lon\": 82.012, \"ele\": 2200, \"desc\": \"一日内连续涉渡冰川融水20余次，失温高发区\"}, {\"id\": \"wp_xj13_7\", \"name\": \"黑英山村出口\", \"lat\": 42.112, \"lon\": 82.152, \"ele\": 1420, \"desc\": \"出峡谷乘车出山，完成顶级朝圣之行\"}]",
		},
		{
			ID:        "pub_xj_14",
			Title:     "夏特古道南北徒步探险",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    115.0,
			EleGain:   3200,
			EleMax:    3580,
			Duration:  "5天4夜",
			Season:    "5月-6月, 9月-10月",
			Downloads: 650,
			Desc:      "跨越天山汗腾格里峰冰川的古丝绸之路险径。从昭苏夏特温泉向南，横跨木扎尔特大冰川冰塔林、冰裂缝，翻越哈达木孜达坂，出阿克苏温宿县。冰裂缝遍布、流沙冰崩频繁，必须结组使用冰爪、高山绳索与头盔等冰雪行进装备。",
			WptsJSON:  "[{\"id\": \"wp_xj14_1\", \"name\": \"夏特温泉度假村登山口\", \"lat\": 42.785, \"lon\": 80.852, \"ele\": 2280, \"desc\": \"徒步起点，向木扎尔特河谷溯流而上\"}, {\"id\": \"wp_xj14_2\", \"name\": \"三号冰川观测营地\", \"lat\": 42.612, \"lon\": 80.812, \"ele\": 2980, \"desc\": \"近观木扎尔特巨型蓝色悬冰川\"}, {\"id\": \"wp_xj14_3\", \"name\": \"木扎尔特大冰川前舌\", \"lat\": 42.485, \"lon\": 80.785, \"ele\": 3280, \"desc\": \"换穿高山冰爪，结组通过冰塔林与明暗冰裂缝\"}, {\"id\": \"wp_xj14_4\", \"name\": \"哈达木孜达坂(3580m)\", \"lat\": 42.385, \"lon\": 80.752, \"ele\": 3580, \"desc\": \"南北天山最高分界达坂，古炮台遗址\"}, {\"id\": \"wp_xj14_5\", \"name\": \"破城子营地(唐代古堡)\", \"lat\": 42.125, \"lon\": 80.685, \"ele\": 2350, \"desc\": \"南疆干燥峡谷碎石路，历史边关遗迹\"}, {\"id\": \"wp_xj14_6\", \"name\": \"温宿县夏特柯尔克孜村\", \"lat\": 41.852, \"lon\": 80.521, \"ele\": 1580, \"desc\": \"出峡谷接阿克苏公路，完成穿越\"}]",
		},
		{
			ID:        "pub_xj_15",
			Title:     "狼塔C+V高危极限重装徒步",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    195.0,
			EleGain:   6800,
			EleMax:    4030,
			Duration:  "9天8夜",
			Season:    "8月中旬-9月中旬",
			Downloads: 420,
			Desc:      "国内公认最高难度“骨灰级”重装徒步线路。贯通天山中部未开发深山，翻越白杨沟达坂、库勒阿特达坂、蒙格特逊达坂等9座高海拔雪山达坂，横切无数悬崖绝壁与咆哮冰河。需极强野外生存自救能力，严禁独行，必须携带卫通设备与专业技术领队引导。",
			WptsJSON:  "[{\"id\": \"wp_xj15_1\", \"name\": \"呼图壁雀儿沟白杨沟煤矿\", \"lat\": 43.852, \"lon\": 86.825, \"ele\": 1450, \"desc\": \"狼塔C线传统起点，最后称重与装备排查\"}, {\"id\": \"wp_xj15_2\", \"name\": \"白杨沟达坂垭口(3860m)\", \"lat\": 43.612, \"lon\": 86.752, \"ele\": 3860, \"desc\": \"雪坡攀升，下达坂为极碎滑石坡\"}, {\"id\": \"wp_xj15_3\", \"name\": \"台勒德达坂与一棵树营地\", \"lat\": 43.425, \"lon\": 86.685, \"ele\": 3680, \"desc\": \"绝壁狭窄横切羊道，一失足成千古恨\"}, {\"id\": \"wp_xj15_4\", \"name\": \"库勒阿特达坂垭口(3980m)\", \"lat\": 43.285, \"lon\": 86.612, \"ele\": 3980, \"desc\": \"狂风呼啸乱石如刀，注意防高反与滑坠\"}, {\"id\": \"wp_xj15_5\", \"name\": \"狼塔核心夏热达坂(4030m)\", \"lat\": 43.152, \"lon\": 86.521, \"ele\": 4030, \"desc\": \"全线最高峰垭口，极度严寒，积雪盈尺\"}, {\"id\": \"wp_xj15_6\", \"name\": \"哈尔嘎特郭勒大冰河\", \"lat\": 42.985, \"lon\": 86.421, \"ele\": 2850, \"desc\": \"河水冰刺入骨，必须合力结绳保护渡河\"}, {\"id\": \"wp_xj15_7\", \"name\": \"巴伦台古仁郭勒出山口\", \"lat\": 42.752, \"lon\": 86.254, \"ele\": 2100, \"desc\": \"抵达南疆和静县境出山，终结史诗挑战\"}]",
		},
		{
			ID:        "pub_xj_16",
			Title:     "喀纳斯·贾登峪-禾木-白哈巴徒步",
			Region:    "xinjiang",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      2,
			Vehicle:   "on_foot",
			DistKm:    68.0,
			EleGain:   1450,
			EleMax:    2350,
			Duration:  "3天2夜",
			Season:    "6月-7月花季, 9月中下旬金秋",
			Downloads: 1890,
			Desc:      "北疆童话阿尔泰山脉最治愈的景观徒步。自贾登峪出发，顺布尔津河谷至图瓦人禾木村看日出晨雾，经美丽峰越过黑湖高山草原抵中国西北第一村白哈巴。金秋白桦林金黄、木屋炊烟、繁星闪烁，难度适中、客栈成熟。",
			WptsJSON:  "[{\"id\": \"wp_xj16_1\", \"name\": \"贾登峪国家森林公园门票站\", \"lat\": 48.512, \"lon\": 87.125, \"ele\": 1420, \"desc\": \"轻装/重装出发，沿河谷步道慢行\"}, {\"id\": \"wp_xj16_2\", \"name\": \"布尔津河与禾木河三角洲\", \"lat\": 48.585, \"lon\": 87.254, \"ele\": 1280, \"desc\": \"两条冰川河汇流处，桥头木屋午餐中继\"}, {\"id\": \"wp_xj16_3\", \"name\": \"禾木图瓦人古村落观景台\", \"lat\": 48.712, \"lon\": 87.425, \"ele\": 1150, \"desc\": \"万亩白桦林环抱木屋，晨雾炊烟摄影圣地\"}, {\"id\": \"wp_xj16_4\", \"name\": \"黑湖高山苔原海子(2350m)\", \"lat\": 48.812, \"lon\": 87.215, \"ele\": 2350, \"desc\": \"黑色深邃的高山融雪湖，蒙古包茶歇\"}, {\"id\": \"wp_xj16_5\", \"name\": \"白哈巴中哈边境第一村\", \"lat\": 48.685, \"lon\": 86.785, \"ele\": 1240, \"desc\": \"边防界碑与中哈界河，乘景区巴士出山\"}]",
		},
		{
			ID:        "pub_xj_17",
			Title:     "罗布泊大海道无人区雅丹硬派越野",
			Region:    "xinjiang",
			Terrain:   "gobi_gravel",
			Category:  "thru",
			Diff:      5,
			Vehicle:   "4x4_extreme",
			DistKm:    385.0,
			EleGain:   450,
			EleMax:    1280,
			Duration:  "3天2夜",
			Season:    "4-5月, 9-10月",
			Downloads: 1260,
			Desc:      "古丝绸之路最神秘残酷的荒漠走廊。穿越哈密戈壁、红柳滩、核心雅丹魔鬼城城堡、火星基地至鄯善迪坎尔村。全程无信号、无水源、地表布满刀片状锋利碎石与暗沟陷沙坑，必须配备双备胎、北斗卫星通讯终端、脱困千斤顶及双车以上编队结伴穿行。",
			WptsJSON:  "[{\"id\": \"wp_xj17_1\", \"name\": \"哈密五堡镇了墩集结点\", \"lat\": 42.652, \"lon\": 92.852, \"ele\": 780, \"desc\": \"最后水源加注，检查双备胎与卫星通信\"}, {\"id\": \"wp_xj17_2\", \"name\": \"南湖黑戈壁锋利碎石带\", \"lat\": 42.412, \"lon\": 92.421, \"ele\": 920, \"desc\": \"刀片黑石减速慢行，严防高速爆胎\"}, {\"id\": \"wp_xj17_3\", \"name\": \"大海道外星人城堡雅丹\", \"lat\": 42.125, \"lon\": 91.895, \"ele\": 1050, \"desc\": \"千万年风蚀巨型城堡雅丹，风势呼啸\"}, {\"id\": \"wp_xj17_4\", \"name\": \"火星基地胶囊营地\", \"lat\": 41.952, \"lon\": 91.521, \"ele\": 1120, \"desc\": \"核心腹地扎营点，极度干燥备足饮用水\"}, {\"id\": \"wp_xj17_5\", \"name\": \"神仙石与断崖迷宫\", \"lat\": 41.825, \"lon\": 91.125, \"ele\": 1180, \"desc\": \"雅丹迷宫易迷失航向，严格依托离线GPS航迹\"}, {\"id\": \"wp_xj17_6\", \"name\": \"鄯善迪坎尔村接铺装路\", \"lat\": 42.682, \"lon\": 89.852, \"ele\": 350, \"desc\": \"抵达古村出荒漠，重回文明绿洲\"}]",
		},
		{
			ID:        "pub_xj_18",
			Title:     "塔克拉玛干沙漠公路纵穿 (G216)",
			Region:    "xinjiang",
			Terrain:   "desert_dune",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    552.0,
			EleGain:   180,
			EleMax:    1150,
			Duration:  "1~2天",
			Season:    "4月-11月(金秋胡杨季最佳)",
			Downloads: 1480,
			Desc:      "横跨“死亡之海”的世界级工程奇迹。由轮台出发跨越塔里木河胡杨林，一路向南直抵民丰县。全线被防沙芦苇方格与苦咸水滴灌红柳防护林包围。浩瀚起伏的沙海浩瀚无垠，需备足饮用水与检查空调滤芯防细沙进入。",
			WptsJSON:  "[{\"id\": \"wp_xj18_1\", \"name\": \"轮台沙漠公路零公里纪念碑\", \"lat\": 41.785, \"lon\": 84.252, \"ele\": 940, \"desc\": \"加满燃油，进入世界最长流动沙漠公路\"}, {\"id\": \"wp_xj18_2\", \"name\": \"塔里木河大桥与原始胡杨\", \"lat\": 41.215, \"lon\": 84.215, \"ele\": 920, \"desc\": \"深秋万亩胡杨倒映塔里木河两岸\"}, {\"id\": \"wp_xj18_3\", \"name\": \"肖塘水文监测水井房\", \"lat\": 40.582, \"lon\": 84.112, \"ele\": 980, \"desc\": \"沿线每4公里一座的护林滴灌水井房，可临时避暑\"}, {\"id\": \"wp_xj18_4\", \"name\": \"塔中油田沙漠深处小镇\", \"lat\": 38.985, \"lon\": 83.652, \"ele\": 1090, \"desc\": \"沙漠正中心石油基地，有加油站与餐馆\"}, {\"id\": \"wp_xj18_5\", \"name\": \"民丰县公路南端终点\", \"lat\": 37.052, \"lon\": 82.685, \"ele\": 1410, \"desc\": \"抵达南疆昆仑山北麓民丰，完成纵穿\"}]",
		},
		{
			ID:        "pub_xj_19",
			Title:     "克里雅古道昆仑秘境越野探险",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "thru",
			Diff:      5,
			Vehicle:   "4x4_extreme",
			DistKm:    260.0,
			EleGain:   3600,
			EleMax:    5450,
			Duration:  "4天3夜",
			Season:    "9月-10月(极短安全窗口期)",
			Downloads: 310,
			Desc:      "西藏阿里与南疆于田之间最凶险的昆仑天路。翻越火山群、硫磺达坂、阿特塔木达坂（5450m）与红柳滩。道路几乎全为高寒冻土融沉、碎石悬崖崩塌与冰川涉水冲沟，是国内越野探险的终极毕业路线之一。非顶配改装双锁重型四驱严禁涉足。",
			WptsJSON:  "[{\"id\": \"wp_xj19_1\", \"name\": \"于田县普鲁村最后补给点\", \"lat\": 36.325, \"lon\": 81.652, \"ele\": 2680, \"desc\": \"维吾尔族昆仑山古村，雇佣当地向导向昆仑进发\"}, {\"id\": \"wp_xj19_2\", \"name\": \"阿拉马斯玉矿岔口\", \"lat\": 36.012, \"lon\": 81.521, \"ele\": 3890, \"desc\": \"和田玉采掘古矿道，悬崖极窄路段\"}, {\"id\": \"wp_xj19_3\", \"name\": \"硫磺达坂地热温泉喷发区\", \"lat\": 35.752, \"lon\": 81.385, \"ele\": 4680, \"desc\": \"黄色硫磺结晶地貌，空气含硫气味刺鼻\"}, {\"id\": \"wp_xj19_4\", \"name\": \"阿特塔木达坂(5450m)\", \"lat\": 35.485, \"lon\": 81.215, \"ele\": 5450, \"desc\": \"全线最高难关，严寒缺氧极度考验车辆发动机进气与冷却\"}, {\"id\": \"wp_xj19_5\", \"name\": \"红柳滩G219新藏线接驳点\", \"lat\": 35.852, \"lon\": 79.125, \"ele\": 4250, \"desc\": \"驶入G219铺装公路，脱离极限险境\"}]",
		},
		{
			ID:        "pub_xj_20",
			Title:     "孟克特古道天山秘境穿越",
			Region:    "xinjiang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    72.0,
			EleGain:   2100,
			EleMax:    3490,
			Duration:  "3天2夜",
			Season:    "6月-9月",
			Downloads: 780,
			Desc:      "古代西汉乌孙国通道。由独库公路K625处切入，翻越门克廷达坂（海拔3490m），穿过天山高山明珠门克廷湖、乌兰萨德克湖（天山魔湖），出唐布拉百里画廊。沿途有大片枯木堰塞湖、高山雪岭云杉与温泉泉眼。",
			WptsJSON:  "[{\"id\": \"wp_xj20_1\", \"name\": \"独库公路K625徒步起点\", \"lat\": 44.025, \"lon\": 84.812, \"ele\": 1820, \"desc\": \"过铁索吊桥入峡谷，沿奎屯河上溯\"}, {\"id\": \"wp_xj20_2\", \"name\": \"天山魔湖(乌兰萨德克淖尔)\", \"lat\": 43.912, \"lon\": 84.625, \"ele\": 2210, \"desc\": \"枯死云杉直立湖中，水色碧绿宛如魔境\"}, {\"id\": \"wp_xj20_3\", \"name\": \"门克廷达坂雪坡(3490m)\", \"lat\": 43.785, \"lon\": 84.452, \"ele\": 3490, \"desc\": \"常年积雪翻越点，注意碎石坡防滑\"}, {\"id\": \"wp_xj20_4\", \"name\": \"温泉草滩营地\", \"lat\": 43.682, \"lon\": 84.285, \"ele\": 2450, \"desc\": \"天然硫磺热泉泡脚解乏，高山草甸宿营\"}, {\"id\": \"wp_xj20_5\", \"name\": \"唐布拉草原小华山出山口\", \"lat\": 43.612, \"lon\": 83.985, \"ele\": 1780, \"desc\": \"接百里画廊柏油路，乘车前往尼勒克\"}]",
		},
		{
			ID:        "pub_xz_21",
			Title:     "川藏南线 318 国道经典景观大道",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      3,
			Vehicle:   "suv_standard",
			DistKm:    1280.0,
			EleGain:   8900,
			EleMax:    5130,
			Duration:  "6~8天",
			Season:    "4-5月, 9-10月",
			Downloads: 3450,
			Desc:      "中国人的景观大道天花板。自芒康入藏，翻越东达山（5130m）、业拉山（4658m），挑战怒江七十二拐天险，穿过然乌湖冰川群、波密通麦天险特大桥、鲁朗林海与林芝雅鲁藏布江，直抵日光城拉萨布达拉宫。全线柏油化良好但高海拔地质滑坡多发，需留意落石。",
			WptsJSON:  "[{\"id\": \"wp_xz21_1\", \"name\": \"金沙江大桥(川藏交界)\", \"lat\": 29.752, \"lon\": 98.985, \"ele\": 2580, \"desc\": \"正式进入西藏自治区辖境\"}, {\"id\": \"wp_xz21_2\", \"name\": \"东达山垭口(5130m)\", \"lat\": 29.685, \"lon\": 97.892, \"ele\": 5130, \"desc\": \"318川藏段最高海拔垭口，常年大风降雪\"}, {\"id\": \"wp_xz21_3\", \"name\": \"业拉山怒江七十二拐观景台\", \"lat\": 30.125, \"lon\": 97.285, \"ele\": 4658, \"desc\": \"大落差盘山公路，使用低档发动机制动防刹车过热\"}, {\"id\": \"wp_xz21_4\", \"name\": \"然乌湖与米堆冰川\", \"lat\": 29.521, \"lon\": 96.752, \"ele\": 3850, \"desc\": \"冰川湖泊融水倒影，林芝门户\"}, {\"id\": \"wp_xz21_5\", \"name\": \"波密通麦特大桥\", \"lat\": 30.085, \"lon\": 95.125, \"ele\": 2080, \"desc\": \"昔日通麦天险排龙天险如今一桥飞架\"}, {\"id\": \"wp_xz21_6\", \"name\": \"色季拉山南迦巴瓦观景台\", \"lat\": 29.652, \"lon\": 94.621, \"ele\": 4728, \"desc\": \"十人九不遇的中国最美雪山南迦巴瓦峰\"}, {\"id\": \"wp_xz21_7\", \"name\": \"米拉山隧道(4752m)\", \"lat\": 29.852, \"lon\": 92.385, \"ele\": 4752, \"desc\": \"高海拔特长隧道，林芝与拉萨分水岭\"}, {\"id\": \"wp_xz21_8\", \"name\": \"拉萨布达拉宫广场\", \"lat\": 29.658, \"lon\": 91.118, \"ele\": 3650, \"desc\": \"圣城拉萨终点，圆梦朝圣之旅\"}]",
		},
		{
			ID:        "pub_xz_22",
			Title:     "川藏北线 317 国道人文探秘之路",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      4,
			Vehicle:   "4x4_high_clearance",
			DistKm:    1450.0,
			EleGain:   9200,
			EleMax:    5050,
			Duration:  "7~9天",
			Season:    "5-6月, 9-10月",
			Downloads: 1250,
			Desc:      "相比318更原始苍凉、宗教人文积淀更深厚的藏地秘境。由四川德格印经院入藏，经江达、昌都强巴林寺、类乌齐查杰玛大殿、丁青孜珠寺（悬崖苯教神庙）、巴青、索县赞丹寺抵那曲大草原，最终并入青藏公路抵拉萨。高海拔非铺装多，暗冰与坑洼频繁。",
			WptsJSON:  "[{\"id\": \"wp_xz22_1\", \"name\": \"德格印经院(甘孜西大门)\", \"lat\": 31.812, \"lon\": 98.582, \"ele\": 3280, \"desc\": \"藏文化大百科全书，木雕刻经板宝库\"}, {\"id\": \"wp_xz22_2\", \"name\": \"矮拉山特长隧道(川藏界)\", \"lat\": 31.685, \"lon\": 98.254, \"ele\": 3950, \"desc\": \"穿越分水岭正式进入西藏江达县\"}, {\"id\": \"wp_xz22_3\", \"name\": \"昌都强巴林寺与两江汇流\", \"lat\": 31.145, \"lon\": 97.185, \"ele\": 3240, \"desc\": \"昂曲与扎曲汇流为澜沧江，康区格鲁派第一大寺\"}, {\"id\": \"wp_xz22_4\", \"name\": \"类乌齐查杰玛大殿\", \"lat\": 31.215, \"lon\": 96.612, \"ele\": 3780, \"desc\": \"红白黑三色条纹建筑奇迹，达隆噶举派名刹\"}, {\"id\": \"wp_xz22_5\", \"name\": \"丁青孜珠寺(悬崖苯教神庙)\", \"lat\": 31.425, \"lon\": 95.582, \"ele\": 4850, \"desc\": \"海拔4850米怪石嶙峋鹰巢古寺，天险盘山土路\"}, {\"id\": \"wp_xz22_6\", \"name\": \"索县赞丹寺(小布达拉宫)\", \"lat\": 31.885, \"lon\": 93.785, \"ele\": 4010, \"desc\": \"依山而建雄伟气魄，进入藏北牧区\"}, {\"id\": \"wp_xj22_7\", \"name\": \"那曲草原接G109国道\", \"lat\": 31.472, \"lon\": 92.052, \"ele\": 4500, \"desc\": \"并入青藏公路南下直抵拉萨\"}]",
		},
		{
			ID:        "pub_xz_23",
			Title:     "新藏线 G219 世界最高海拔公路",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "thru",
			Diff:      5,
			Vehicle:   "4x4_high_clearance",
			DistKm:    2140.0,
			EleGain:   14200,
			EleMax:    5378,
			Duration:  "7~10天",
			Season:    "5-6月, 9-10月",
			Downloads: 1120,
			Desc:      "“行者之巅，生死新藏”。从新疆叶城零公里石碑启程，横跨昆仑山脉、喀喇昆仑山脉与冈底斯山脉，翻越库地达坂、麻扎达坂、界山达坂（5347m）、红土达坂（5378m），穿经死人沟（泉水沟极度缺氧区），沿班公错抵阿里日土、狮泉河直至拉孜。平均海拔超4500米，对人车抗高原极限考验极大。",
			WptsJSON:  "[{\"id\": \"wp_xz23_1\", \"name\": \"叶城零公里石碑\", \"lat\": 37.885, \"lon\": 77.412, \"ele\": 1365, \"desc\": \"检查边防证、车辆机油防冻液，出发誓师\"}, {\"id\": \"wp_xz23_2\", \"name\": \"麻扎达坂连续回头弯\", \"lat\": 36.582, \"lon\": 77.012, \"ele\": 4969, \"desc\": \"碎石寸草不生黑山峡谷，长下坡发动机制动\"}, {\"id\": \"wp_xj23_3\", \"name\": \"三十里营房驻地\", \"lat\": 36.352, \"lon\": 78.025, \"ele\": 3780, \"desc\": \"新藏线中途唯一正规医疗兵站补给点\"}, {\"id\": \"wp_xz23_4\", \"name\": \"死人沟(泉水沟高危缺氧区)\", \"lat\": 35.215, \"lon\": 79.552, \"ele\": 5120, \"desc\": \"极度低压缺氧高寒，禁止剧烈运动，非必要不停留\"}, {\"id\": \"wp_xz23_5\", \"name\": \"界山达坂(新疆西藏交界5347m)\", \"lat\": 34.985, \"lon\": 80.125, \"ele\": 5347, \"desc\": \"新藏公路最高纪念碑垭口，正式入藏\"}, {\"id\": \"wp_xz23_6\", \"name\": \"班公错中印界湖\", \"lat\": 33.452, \"lon\": 79.712, \"ele\": 4240, \"desc\": \"东淡西咸奇特狭长高原湖泊，水鸟栖息\"}, {\"id\": \"wp_xz23_7\", \"name\": \"日土宗古堡与岩画\", \"lat\": 33.225, \"lon\": 79.685, \"ele\": 4280, \"desc\": \"阿里高原第一重镇，山顶石城遗迹\"}, {\"id\": \"wp_xz23_8\", \"name\": \"拉孜G318线5000公里处\", \"lat\": 29.085, \"lon\": 87.652, \"ele\": 4010, \"desc\": \"新藏线终点接G318国道返回拉萨\"}]",
		},
		{
			ID:        "pub_xz_24",
			Title:     "阿里大北线荒原越野 (一错再错)",
			Region:    "xizang",
			Terrain:   "plateau_grassland",
			Category:  "thru",
			Diff:      5,
			Vehicle:   "4x4_high_clearance",
			DistKm:    2420.0,
			EleGain:   12500,
			EleMax:    5360,
			Duration:  "10~12天",
			Season:    "5-6月, 9-10月",
			Downloads: 1540,
			Desc:      "无阿里，不西藏；无大北，不荒原。深入藏北羌塘国家级自然保护区边缘，拥抱野生藏羚羊、野牦牛与藏野驴。途经圣湖玛旁雍错、神山冈仁波齐、狮泉河、仁多、错勤、扎日南木错、当惹雍错（古象雄文明腹地）、色林错、班戈直至纳木错。路况涵盖数百公里搓板碎石非铺装路，需严控补给燃油。",
			WptsJSON:  "[{\"id\": \"wp_xz24_1\", \"name\": \"拉萨布宫出发\", \"lat\": 29.658, \"lon\": 91.118, \"ele\": 3650, \"desc\": \"检查全车胎压与高反救援应急物资\"}, {\"id\": \"wp_xz24_2\", \"name\": \"神山冈仁波齐塔钦\", \"lat\": 31.025, \"lon\": 81.285, \"ele\": 4680, \"desc\": \"四大宗教宇宙中心，玛旁雍错圣湖守望\"}, {\"id\": \"wp_xz24_3\", \"name\": \"札达土林与古格遗址\", \"lat\": 31.485, \"lon\": 79.852, \"ele\": 3750, \"desc\": \"百万年地壳隆起峡谷古城堡遗迹\"}, {\"id\": \"wp_xz24_4\", \"name\": \"狮泉河镇(阿里行署)\", \"lat\": 32.502, \"lon\": 80.105, \"ele\": 4280, \"desc\": \"大北线起点补给站，加满所有备用油桶\"}, {\"id\": \"wp_xz24_5\", \"name\": \"仁多乡高原搓板路\", \"lat\": 31.952, \"lon\": 83.421, \"ele\": 4820, \"desc\": \"正式进入一错再错无人荒原，无手机网络\"}, {\"id\": \"wp_xz24_6\", \"name\": \"当惹雍错·文布南村\", \"lat\": 31.052, \"lon\": 86.582, \"ele\": 4580, \"desc\": \"笨教最大圣湖，古象雄文明遗址，湖畔石屋\"}, {\"id\": \"wp_xz24_7\", \"name\": \"色林错(西藏第一大湖)\", \"lat\": 31.852, \"lon\": 88.985, \"ele\": 4540, \"desc\": \"浩瀚魔鬼湖，藏羚羊种群穿行\"}, {\"id\": \"wp_xz24_8\", \"name\": \"当雄县返回拉萨闭环\", \"lat\": 30.485, \"lon\": 91.105, \"ele\": 4280, \"desc\": \"并入G109京藏高速，完成大北线闭环\"}]",
		},
		{
			ID:        "pub_xz_25",
			Title:     "冈仁波齐神山高海拔转山路书",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    52.0,
			EleGain:   1580,
			EleMax:    5648,
			Duration:  "2天1夜",
			Season:    "5-10月",
			Downloads: 2150,
			Desc:      "藏传佛教、印度教、苯教共同尊奉的“神山之王”。从塔钦出发，顺时针环绕冈仁波齐峰。首日由塔钦徒步至止热寺，近距离凝望神山北壁日照金山；次日翻越全程最高险阻“卓玛拉达坂”（海拔5648米），经过慈悲湖（托吉错）下至祖楚寺返程。需极强抗高反体能与防风保暖装备。",
			WptsJSON:  "[{\"id\": \"wp_xz25_1\", \"name\": \"塔钦小镇转山起点\", \"lat\": 30.985, \"lon\": 81.285, \"ele\": 4680, \"desc\": \"清晨出发，登山杖、高能量路粮齐备\"}, {\"id\": \"wp_xz25_2\", \"name\": \"经幡广场(双腿佛塔)\", \"lat\": 31.025, \"lon\": 81.252, \"ele\": 4780, \"desc\": \"仰望神山南壁，虔诚藏民朝圣叩长头起点\"}, {\"id\": \"wp_xz25_3\", \"name\": \"止热寺(神山北壁正对点)\", \"lat\": 31.115, \"lon\": 81.295, \"ele\": 5080, \"desc\": \"首夜宿营客栈，神山北壁金字塔壮美日照金山\"}, {\"id\": \"wp_xz25_4\", \"name\": \"卓玛拉达坂最高点(5648m)\", \"lat\": 31.139, \"lon\": 81.348, \"ele\": 5648, \"desc\": \"挂经幡撒隆达祈福，不可长时间停留防严重失温\"}, {\"id\": \"wp_xz25_5\", \"name\": \"慈悲湖(托吉错绿翡翠)\", \"lat\": 31.135, \"lon\": 81.355, \"ele\": 5580, \"desc\": \"达坂下方万年冰川高山湖泊，急陡碎石下坡防滑\"}, {\"id\": \"wp_xz25_6\", \"name\": \"塔钦终点圆满\", \"lat\": 30.985, \"lon\": 81.285, \"ele\": 4680, \"desc\": \"完成52公里神山洗礼，功德圆满\"}]",
		},
		{
			ID:        "pub_xz_26",
			Title:     "珠峰东坡·嘎玛沟世界顶级徒步",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    85.0,
			EleGain:   4200,
			EleMax:    5350,
			Duration:  "7天6夜",
			Season:    "5-6月, 9-10月",
			Downloads: 780,
			Desc:      "美国《国家地理》评选的“世界十大顶级徒步路线”之一。置身喜马拉雅腹地原始森林与冰川峡谷，同时面对珠穆朗玛峰（8848m）、洛子峰（8516m）、马卡鲁峰（8463m）三座八千米级巨峰东壁冰川。需翻越海拔5350米的朗玛拉达坂，全程雇佣牦牛工驮运物资。",
			WptsJSON:  "[{\"id\": \"wp_xz26_1\", \"name\": \"定日县曲当乡优帕村\", \"lat\": 28.012, \"lon\": 87.285, \"ele\": 3750, \"desc\": \"徒步起点，办理边防与牦牛队接洽\"}, {\"id\": \"wp_xz26_2\", \"name\": \"晓乌措冰川湖营地\", \"lat\": 28.052, \"lon\": 87.185, \"ele\": 4650, \"desc\": \"高山碧蓝海子扎营，倒映马卡鲁雪山\"}, {\"id\": \"wp_xz26_3\", \"name\": \"晓乌拉达坂(4900m)\", \"lat\": 28.085, \"lon\": 28.085, \"ele\": 4900, \"desc\": \"进入嘎玛沟原始峡谷杜鹃林分界点\"}, {\"id\": \"wp_xz26_4\", \"name\": \"汤湘高山观景台营地\", \"lat\": 28.125, \"lon\": 87.052, \"ele\": 4050, \"desc\": \"正对嘎玛沟谷地与洛子峰冰川瀑布\"}, {\"id\": \"wp_xz26_5\", \"name\": \"白当营地(珠峰东坡正对点)\", \"lat\": 28.015, \"lon\": 86.952, \"ele\": 4950, \"desc\": \"近距离仰望世界最高峰巨型冰壁震撼景致\"}, {\"id\": \"wp_xz26_6\", \"name\": \"朗玛拉达坂最高峰(5350m)\", \"lat\": 28.152, \"lon\": 87.185, \"ele\": 5350, \"desc\": \"全线最险峻垭口，冰雪与巨石混合路段\"}, {\"id\": \"wp_xz26_7\", \"name\": \"轮朱林村出山终点\", \"lat\": 28.085, \"lon\": 87.325, \"ele\": 3950, \"desc\": \"乘车返回日喀则，完成世界屋脊漫步\"}]",
		},
		{
			ID:        "pub_xz_27",
			Title:     "库拉岗日神山三神湖经典徒步",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    38.0,
			EleGain:   1650,
			EleMax:    4850,
			Duration:  "3天2夜",
			Season:    "5月-10月",
			Downloads: 1160,
			Desc:      "山南洛扎县境内的秘境雪山湖泊天堂。仰望海拔7538米的藏南第一神山库拉岗日，探访如宝石般镶嵌在雪峰下的白玛林错、折公措、介久措三座圣湖。路况多高山碎石山道与草甸步道，风景纯美，游客相对较少。",
			WptsJSON:  "[{\"id\": \"wp_xz27_1\", \"name\": \"洛扎县色乡错玉村起点\", \"lat\": 28.285, \"lon\": 90.852, \"ele\": 4120, \"desc\": \"进山前在藏民家安顿，租用当地向导\"}, {\"id\": \"wp_xz27_2\", \"name\": \"白玛林错观景台\", \"lat\": 28.215, \"lon\": 90.785, \"ele\": 4550, \"desc\": \"蓝绿相间圣湖，传闻能看到前世今生的圣湖\"}, {\"id\": \"wp_xz27_3\", \"name\": \"折公三措分水岭\", \"lat\": 28.185, \"lon\": 90.752, \"ele\": 4850, \"desc\": \"三个阶梯状湖泊连成一串，雪山倒影\"}, {\"id\": \"wp_xz27_4\", \"name\": \"介久措与库拉岗日主峰冰川\", \"lat\": 28.152, \"lon\": 90.712, \"ele\": 4700, \"desc\": \"翡翠绿色湖水，正面迎接库拉岗日七千米冰壁\"}, {\"id\": \"wp_xz27_5\", \"name\": \"错玉村终点\", \"lat\": 28.285, \"lon\": 90.852, \"ele\": 4120, \"desc\": \"返回村庄，乘车前往洛扎县城\"}]",
		},
		{
			ID:        "pub_xz_28",
			Title:     "丙察察“魔鬼越野进藏路”",
			Region:    "xizang",
			Terrain:   "canyon_gorge",
			Category:  "offroad",
			Diff:      5,
			Vehicle:   "4x4_extreme",
			DistKm:    286.0,
			EleGain:   4200,
			EleMax:    4720,
			Duration:  "2~3天",
			Season:    "5-6月, 9-10月",
			Downloads: 1680,
			Desc:      "昔日“最艰险的进藏越野公路”。自云南怒江贡山丙中洛出发，经过秋那桶进入西藏察瓦龙，挑战令人闻风丧胆的“大流沙”（落石如瀑布）、滚石坡，再翻越齐马拉达坂（4630m）、昌拉达坂直达察隅。沿途峡谷悬崖深达数百米，必须硬派四驱车辆并随时提防高空坠石。",
			WptsJSON:  "[{\"id\": \"wp_xz28_1\", \"name\": \"丙中洛人神共居之乡\", \"lat\": 28.012, \"lon\": 98.595, \"ele\": 1750, \"desc\": \"怒江第一湾观景，出发前检查底盘护板\"}, {\"id\": \"wp_xz28_2\", \"name\": \"秋那桶峡谷滇藏界碑\", \"lat\": 28.185, \"lon\": 98.572, \"ele\": 1820, \"desc\": \"进入西藏自治区林芝察隅县境\"}, {\"id\": \"wp_xz28_3\", \"name\": \"大流沙天险(生死关卡)\", \"lat\": 28.325, \"lon\": 98.485, \"ele\": 1950, \"desc\": \"巨型碎石滑坡带，观察山顶动静，一脚油门快速通过切勿鸣笛\"}, {\"id\": \"wp_xz28_4\", \"name\": \"察瓦龙镇怒江干热河谷\", \"lat\": 28.452, \"lon\": 98.452, \"ele\": 1980, \"desc\": \"仙人掌遍野的干热小镇，首晚宿营加汽油\"}, {\"id\": \"wp_xz28_5\", \"name\": \"甲应村神山隐秘岔口\", \"lat\": 28.582, \"lon\": 98.352, \"ele\": 3200, \"desc\": \"梅里雪山西坡绝壁古村分道口\"}, {\"id\": \"wp_xz28_6\", \"name\": \"雄楚拉达坂垭口(4630m)\", \"lat\": 28.652, \"lon\": 98.152, \"ele\": 4630, \"desc\": \"高山原始红杉冷杉林，气温骤降\"}, {\"id\": \"wp_xz28_7\", \"name\": \"目若村高山牧场\", \"lat\": 28.521, \"lon\": 97.852, \"ele\": 3720, \"desc\": \"黑青稞与藏香猪成群，纯净原始\"}, {\"id\": \"wp_xz28_8\", \"name\": \"察隅县城水乡终点\", \"lat\": 28.658, \"lon\": 97.462, \"ele\": 2350, \"desc\": \"西藏江南察隅，连接省道完成传奇越野\"}]",
		},
		{
			ID:        "pub_xz_29",
			Title:     "山南藏文化发祥地深度大环线",
			Region:    "xizang",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    850.0,
			EleGain:   4800,
			EleMax:    5070,
			Duration:  "4天3夜",
			Season:    "4-10月",
			Downloads: 1050,
			Desc:      "探索藏民族摇篮与早期文明源头。从拉萨出发，翻越岗巴拉山俯瞰羊卓雍错珊瑚碧玉蓝，抵普莫雍错看“天空之泪”与库拉岗日，穿过洛扎碉楼群、乃东雍布拉康（西藏第一座宫殿）、桑耶寺（西藏第一座佛法僧俱全寺院）返回拉萨。",
			WptsJSON:  "[{\"id\": \"wp_xz29_1\", \"name\": \"拉萨滨河大道出发\", \"lat\": 29.658, \"lon\": 91.118, \"ele\": 3650, \"desc\": \"出城沿雅鲁藏布江一路向南\"}, {\"id\": \"wp_xz29_2\", \"name\": \"岗巴拉山垭口(羊卓雍错)\", \"lat\": 29.185, \"lon\": 90.625, \"ele\": 4998, \"desc\": \"俯瞰羊湖蜿蜒深蓝湖水与宁金抗沙峰\"}, {\"id\": \"wp_xz29_3\", \"name\": \"普莫雍错推村(海拔5010m)\", \"lat\": 28.521, \"lon\": 90.452, \"ele\": 5010, \"desc\": \"世界海拔最高行政村，冬季蓝冰羊群转场\"}, {\"id\": \"wp_xz29_4\", \"name\": \"洛扎藏东石碉楼群\", \"lat\": 28.385, \"lon\": 90.852, \"ele\": 3820, \"desc\": \"悬崖绝壁防御性千年古碉楼群\"}, {\"id\": \"wp_xz29_5\", \"name\": \"雍布拉康(西藏第一宫殿)\", \"lat\": 29.152, \"lon\": 91.785, \"ele\": 3700, \"desc\": \"雅砻河谷耸立石崖古堡，藏王聂赤赞普行宫\"}, {\"id\": \"wp_xz29_6\", \"name\": \"桑耶寺(坛城宇宙构型)\", \"lat\": 29.325, \"lon\": 91.512, \"ele\": 3620, \"desc\": \"莲花生大师亲自主持修建，藏汉印三合一风格\"}, {\"id\": \"wp_xz29_7\", \"name\": \"拉萨贡嘎大桥闭环\", \"lat\": 29.285, \"lon\": 90.952, \"ele\": 3580, \"desc\": \"返回拉萨市区完成山南文明大环线\"}]",
		},
		{
			ID:        "pub_xz_30",
			Title:     "阿里中线无人区穿越 (大北线精华)",
			Region:    "xizang",
			Terrain:   "plateau_grassland",
			Category:  "thru",
			Diff:      5,
			Vehicle:   "4x4_extreme",
			DistKm:    980.0,
			EleGain:   5200,
			EleMax:    5150,
			Duration:  "5天4夜",
			Season:    "5-6月, 9-10月",
			Downloads: 580,
			Desc:      "介于阿里南线与大北线之间的极野探索通道。深入无路之境的羌塘荒原，自改则向南穿越洞错、达瓦错、扎布耶茶卡（世界三大锂盐湖之一的粉红色盐湖）、塔若错直至措勤。必须备足备用燃油（中途超500公里无正规加油站）、强光射灯与卫星通信。",
			WptsJSON:  "[{\"id\": \"wp_xz30_1\", \"name\": \"改则县城最后加油站\", \"lat\": 32.302, \"lon\": 84.065, \"ele\": 4500, \"desc\": \"加满全车与备用油桶，检查双备胎\"}, {\"id\": \"wp_xz30_2\", \"name\": \"洞错高原咸水湖畔\", \"lat\": 32.215, \"lon\": 84.452, \"ele\": 4480, \"desc\": \"湖畔天然土路，藏野驴群在此奔跑\"}, {\"id\": \"wp_xz30_3\", \"name\": \"达瓦错月亮之湖\", \"lat\": 31.252, \"lon\": 84.952, \"ele\": 4650, \"desc\": \"宛如一弯新月的蓝色湖泊，无信号区\"}, {\"id\": \"wp_xz30_4\", \"name\": \"扎布耶茶卡(粉红锂盐湖)\", \"lat\": 31.352, \"lon\": 84.152, \"ele\": 4420, \"desc\": \"世界第三大锂盐湖，卤水结晶呈现神奇粉红色\"}, {\"id\": \"wp_xz30_5\", \"name\": \"塔若错与布嘎寺\", \"lat\": 31.125, \"lon\": 83.985, \"ele\": 4560, \"desc\": \"沿湖沙石路，水鸟聚集地\"}, {\"id\": \"wp_xz30_6\", \"name\": \"措勤县城重回铺装路\", \"lat\": 31.025, \"lon\": 85.152, \"ele\": 4700, \"desc\": \"完成阿里中线纯野路穿行\"}]",
		},
		{
			ID:        "pub_xz_31",
			Title:     "希夏邦马峰南坡大本营徒步",
			Region:    "xizang",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    42.0,
			EleGain:   1850,
			EleMax:    4350,
			Duration:  "2天1夜",
			Season:    "5月-10月",
			Downloads: 850,
			Desc:      "探访唯一一座完全在中国境内的八千米级极高峰（8027m）。从吉隆县宗嘎镇向乃村进发，俯瞰佩枯措湛蓝湖水，近观希峰南坡巨大的现代悬冰川与冰塔林。视野极度开阔，高原草甸上藏原羚跳跃。",
			WptsJSON:  "[{\"id\": \"wp_xz31_1\", \"name\": \"佩枯措湖畔营地\", \"lat\": 28.612, \"lon\": 85.852, \"ele\": 4590, \"desc\": \"佩枯措与希夏邦马雪山倒影起点\"}, {\"id\": \"wp_xz31_2\", \"name\": \"乃村高山观景台\", \"lat\": 28.452, \"lon\": 85.325, \"ele\": 4150, \"desc\": \"吉隆沟云海与雪山全景天然观礼台\"}, {\"id\": \"wp_xj31_3\", \"name\": \"希峰南坡冰川末端\", \"lat\": 28.325, \"lon\": 85.785, \"ele\": 4350, \"desc\": \"巨大的冰碛物堆积垄，仰视8027m雪山主峰\"}, {\"id\": \"wp_xz31_4\", \"name\": \"吉隆沟口口岸通道\", \"lat\": 28.285, \"lon\": 85.252, \"ele\": 2800, \"desc\": \"返回中尼边境吉隆口岸，完成徒步\"}]",
		},
		{
			ID:        "pub_xz_32",
			Title:     "滇藏线 G214 穿越梅里与盐井",
			Region:    "xizang",
			Terrain:   "canyon_gorge",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    430.0,
			EleGain:   3100,
			EleMax:    4292,
			Duration:  "2~3天",
			Season:    "4-6月, 9-11月",
			Downloads: 2200,
			Desc:      "彩云之南入藏的茶马古道经典脉络。由香格里拉独克宗古城出发，经奔子栏金沙江大拐弯、翻越白马雪山垭口（4292m），朝拜梅里雪山卡瓦格博峰日照金山，进入西藏芒康盐井（品尝千年古盐田与加加面），在芒康汇入318国道。",
			WptsJSON:  "[{\"id\": \"wp_xz32_1\", \"name\": \"香格里拉独克宗月光城\", \"lat\": 27.812, \"lon\": 99.712, \"ele\": 3280, \"desc\": \"世界最大转经筒，滇藏自驾始发站\"}, {\"id\": \"wp_xz32_2\", \"name\": \"金沙江大拐弯(月亮湾)\", \"lat\": 28.254, \"lon\": 99.312, \"ele\": 2180, \"desc\": \"Ω形巨型河湾，干热河谷地貌\"}, {\"id\": \"wp_xz32_3\", \"name\": \"白马雪山老路垭口(4292m)\", \"lat\": 28.352, \"lon\": 99.012, \"ele\": 4292, \"desc\": \"高山杜鹃林与流石滩，远眺白马雪山U型冰川谷\"}, {\"id\": \"wp_xz32_4\", \"name\": \"德钦飞来寺观景台\", \"lat\": 28.452, \"lon\": 98.885, \"ele\": 3450, \"desc\": \"朝圣梅里雪山十三峰日照金山第一圣地\"}, {\"id\": \"wp_xz32_5\", \"name\": \"西藏芒康千年古盐田\", \"lat\": 29.025, \"lon\": 98.612, \"ele\": 2350, \"desc\": \"澜沧江畔层叠木质晒盐架，品尝特色加加面\"}, {\"id\": \"wp_xz32_6\", \"name\": \"芒康县城接G318国道\", \"lat\": 29.685, \"lon\": 98.595, \"ele\": 3880, \"desc\": \"滇藏线与川藏南线交汇点\"}]",
		},
		{
			ID:        "pub_cx_33",
			Title:     "洛克之路 (扎尕那-迭部-若尔盖)",
			Region:    "chuanxi",
			Terrain:   "forest_mountain",
			Category:  "overland",
			Diff:      3,
			Vehicle:   "at_tire",
			DistKm:    115.0,
			EleGain:   1250,
			EleMax:    3950,
			Duration:  "1天",
			Season:    "5-10月",
			Downloads: 1420,
			Desc:      "追寻探险家约瑟夫·洛克的足迹。穿越甘南迭部扎尕那巨石城堡，翻越光盖山垭口（海拔3950米），跨越白龙江发源地峡谷直达若尔盖草原。沿途尽是石灰岩巨壁、高山流石滩、暗针叶林与高山草甸，被越野探险界公认为“中国最壮丽的峡谷天路”。",
			WptsJSON:  "[{\"id\": \"wp_cx33_1\", \"name\": \"扎尕那东哇村石城起点\", \"lat\": 34.248, \"lon\": 103.215, \"ele\": 2980, \"desc\": \"清晨观云雾石城仙境，检查四驱与胎压\"}, {\"id\": \"wp_cx33_2\", \"name\": \"老虎嘴峡谷崖壁公路\", \"lat\": 34.285, \"lon\": 103.185, \"ele\": 3420, \"desc\": \"悬崖峭壁擦肩而过，注意弯道盲区与会车鸣笛\"}, {\"id\": \"wp_cx33_3\", \"name\": \"光盖山分水岭垭口(3950m)\", \"lat\": 34.325, \"lon\": 103.152, \"ele\": 3950, \"desc\": \"洛克之路最高峰，眺望层峦石海与迭山主峰\"}, {\"id\": \"wp_cx33_4\", \"name\": \"贡巴寺高山牧区\", \"lat\": 34.385, \"lon\": 103.085, \"ele\": 3480, \"desc\": \"下行至峡谷牧区，夏季野花漫山\"}, {\"id\": \"wp_cx33_5\", \"name\": \"卓尼大峪沟公路岔口\", \"lat\": 34.452, \"lon\": 103.025, \"ele\": 2850, \"desc\": \"汇入国道完成洛克之路穿越\"}]",
		},
		{
			ID:        "pub_cx_34",
			Title:     "格涅神山大环线越野穿越",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "offroad",
			Diff:      4,
			Vehicle:   "4x4_high_clearance",
			DistKm:    235.0,
			EleGain:   2850,
			EleMax:    4820,
			Duration:  "2~3天",
			Season:    "6-10月",
			Downloads: 980,
			Desc:      "川西深处最后的越野净土。自理塘毛垭大草原切入，环抱格涅神山雪峰（6204m）。打卡大地明眸“格涅之眼”、依崖而建的冷古寺老庙、热梯大峡谷温泉与波密乡。路况多碎石炮弹坑、冲沟与泥浆漫水路，必须四驱硬派SUV并携带备胎。",
			WptsJSON:  "[{\"id\": \"wp_cx34_1\", \"name\": \"理塘毛垭大草原西入口\", \"lat\": 30.052, \"lon\": 100.125, \"ele\": 4010, \"desc\": \"从G318切入格涅南线砂石路\"}, {\"id\": \"wp_cx34_2\", \"name\": \"铁匠山古冰帽垭口(4770m)\", \"lat\": 29.952, \"lon\": 99.852, \"ele\": 4770, \"desc\": \"怪石嶙峋古冰帽遗迹，远眺格涅群峰\"}, {\"id\": \"wp_cx34_3\", \"name\": \"格涅之眼(水塘奇观)\", \"lat\": 29.825, \"lon\": 99.652, \"ele\": 4150, \"desc\": \"圆形水草湿地宛如大地之眸，倒映雪山金顶\"}, {\"id\": \"wp_cx34_4\", \"name\": \"老冷古寺肖扎神山下\", \"lat\": 29.712, \"lon\": 99.512, \"ele\": 4120, \"desc\": \"藏传佛教噶玛噶举派著名古寺，三件圣物\"}, {\"id\": \"wp_cx34_5\", \"name\": \"热梯河谷草甸碎石滩\", \"lat\": 29.652, \"lon\": 99.385, \"ele\": 4350, \"desc\": \"碎石河滩极易刮底盘，严格缓行\"}, {\"id\": \"wp_cx34_6\", \"name\": \"劳者龙巴垭口(4820m)\", \"lat\": 29.782, \"lon\": 99.215, \"ele\": 4820, \"desc\": \"格涅环线最高达坂，风雪高发地带\"}, {\"id\": \"wp_cx34_7\", \"name\": \"巴塘县城接G318国道\", \"lat\": 30.005, \"lon\": 99.105, \"ele\": 2580, \"desc\": \"出峡谷完成格涅大环线越野\"}]",
		},
		{
			ID:        "pub_cx_35",
			Title:     "贡嘎雪山全线重装大环线徒步",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    76.5,
			EleGain:   3100,
			EleMax:    4920,
			Duration:  "4天3夜",
			Season:    "5-6月, 9-10月",
			Downloads: 1380,
			Desc:      "朝圣“蜀山之王”（7556米）的殿堂级重装徒步路线。由康定老榆林电站出发，穿过格西草原、两岔河，翻越海拔4920米冰雪覆盖的日乌且达坂，经莫溪沟谷地抵达六百年历史的贡嘎寺，最后翻越子梅垭口眺望贡嘎群峰云海。需准备高海拔抗低温零下防寒装备。",
			WptsJSON:  "[{\"id\": \"wp_cx35_1\", \"name\": \"老榆林水库电站起点\", \"lat\": 29.985, \"lon\": 101.952, \"ele\": 2880, \"desc\": \"向导挑夫汇合，检查冰爪防风软壳\"}, {\"id\": \"wp_cx35_2\", \"name\": \"格西草原营地\", \"lat\": 29.895, \"lon\": 101.885, \"ele\": 3400, \"desc\": \"高山草甸开阔地，首晚适应海拔扎营\"}, {\"id\": \"wp_cx35_3\", \"name\": \"上日乌且冰川营地\", \"lat\": 29.785, \"lon\": 101.812, \"ele\": 4350, \"desc\": \"雪山冰川脚下，气温直逼冰点\"}, {\"id\": \"wp_cx35_4\", \"name\": \"日乌且达坂垭口(4920m)\", \"lat\": 29.742, \"lon\": 101.785, \"ele\": 4920, \"desc\": \"全线最高难关，碎石巨石坡，注意滑坠\"}, {\"id\": \"wp_cx35_5\", \"name\": \"贡嘎寺(主峰正对朝拜点)\", \"lat\": 29.612, \"lon\": 101.785, \"ele\": 3750, \"desc\": \"面对贡嘎主峰冰川，藏传佛教古寺\"}, {\"id\": \"wp_cx35_6\", \"name\": \"子梅垭口云海观景台\", \"lat\": 29.582, \"lon\": 101.745, \"ele\": 4550, \"desc\": \"贡嘎主峰云海日落最佳摄影平台\"}, {\"id\": \"wp_cx35_7\", \"name\": \"上木居村乘车出山\", \"lat\": 29.521, \"lon\": 101.685, \"ele\": 3720, \"desc\": \"徒步终点，乘车前往康定返程\"}]",
		},
		{
			ID:        "pub_cx_36",
			Title:     "四姑娘山长坪沟-毕棚沟“长毕穿越”",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    36.0,
			EleGain:   1550,
			EleMax:    4668,
			Duration:  "2天1夜",
			Season:    "5月-10月",
			Downloads: 2100,
			Desc:      "川西最经典的高山徒步跨越线。从四姑娘山长坪沟喇嘛寺出发，沿着原始森林峡谷经木骡子、叉子沟营地，凌晨冲顶翻越海拔4668米的毕棚沟垭口，下行进入阿坝理县毕棚沟三棵树红石滩出山。需备好雪套、高帮防水徒步鞋与简易冰爪。",
			WptsJSON:  "[{\"id\": \"wp_cx36_1\", \"name\": \"长坪沟景区喇嘛寺栈道起点\", \"lat\": 30.985, \"lon\": 102.885, \"ele\": 3400, \"desc\": \"四姑娘山传统栈道步入森林碎石道\"}, {\"id\": \"wp_cx36_2\", \"name\": \"枯树滩与木骡子高山大草甸\", \"lat\": 31.052, \"lon\": 102.852, \"ele\": 3760, \"desc\": \"仰望婆缪峰、幺妹峰后侧冰壁，绝佳露营地\"}, {\"id\": \"wp_cx36_3\", \"name\": \"叉子沟尾营地(海拔3900m)\", \"lat\": 31.125, \"lon\": 102.812, \"ele\": 3900, \"desc\": \"凌晨3点拔营冲顶准备，补充高能热食\"}, {\"id\": \"wp_cx36_4\", \"name\": \"长毕达坂垭口(4668m)\", \"lat\": 31.185, \"lon\": 102.785, \"ele\": 4668, \"desc\": \"风口极冷，翻过垭口即进入阿坝理县\"}, {\"id\": \"wp_cx36_5\", \"name\": \"毕棚沟三棵树红石滩出口\", \"lat\": 31.252, \"lon\": 102.752, \"ele\": 3600, \"desc\": \"乘毕棚沟电瓶车出景区，完成穿越\"}]",
		},
		{
			ID:        "pub_cx_37",
			Title:     "四姑娘山二峰初级雪山攀登",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    28.0,
			EleGain:   1850,
			EleMax:    5276,
			Duration:  "3天2夜",
			Season:    "4月-11月",
			Downloads: 1850,
			Desc:      "户外爱好者的“人生第一座5000米雪山”。海拔5276米。由日隆镇（四姑娘山镇）海子沟入山，经朝山坪、打尖包抵大本营（4300m），凌晨登顶。线路成熟安全，配备协作与冰爪头盔即可体验真正的雪峰攀登成就感。",
			WptsJSON:  "[{\"id\": \"wp_cx37_1\", \"name\": \"海子沟售票处进山马道\", \"lat\": 30.985, \"lon\": 102.852, \"ele\": 3200, \"desc\": \"高山草甸起步爬升，体能分配至关重要\"}, {\"id\": \"wp_cx37_2\", \"name\": \"朝山坪锅庄坪观景台\", \"lat\": 31.012, \"lon\": 102.865, \"ele\": 3650, \"desc\": \"正面一字排开的四姑娘山四座雪峰\"}, {\"id\": \"wp_cx37_3\", \"name\": \"打尖包休息补给中继木屋\", \"lat\": 31.052, \"lon\": 102.875, \"ele\": 3780, \"desc\": \"热泡面、红牛补给点，分岔口向二峰营地\"}, {\"id\": \"wp_cx37_4\", \"name\": \"二峰高山大本营(4300m)\", \"lat\": 31.095, \"lon\": 102.895, \"ele\": 4300, \"desc\": \"石头木屋或帐篷扎营，早歇备战凌晨2点冲顶\"}, {\"id\": \"wp_cx37_5\", \"name\": \"碎石大陡坡与垭口拉绳处\", \"lat\": 31.115, \"lon\": 102.912, \"ele\": 4950, \"desc\": \"穿戴冰爪与安全头盔，抓握路绳攀升\"}, {\"id\": \"wp_cx37_6\", \"name\": \"四姑娘山二峰峰顶(5276m)\", \"lat\": 31.125, \"lon\": 102.918, \"ele\": 5276, \"desc\": \"登顶眺望幺妹峰傲立云海，热泪盈眶\"}]",
		},
		{
			ID:        "pub_cx_38",
			Title:     "稻城亚丁三神山大环线徒步",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    62.0,
			EleGain:   2900,
			EleMax:    4750,
			Duration:  "3天2夜",
			Season:    "5月-10月",
			Downloads: 1750,
			Desc:      "香格里拉之魂。环绕仙乃日（观音）、央迈勇（文殊）、夏诺多吉（金刚手）三座呈品字形排列的圣洁雪山。由亚丁龙同坝、洛绒牛场出发，探访牛奶海、五色海，翻越央迈勇垭口经松多垭口沿卡斯地狱谷下行。高海拔冰川流石与缺氧挑战极大。",
			WptsJSON:  "[{\"id\": \"wp_cx38_1\", \"name\": \"亚丁冲古寺与珍珠海\", \"lat\": 28.452, \"lon\": 100.352, \"ele\": 3880, \"desc\": \"仙乃日雪山下碧绿海子\"}, {\"id\": \"wp_cx38_2\", \"name\": \"洛绒牛场贡嘎河曲草甸\", \"lat\": 28.395, \"lon\": 100.412, \"ele\": 4180, \"desc\": \"三座神山汇聚中心，纯净的高山牧场\"}, {\"id\": \"wp_cx38_3\", \"name\": \"牛奶海与五色海(海拔4600m)\", \"lat\": 28.362, \"lon\": 100.385, \"ele\": 4600, \"desc\": \"折射五彩光芒的古冰斗湖泊\"}, {\"id\": \"wp_cx38_4\", \"name\": \"央迈勇松多垭口(4750m)\", \"lat\": 28.325, \"lon\": 100.352, \"ele\": 4750, \"desc\": \"全线最高点，直面央迈勇冰壁\"}, {\"id\": \"wp_cx38_5\", \"name\": \"卡斯地狱谷幽深峡谷\", \"lat\": 28.352, \"lon\": 100.252, \"ele\": 3200, \"desc\": \"原始密林瀑布怪石，穿越出山\"}]",
		},
		{
			ID:        "pub_cx_39",
			Title:     "党岭·葫芦海-丹巴自驾徒步线",
			Region:    "chuanxi",
			Terrain:   "forest_mountain",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "at_tire",
			DistKm:    68.0,
			EleGain:   1150,
			EleMax:    4200,
			Duration:  "2天1夜",
			Season:    "5-6月杜鹃, 9-10月秋色彩林",
			Downloads: 1120,
			Desc:      "丹巴嘉绒藏族风情与高山海子仙境。从中国最美乡村丹巴甲居藏寨出发，深入边耳乡党岭村，轻装或骑马徒步至海拔4160米的葫芦海（形似葫芦的高山海子）。温泉野汤与雪山倒影交织，秋季彩林绚烂夺目。",
			WptsJSON:  "[{\"id\": \"wp_cx39_1\", \"name\": \"丹巴甲居藏寨观景台\", \"lat\": 30.885, \"lon\": 101.852, \"ele\": 2050, \"desc\": \"梨花掩映下的白红特色藏式碉房\"}, {\"id\": \"wp_cx39_2\", \"name\": \"边耳乡党岭村藏家乐\", \"lat\": 31.025, \"lon\": 101.612, \"ele\": 3180, \"desc\": \"村中木屋住宿，泡纯天然野温泉\"}, {\"id\": \"wp_cx39_3\", \"name\": \"飞机坪草甸休息点\", \"lat\": 31.052, \"lon\": 101.582, \"ele\": 3650, \"desc\": \"开阔平坦的高山草场，马帮中继站\"}, {\"id\": \"wp_cx39_4\", \"name\": \"党岭葫芦海湖畔(4160m)\", \"lat\": 31.085, \"lon\": 101.552, \"ele\": 4160, \"desc\": \"倒映夏羌拉雪峰的高原明珠，清澈见底\"}, {\"id\": \"wp_cx39_5\", \"name\": \"大海子幽蓝秘境\", \"lat\": 31.095, \"lon\": 101.535, \"ele\": 4250, \"desc\": \"更深处的高山海子，原路返回党岭\"}]",
		},
		{
			ID:        "pub_cx_40",
			Title:     "怒江大峡谷·滇西北秘境自驾",
			Region:    "chuanxi",
			Terrain:   "canyon_gorge",
			Category:  "overland",
			Diff:      3,
			Vehicle:   "at_tire",
			DistKm:    320.0,
			EleGain:   2450,
			EleMax:    3100,
			Duration:  "3天2夜",
			Season:    "11月-次年4月(怒江水碧蓝如翡翠)",
			Downloads: 1350,
			Desc:      "自云南保山/六库起，沿怒江美丽公路一路向北。穿过老虎跳急流峡谷、福贡石月亮奇观、贡山县城，深入独龙江乡寻找纹面女文化，抵达“人神共居”的丙中洛。冬季与早春怒江褪去浊浪，水色碧绿如翠玉。",
			WptsJSON:  "[{\"id\": \"wp_cx40_1\", \"name\": \"六库怒江美丽公路起点\", \"lat\": 25.852, \"lon\": 98.852, \"ele\": 810, \"desc\": \"怒江傈僳族自治州府，开启大峡谷自驾\"}, {\"id\": \"wp_cx40_2\", \"name\": \"匹河飞来石与老姆登基督教堂\", \"lat\": 26.582, \"lon\": 98.892, \"ele\": 1280, \"desc\": \"怒族特色达玛花，听老姆登天籁赞美诗\"}, {\"id\": \"wp_cx40_3\", \"name\": \"福贡石月亮高空山体透穿\", \"lat\": 27.025, \"lon\": 98.865, \"ele\": 1150, \"desc\": \"高黎贡山峰顶大理岩溶洞天然穿孔奇观\"}, {\"id\": \"wp_cx40_4\", \"name\": \"独龙江高黎贡山隧道\", \"lat\": 27.752, \"lon\": 98.452, \"ele\": 3020, \"desc\": \"穿透雪山告别半年大雪封山历史，探寻独龙族\"}, {\"id\": \"wp_cx40_5\", \"name\": \"丙中洛怒江第一湾\", \"lat\": 28.012, \"lon\": 98.595, \"ele\": 1750, \"desc\": \"怒江在此被气势磅礴的山石拦截形成大回环\"}]",
		},
		{
			ID:        "pub_cx_41",
			Title:     "若尔盖大草原·黄河九曲第一湾",
			Region:    "chuanxi",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    420.0,
			EleGain:   650,
			EleMax:    3500,
			Duration:  "2天1夜",
			Season:    "6月-8月",
			Downloads: 1680,
			Desc:      "川西北高原“绿宝石”。途经红原月亮湾、唐克黄河九曲第一湾看长河落日大圆月，游历若尔盖花湖国家级黑颈鹤湿地保护区与郎木寺镇（甘川分界）。盛夏漫山遍野繁花似锦，牛羊宛如珍珠散落。",
			WptsJSON:  "[{\"id\": \"wp_cx41_1\", \"name\": \"红原县月亮湾景区\", \"lat\": 32.785, \"lon\": 102.552, \"ele\": 3480, \"desc\": \"白河水在茫茫草原上曲折如新月\"}, {\"id\": \"wp_cx41_2\", \"name\": \"唐克黄河九曲第一湾观景台\", \"lat\": 33.325, \"lon\": 102.485, \"ele\": 3550, \"desc\": \"黄河与白河交汇，电梯登顶看雄浑大河落日\"}, {\"id\": \"wp_cx41_3\", \"name\": \"若尔盖热尔大草原腹地\", \"lat\": 33.682, \"lon\": 102.852, \"ele\": 3450, \"desc\": \"中国仅次于呼伦贝尔的第二大草原\"}, {\"id\": \"wp_cx41_4\", \"name\": \"若尔盖花湖木栈道\", \"lat\": 33.912, \"lon\": 102.825, \"ele\": 3468, \"desc\": \"高原泥炭沼泽湿地，黑颈鹤与天鹅飞舞\"}, {\"id\": \"wp_cx41_5\", \"name\": \"郎木寺东方小瑞士镇\", \"lat\": 34.085, \"lon\": 102.625, \"ele\": 3350, \"desc\": \"一河跨甘川两省两座藏传古寺\"}]",
		},
		{
			ID:        "pub_cx_42",
			Title:     "川西大环线全景深度自驾",
			Region:    "chuanxi",
			Terrain:   "snow_alpine",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    1680.0,
			EleGain:   9500,
			EleMax:    4718,
			Duration:  "7~9天",
			Season:    "5-6月, 9-10月",
			Downloads: 3120,
			Desc:      "川西全景一网打尽的殿堂级自驾路线。成都出发，经雅安、康定折多山、新都桥光影天堂、理塘天空之城、稻城亚丁、新龙红山、甘孜格萨尔王城、色达五明佛学院红房子、炉霍、马尔康卓克基土司官寨返回成都。全线高等级公路，震撼无匹。",
			WptsJSON:  "[{\"id\": \"wp_cx42_1\", \"name\": \"成都绕城高速西出口\", \"lat\": 30.658, \"lon\": 104.065, \"ele\": 500, \"desc\": \"雅康高速启程，穿越二郎山特长隧道\"}, {\"id\": \"wp_cx42_2\", \"name\": \"康定情歌广场与折多山(4298m)\", \"lat\": 30.052, \"lon\": 101.812, \"ele\": 4298, \"desc\": \"康巴第一关，正式步入藏区高海拔\"}, {\"id\": \"wp_cx42_3\", \"name\": \"新都桥摄影家走廊\", \"lat\": 30.025, \"lon\": 101.521, \"ele\": 3460, \"desc\": \"白杨树、藏寨、小溪与金黄夕阳\"}, {\"id\": \"wp_cx42_4\", \"name\": \"理塘西城门(海拔4014m)\", \"lat\": 29.985, \"lon\": 100.285, \"ele\": 4014, \"desc\": \"世界高城理塘，打卡勒通古镇与长青春科尔寺\"}, {\"id\": \"wp_cx42_5\", \"name\": \"稻城金珠镇万亩青杨林\", \"lat\": 29.052, \"lon\": 100.295, \"ele\": 3750, \"desc\": \"尊胜塔林白塔，红草地与金秋杨林\"}, {\"id\": \"wp_cx42_6\", \"name\": \"甘孜县城与雅砻江大雪山\", \"lat\": 31.625, \"lon\": 99.985, \"ele\": 3390, \"desc\": \"仰望雀儿山冰峰，格萨尔王文化圣地\"}, {\"id\": \"wp_cx42_7\", \"name\": \"色达喇荣五明佛学院\", \"lat\": 32.145, \"lon\": 100.752, \"ele\": 4000, \"desc\": \"山谷遍布红色僧房，震撼万分的信仰之城\"}, {\"id\": \"wp_cx42_8\", \"name\": \"马尔康卓克基土司官寨\", \"lat\": 31.912, \"lon\": 102.254, \"ele\": 2680, \"desc\": \"茅盾文学奖《尘埃落定》故事发生地，返程成都\"}]",
		},
		{
			ID:        "pub_qh_43",
			Title:     "柴达木盆地·火星一号公路越野探险",
			Region:    "qinghai",
			Terrain:   "gobi_gravel",
			Category:  "offroad",
			Diff:      4,
			Vehicle:   "4x4_high_clearance",
			DistKm:    365.0,
			EleGain:   620,
			EleMax:    2980,
			Duration:  "2天1夜",
			Season:    "5-10月",
			Downloads: 1890,
			Desc:      "地球上最像火星地貌的无人越野地带。由大柴旦翡翠湖出发，穿经世界上唯一的水上雅丹（乌素特），驶入G315火星一号公路（砂石非铺装），深入俄博梁雅丹硅化立柱群核心，入住火星营地睡眠舱，最终抵临冷湖石油废墟小镇。沿途严禁单车盲目驶离主航迹，沙地极易下沉深陷。",
			WptsJSON:  "[{\"id\": \"wp_qh43_1\", \"name\": \"大柴旦翡翠湖景区大门\", \"lat\": 37.852, \"lon\": 95.325, \"ele\": 3140, \"desc\": \"盐湖结晶色彩斑斓，出发前加满燃油\"}, {\"id\": \"wp_qh43_2\", \"name\": \"G315网红U型公路段\", \"lat\": 37.652, \"lon\": 94.452, \"ele\": 2850, \"desc\": \"波浪起伏公路线，切勿路中停车拍照\"}, {\"id\": \"wp_qh43_3\", \"name\": \"乌素特水上雅丹公园\", \"lat\": 37.582, \"lon\": 93.852, \"ele\": 2720, \"desc\": \"世界绝无仅有的水上雅丹地质地貌\"}, {\"id\": \"wp_qh43_4\", \"name\": \"火星一号公路南端入口\", \"lat\": 37.712, \"lon\": 93.421, \"ele\": 2780, \"desc\": \"转入非铺装荒漠砂石路，开启低速减震模式\"}, {\"id\": \"wp_qh43_5\", \"name\": \"冷湖火星营地空间站\", \"lat\": 38.012, \"lon\": 93.254, \"ele\": 2890, \"desc\": \"太空胶囊舱宿营体验，租借宇航服拍摄大片\"}, {\"id\": \"wp_qh43_6\", \"name\": \"俄博梁雅丹魔鬼城核心\", \"lat\": 38.125, \"lon\": 93.185, \"ele\": 2980, \"desc\": \"规模宏大的柱状雅丹群，强磁场指南针失效\"}, {\"id\": \"wp_qh43_7\", \"name\": \"冷湖石油工业废墟遗址\", \"lat\": 38.745, \"lon\": 93.325, \"ele\": 2750, \"desc\": \"昔日数万人油田基地遗迹，出荒漠完成穿越\"}]",
		},
		{
			ID:        "pub_qh_44",
			Title:     "青海湖·祁连山大环线经典自驾",
			Region:    "qinghai",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    1180.0,
			EleGain:   3200,
			EleMax:    3820,
			Duration:  "5~6天",
			Season:    "6-8月",
			Downloads: 4200,
			Desc:      "西北最经典的国民大环线。西宁出发，经日月山抵青海湖二郎剑，漫步茶卡天空之镜盐湖，穿越柴达木盆地大柴旦翡翠湖，翻越祁连山脉卓尔山看东方小瑞士，途经门源百里油菜花海返回西宁。全线均为高等级柏油公路，配套设施完备成熟，老少皆宜。",
			WptsJSON:  "[{\"id\": \"wp_qh44_1\", \"name\": \"西宁火车站/机场集结点\", \"lat\": 36.621, \"lon\": 101.785, \"ele\": 2260, \"desc\": \"青甘大环线始发站，采购抗高反葡萄糖\"}, {\"id\": \"wp_qh44_2\", \"name\": \"日月山文成公主进藏道\", \"lat\": 36.425, \"lon\": 100.985, \"ele\": 3520, \"desc\": \"黄土高原与青藏高原天然地理分界线\"}, {\"id\": \"wp_qh44_3\", \"name\": \"青海湖二郎剑景区\", \"lat\": 36.582, \"lon\": 100.452, \"ele\": 3200, \"desc\": \"中国最大内陆咸水湖，蔚蓝湖水海天一色\"}, {\"id\": \"wp_qh44_4\", \"name\": \"茶卡天空之镜盐湖\", \"lat\": 36.712, \"lon\": 99.085, \"ele\": 3059, \"desc\": \"小火车驶入盐湖腹地，白色倒影摄影圣地\"}, {\"id\": \"wp_qh44_5\", \"name\": \"大柴旦翡翠湖\", \"lat\": 37.852, \"lon\": 95.325, \"ele\": 3140, \"desc\": \"矿物结晶形成的翠绿浅滩湖泊\"}, {\"id\": \"wp_qh44_6\", \"name\": \"祁连县卓尔山风景区\", \"lat\": 38.185, \"lon\": 100.254, \"ele\": 2980, \"desc\": \"东方小瑞士，红色丹霞与油菜花群山辉映\"}, {\"id\": \"wp_qh44_7\", \"name\": \"门源百里油菜花海\", \"lat\": 37.385, \"lon\": 101.621, \"ele\": 2850, \"desc\": \"7月万亩金色油菜花海壮丽盛景\"}, {\"id\": \"wp_qh44_8\", \"name\": \"西宁市区闭环终点\", \"lat\": 36.621, \"lon\": 101.785, \"ele\": 2260, \"desc\": \"回到西宁，品尝炕锅羊肉与酸奶\"}]",
		},
		{
			ID:        "pub_qh_45",
			Title:     "茫崖翡翠湖·恶魔之眼艾肯泉自驾",
			Region:    "qinghai",
			Terrain:   "gobi_gravel",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    480.0,
			EleGain:   580,
			EleMax:    2920,
			Duration:  "2天1夜",
			Season:    "5-10月",
			Downloads: 1360,
			Desc:      "柴达木盆地最西端的极致色彩盛宴。经西台吉乃尔双色湖（一侧蓝一侧绿的奇景）、水上雅丹、黄瓜梁雅丹群，抵达茫崖市翡翠湖（深邃翠绿如琥珀），最后探寻奔涌数千年如恶魔之瞳的含硫热泉“艾肯泉”。",
			WptsJSON:  "[{\"id\": \"wp_qh45_1\", \"name\": \"大柴旦镇西向出发点\", \"lat\": 37.852, \"lon\": 95.325, \"ele\": 3140, \"desc\": \"沿G315国道一路西行向西柴达木深入\"}, {\"id\": \"wp_qh45_2\", \"name\": \"西台吉乃尔双色湖\", \"lat\": 37.625, \"lon\": 93.352, \"ele\": 2680, \"desc\": \"公路两旁湖水因矿物质浓度不同呈现双色\"}, {\"id\": \"wp_qh45_3\", \"name\": \"茫崖翡翠湖(黑独山旁)\", \"lat\": 38.252, \"lon\": 90.185, \"ele\": 2900, \"desc\": \"宛如镶嵌在黑色矿山中的碧玉翠池\"}, {\"id\": \"wp_qh45_4\", \"name\": \"艾肯泉(恶魔之眼喷泉)\", \"lat\": 38.152, \"lon\": 89.985, \"ele\": 2920, \"desc\": \"高空俯瞰如一只巨大彩色眼睛脉动喷涌硫磺\"}, {\"id\": \"wp_qh45_5\", \"name\": \"茫崖花土沟镇集结返程\", \"lat\": 38.385, \"lon\": 90.452, \"ele\": 2880, \"desc\": \"青新交界重镇，连通若羌出疆\"}]",
		},
		{
			ID:        "pub_qh_46",
			Title:     "年宝玉则神山湖泊大环线徒步",
			Region:    "qinghai",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    52.0,
			EleGain:   1950,
			EleMax:    4600,
			Duration:  "3天2夜",
			Season:    "6月-8月",
			Downloads: 980,
			Desc:      "果洛藏族自治州久治县神山秘境。仰望果洛山主峰年宝玉则（5369m），徒步探访仙女湖、妖女湖、黑石海，翻越海拔4600米的下藏科达坂，途径日尕玛措。冰蚀悬崖陡峭如刀劈斧削，夏日野花地毯般铺展。",
			WptsJSON:  "[{\"id\": \"wp_qh46_1\", \"name\": \"年宝玉则国家地质公园入口\", \"lat\": 33.352, \"lon\": 101.185, \"ele\": 3980, \"desc\": \"仙女湖畔整备行囊，向妖女湖进发\"}, {\"id\": \"wp_qh46_2\", \"name\": \"妖女湖深处灌木滩营地\", \"lat\": 33.285, \"lon\": 101.125, \"ele\": 4050, \"desc\": \"湖畔乱石与灌木丛，常有棕熊出没痕迹注意防范\"}, {\"id\": \"wp_qh46_3\", \"name\": \"下藏科达坂(4600m)\", \"lat\": 33.215, \"lon\": 101.052, \"ele\": 4600, \"desc\": \"巨型花岗岩流石堆，手足并用攀爬翻越\"}, {\"id\": \"wp_qh46_4\", \"name\": \"日尕玛措清澈圣湖\", \"lat\": 33.152, \"lon\": 100.985, \"ele\": 4350, \"desc\": \"远离喧嚣未开发处女湖\"}, {\"id\": \"wp_qh46_5\", \"name\": \"西姆措与出山口下藏科乡\", \"lat\": 33.085, \"lon\": 100.892, \"ele\": 3920, \"desc\": \"乘接驳车出山完成年宝玉则转山\"}]",
		},
		{
			ID:        "pub_qh_47",
			Title:     "阿尼玛卿雪山外环线转山徒步",
			Region:    "qinghai",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    68.0,
			EleGain:   2200,
			EleMax:    4680,
			Duration:  "4天3夜",
			Season:    "6月-9月",
			Downloads: 650,
			Desc:      "藏区四大神山之一（海拔6282米）。位于果洛玛沁县。藏传佛教信徒绕山一圈可洗清前世今生罪孽。沿途经过哈龙冰川、黄河源头支流、达玛垭口，全方位仰视雪山晶莹冰川。需携带专业保暖抗风装备与防高反物资。",
			WptsJSON:  "[{\"id\": \"wp_qh47_1\", \"name\": \"大武镇雪山乡大日加起点\", \"lat\": 34.452, \"lon\": 99.452, \"ele\": 3950, \"desc\": \"转山藏民起点，顺时针方向启程\"}, {\"id\": \"wp_qh47_2\", \"name\": \"哈龙冰川舌前缘(4350m)\", \"lat\": 34.612, \"lon\": 99.385, \"ele\": 4350, \"desc\": \"长达数公里的巨大高山悬冰川瀑布\"}, {\"id\": \"wp_qh47_3\", \"name\": \"下大坂与达玛垭口(4680m)\", \"lat\": 34.785, \"lon\": 99.254, \"ele\": 4680, \"desc\": \"狂风肆虐风口，经幡呼啸，撒龙达祈福\"}, {\"id\": \"wp_qh47_4\", \"name\": \"格鲁派下大武寺与转山终点\", \"lat\": 34.521, \"lon\": 99.125, \"ele\": 4010, \"desc\": \"完成全线转山回到起点\"}]",
		},
		{
			ID:        "pub_qh_48",
			Title:     "甘加秘境·白石崖八角古城穿越",
			Region:    "qinghai",
			Terrain:   "plateau_grassland",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    95.0,
			EleGain:   850,
			EleMax:    3200,
			Duration:  "1~2天",
			Season:    "5月-10月",
			Downloads: 1120,
			Desc:      "甘南夏河拉卜楞寺北侧的遗世明珠。造访西汉古八角城（十字空心城墙遗址）、白石崖溶洞（丹尼索瓦古人类遗址）、高耸如屏风的巨型白石崖绝壁与甘加草原。土路与砂石车辙相连，景色苍凉宏大。",
			WptsJSON:  "[{\"id\": \"wp_qh48_1\", \"name\": \"夏河拉卜楞寺集合点\", \"lat\": 35.202, \"lon\": 102.505, \"ele\": 2980, \"desc\": \"世界藏学府，世界最长转经长廊打卡\"}, {\"id\": \"wp_qh48_2\", \"name\": \"八角古城观景台\", \"lat\": 35.352, \"lon\": 102.612, \"ele\": 3050, \"desc\": \"两千年前汉代十字城墙古城堡俯瞰\"}, {\"id\": \"wp_qh48_3\", \"name\": \"白石崖溶洞与寺院\", \"lat\": 35.421, \"lon\": 102.685, \"ele\": 3280, \"desc\": \"千仞白色石灰岩垂直绝壁，溶洞神秘探幽\"}, {\"id\": \"wp_qh48_4\", \"name\": \"甘加草原草甸深处\", \"lat\": 35.485, \"lon\": 102.752, \"ele\": 3150, \"desc\": \"牛羊漫山，土路尽头返回夏河县城\"}]",
		},
		{
			ID:        "pub_qh_49",
			Title:     "河西走廊历史文化自驾大道",
			Region:    "qinghai",
			Terrain:   "gobi_gravel",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    1150.0,
			EleGain:   1850,
			EleMax:    2980,
			Duration:  "5~6天",
			Season:    "5-10月",
			Downloads: 3250,
			Desc:      "华夏文明金戈铁马的壮烈史诗。从兰州出发，穿越乌鞘岭，经武威雷台汉墓马踏飞燕、张掖七彩丹霞与大佛寺、酒泉卫星发射中心分道、天下第一雄关嘉峪关、瓜州大地之子，直抵丝路明珠敦煌莫高窟与鸣沙山月牙泉。",
			WptsJSON:  "[{\"id\": \"wp_qh49_1\", \"name\": \"兰州中山桥黄河第一桥\", \"lat\": 36.065, \"lon\": 103.812, \"ele\": 1520, \"desc\": \"品尝兰州牛肉面，启程跨越乌鞘岭\"}, {\"id\": \"wp_qh49_2\", \"name\": \"武威雷台汉墓与凉州故城\", \"lat\": 37.935, \"lon\": 102.652, \"ele\": 1530, \"desc\": \"马踏飞燕国宝出土之地，汉唐凉州词\"}, {\"id\": \"wp_qh49_3\", \"name\": \"张掖七彩丹霞地质公园\", \"lat\": 38.982, \"lon\": 100.125, \"ele\": 1780, \"desc\": \"夕阳下色彩斑斓犹如上帝打翻调色盘\"}, {\"id\": \"wp_qh49_4\", \"name\": \"嘉峪关明代万里长城第一关\", \"lat\": 39.812, \"lon\": 98.215, \"ele\": 1680, \"desc\": \"河西咽喉锁钥，天下第一雄关\"}, {\"id\": \"wp_qh49_5\", \"name\": \"瓜州戈壁清泉与无界大地之子\", \"lat\": 40.521, \"lon\": 95.812, \"ele\": 1180, \"desc\": \"荒漠中安详熟睡的巨大巨婴雕塑\"}, {\"id\": \"wp_qh49_6\", \"name\": \"敦煌莫高窟与鸣沙山月牙泉\", \"lat\": 40.142, \"lon\": 94.662, \"ele\": 1140, \"desc\": \"千年莫高飞天壁画，大漠清泉相拥奇观\"}]",
		},
		{
			ID:        "pub_qh_50",
			Title:     "扎尕那-大峪沟甘南秘境徒步",
			Region:    "qinghai",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    58.0,
			EleGain:   2300,
			EleMax:    3950,
			Duration:  "3天2夜",
			Season:    "6月-9月",
			Downloads: 850,
			Desc:      "深藏在甘南迭山山脉腹地的原生态穿越线。从扎尕那石城出发，沿桑成沟峡谷攀升翻越喀拉克垭口，穿经大峪沟九甸峡、旗杆石。峡谷流水潺潺，冷杉白桦层层叠叠，堪称东方阿尔卑斯。",
			WptsJSON:  "[{\"id\": \"wp_qh50_1\", \"name\": \"扎尕那代巴村徒步起点\", \"lat\": 34.252, \"lon\": 103.225, \"ele\": 3020, \"desc\": \"避开旅游主干道切入原生态峡谷\"}, {\"id\": \"wp_qh50_2\", \"name\": \"冬才石林露营地\", \"lat\": 34.312, \"lon\": 103.185, \"ele\": 3450, \"desc\": \"怪石柱林耸立，扎营第一晚\"}, {\"id\": \"wp_qh50_3\", \"name\": \"喀拉克达坂垭口(3950m)\", \"lat\": 34.352, \"lon\": 103.125, \"ele\": 3950, \"desc\": \"碎石大坡翻越点，俯瞰南北峡谷分界\"}, {\"id\": \"wp_qh50_4\", \"name\": \"大峪沟阿角沟口\", \"lat\": 34.412, \"lon\": 103.085, \"ele\": 2850, \"desc\": \"青山绿水间出峡谷，卓尼县接驳返程\"}]",
		},
		{
			ID:        "pub_hb_51",
			Title:     "太行天路·郭亮与昆山挂壁自驾",
			Region:    "huabei",
			Terrain:   "canyon_gorge",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    88.0,
			EleGain:   950,
			EleMax:    1660,
			Duration:  "1~2天",
			Season:    "4-11月",
			Downloads: 1750,
			Desc:      "人工在千仞绝壁上开凿的公路奇迹。从河南新乡万仙山进入，穿过被誉为“世界第九大奇迹”的郭亮绝壁长廊，沿山脊天路通往山西陵川昆山挂壁公路（极窄险峻崖壁公路），再登临王莽岭俯瞰八百里太行群峰云海。挂壁路段狭窄需开启近光灯会车避让。",
			WptsJSON:  "[{\"id\": \"wp_hb51_1\", \"name\": \"万仙山景区南门入口\", \"lat\": 35.712, \"lon\": 113.612, \"ele\": 850, \"desc\": \"核验车牌与门票，入山盘山公路\"}, {\"id\": \"wp_hb51_2\", \"name\": \"郭亮挂壁绝壁长廊\", \"lat\": 35.735, \"lon\": 113.585, \"ele\": 1120, \"desc\": \"全长1250米的人工开凿红岩绝壁挂壁天路\"}, {\"id\": \"wp_hb51_3\", \"name\": \"郭亮石头村天池\", \"lat\": 35.748, \"lon\": 113.572, \"ele\": 1250, \"desc\": \"石磨、石桌、石屋，古朴民俗村落\"}, {\"id\": \"wp_hb51_4\", \"name\": \"昆山挂壁公路(晋豫交界)\", \"lat\": 35.682, \"lon\": 113.521, \"ele\": 1420, \"desc\": \"比郭亮更原始更险窄的绝壁天路，小心擦碰后视镜\"}, {\"id\": \"wp_hb51_5\", \"name\": \"王莽岭主峰龟驼峰\", \"lat\": 35.652, \"lon\": 113.545, \"ele\": 1665, \"desc\": \"太行山最高观景台，观壮丽太行日出与云海\"}]",
		},
		{
			ID:        "pub_hb_52",
			Title:     "太行大峡谷·林州红旗渠天路",
			Region:    "huabei",
			Terrain:   "canyon_gorge",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    95.0,
			EleGain:   1100,
			EleMax:    1580,
			Duration:  "2天1夜",
			Season:    "4-11月",
			Downloads: 1180,
			Desc:      "人工天河与南太行雄险风光结合。由林州红旗渠青年洞引水渠出发，盘山登上太行天路观景台，俯瞰桃花谷飞瀑深潭与王相岩摩天筒梯。红岩嶂谷地貌壁立千仞，壮怀激烈。",
			WptsJSON:  "[{\"id\": \"wp_hb52_1\", \"name\": \"红旗渠青年洞分水闸\", \"lat\": 36.325, \"lon\": 113.785, \"ele\": 520, \"desc\": \"峭壁上人工开凿的红旗渠咽喉工程\"}, {\"id\": \"wp_hb52_2\", \"name\": \"桃花谷飞龙峡九连瀑\", \"lat\": 36.125, \"lon\": 113.712, \"ele\": 780, \"desc\": \"峡谷溪流潺潺，深潭碧绿如玉\"}, {\"id\": \"wp_hb52_3\", \"name\": \"太行天路平步青云观景台\", \"lat\": 36.085, \"lon\": 113.685, \"ele\": 1420, \"desc\": \"俯瞰太行大峡谷U型谷底断崖\"}, {\"id\": \"wp_hb52_4\", \"name\": \"梦幻玻璃栈道与旋梯\", \"lat\": 36.052, \"lon\": 113.672, \"ele\": 1520, \"desc\": \"崖壁悬空栈道，直视谷底深渊\"}, {\"id\": \"wp_hb52_5\", \"name\": \"王相岩摩天筒梯终点\", \"lat\": 35.985, \"lon\": 113.695, \"ele\": 890, \"desc\": \"88米高垂直旋转钢梯挑战胆魄\"}]",
		},
		{
			ID:        "pub_hb_53",
			Title:     "北京门头沟·京西古道探秘徒步",
			Region:    "huabei",
			Terrain:   "canyon_gorge",
			Category:  "hiking",
			Diff:      2,
			Vehicle:   "on_foot",
			DistKm:    21.5,
			EleGain:   680,
			EleMax:    880,
			Duration:  "1天",
			Season:    "3-5月, 9-11月",
			Downloads: 1620,
			Desc:      "北京最具历史沧桑感的文化徒步线路。寻觅马致远笔下“古道西风瘦马”的历史原型。从门头沟圈门出发，沿古香道攀行，途径天梯、峰口庵关隘、令人惊叹的数百年骡马踩踏出的“蹄窝遗迹”，至韭园村马致远故居。适合周末轻量化徒步健身与历史文化溯源。",
			WptsJSON:  "[{\"id\": \"wp_hb53_1\", \"name\": \"门头沟圈门古戏楼\", \"lat\": 39.925, \"lon\": 116.052, \"ele\": 180, \"desc\": \"京西古道起点，登台阶起步爬升\"}, {\"id\": \"wp_hb53_2\", \"name\": \"天梯古香道陡坡\", \"lat\": 39.918, \"lon\": 116.035, \"ele\": 380, \"desc\": \"青石板台阶，坡度较陡，用登山杖借力\"}, {\"id\": \"wp_hb53_3\", \"name\": \"峰口庵关隘城门\", \"lat\": 39.905, \"lon\": 116.012, \"ele\": 650, \"desc\": \"明清运煤古道重要关口\"}, {\"id\": \"wp_hb53_4\", \"name\": \"蹄窝遗迹核心区\", \"lat\": 39.901, \"lon\": 116.008, \"ele\": 620, \"desc\": \"坚硬青石上深达数十厘米的百余个马蹄窝历史印记\"}, {\"id\": \"wp_hb53_5\", \"name\": \"王平韭园村马致远故居\", \"lat\": 39.952, \"lon\": 115.952, \"ele\": 280, \"desc\": \"小桥流水人家，乘公交返城\"}]",
		},
		{
			ID:        "pub_hb_54",
			Title:     "北京“三峰连穿”越野跑标杆线",
			Region:    "huabei",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    24.8,
			EleGain:   1850,
			EleMax:    1291,
			Duration:  "1天",
			Season:    "4-5月, 9-10月",
			Downloads: 2100,
			Desc:      "北京越野跑与高强度登山者的进阶考核线。自大觉寺古刹启程，登顶阳台山（1276m）、妙峰山娘娘庙金顶（1291m）、萝卜地北尖，下撤至涧沟村或大觉寺闭环。爬升剧烈，乱石路滑，是检验体能与心肺耐力的经典试金石。",
			WptsJSON:  "[{\"id\": \"wp_hb54_1\", \"name\": \"大觉寺古刹山门起点\", \"lat\": 40.052, \"lon\": 116.098, \"ele\": 120, \"desc\": \"古银杏树下启程，碎石台阶快速拉升心率\"}, {\"id\": \"wp_hb54_2\", \"name\": \"萝卜地北尖山梁\", \"lat\": 40.065, \"lon\": 116.065, \"ele\": 1105, \"desc\": \"防火道与山脊小径交汇，远眺京城天际线\"}, {\"id\": \"wp_hb54_3\", \"name\": \"阳台山主峰望京楼(1276m)\", \"lat\": 40.075, \"lon\": 116.052, \"ele\": 1276, \"desc\": \"海淀最高峰，玛尼石堆打卡\"}, {\"id\": \"wp_xj54_4\", \"name\": \"妙峰山娘娘庙金顶(1291m)\", \"lat\": 40.082, \"lon\": 116.012, \"ele\": 1291, \"desc\": \"华北道教名山金顶，香火鼎盛\"}, {\"id\": \"wp_hb54_5\", \"name\": \"涧沟村玫瑰谷终点\", \"lat\": 40.095, \"lon\": 116.025, \"ele\": 680, \"desc\": \"出山品尝妙峰山玫瑰饼与炸灌肠\"}]",
		},
		{
			ID:        "pub_hb_55",
			Title:     "蔚县小五台山五台连穿山脊线",
			Region:    "huabei",
			Terrain:   "snow_alpine",
			Category:  "hiking",
			Diff:      5,
			Vehicle:   "on_foot",
			DistKm:    38.0,
			EleGain:   3200,
			EleMax:    2882,
			Duration:  "2天1夜",
			Season:    "6月中旬-7月中旬(金莲花盛开)",
			Downloads: 890,
			Desc:      "“河北屋脊”与华北户外殿堂级挑战。自赤崖堡出发，连续攻克北台、东台（2882米河北最高峰）、中台、西台、南台。万亩金莲花海与高山草甸在云海中翻腾，山脊线刀削斧劈，风大温低，水源极其匮乏，需严控体能负重。",
			WptsJSON:  "[{\"id\": \"wp_hb55_1\", \"name\": \"蔚县赤崖堡村进山点\", \"lat\": 39.952, \"lon\": 115.052, \"ele\": 1050, \"desc\": \"传统北沟进山，备足3L水与防寒抓绒\"}, {\"id\": \"wp_hb55_2\", \"name\": \"北台垭口与北台顶(2837m)\", \"lat\": 39.985, \"lon\": 115.085, \"ele\": 2837, \"desc\": \"陡峭白石山梁爬升，首个大台顶\"}, {\"id\": \"wp_hb55_3\", \"name\": \"东台顶河北第一峰(2882m)\", \"lat\": 39.995, \"lon\": 115.125, \"ele\": 2882, \"desc\": \"河北最高点玛尼堆，视野穿透燕山太行\"}, {\"id\": \"wp_hb55_4\", \"name\": \"中台宿营大草甸(2801m)\", \"lat\": 39.982, \"lon\": 115.105, \"ele\": 2801, \"desc\": \"高山草甸平台，避风扎营赏日落云海\"}, {\"id\": \"wp_hb55_5\", \"name\": \"西台与三岔山脊分水岭\", \"lat\": 39.965, \"lon\": 115.075, \"ele\": 2671, \"desc\": \"向南台连穿或从下金河口下撤分岔点\"}, {\"id\": \"wp_hb55_6\", \"name\": \"南台金莲花坡出山\", \"lat\": 39.912, \"lon\": 115.052, \"ele\": 1280, \"desc\": \"穿越高山灌木林完成五台连穿\"}]",
		},
		{
			ID:        "pub_hb_56",
			Title:     "大兴安岭·漠河极北找北公路",
			Region:    "huabei",
			Terrain:   "forest_mountain",
			Category:  "overland",
			Diff:      2,
			Vehicle:   "suv_standard",
			DistKm:    520.0,
			EleGain:   1100,
			EleMax:    1120,
			Duration:  "3天2夜",
			Season:    "6-8月森林避暑, 12-2月极寒冰雪",
			Downloads: 1520,
			Desc:      "中国地理最北端的林海寻北史诗。从加格达奇出发深入大兴安岭原始森林腹地，穿经呼中、漠河县城，抵达中国最北村庄“北红村”、北极村以及黑龙江第一湾（江湾如蛟龙盘旋）。冬季气温可破零下40度，极光寻踪胜地。",
			WptsJSON:  "[{\"id\": \"wp_hb56_1\", \"name\": \"加格达奇铁道林业枢纽\", \"lat\": 50.425, \"lon\": 124.125, \"ele\": 450, \"desc\": \"大兴安岭行署首府，检查防冻机油与雪地胎\"}, {\"id\": \"wp_hb56_2\", \"name\": \"呼中大兴安岭最高峰大白山\", \"lat\": 51.785, \"lon\": 123.582, \"ele\": 1120, \"desc\": \"万顷落叶松林海波涛，中国最冷小镇\"}, {\"id\": \"wp_hb56_3\", \"name\": \"漠河火灾纪念馆与五·六火灾遗址\", \"lat\": 52.972, \"lon\": 122.525, \"ele\": 410, \"desc\": \"警钟长鸣，松苑原始森林公园保留地\"}, {\"id\": \"wp_hb56_4\", \"name\": \"黑龙江第一湾(龙江巨环)\", \"lat\": 53.552, \"lon\": 123.285, \"ele\": 380, \"desc\": \"滚滚黑龙江中俄界河深切U型大回旋\"}, {\"id\": \"wp_hb56_5\", \"name\": \"中国真正最北村庄北红村\", \"lat\": 53.502, \"lon\": 123.112, \"ele\": 320, \"desc\": \"未过度商业化原始木刻楞小木屋村落\"}, {\"id\": \"wp_hb56_6\", \"name\": \"北极村神州北极广场与最北哨所\", \"lat\": 53.485, \"lon\": 122.352, \"ele\": 310, \"desc\": \"找到最北邮局寄明信片，极北自驾圆满\"}]",
		},
		{
			ID:        "pub_hd_57",
			Title:     "徽杭古道经典历史文化徒步",
			Region:    "huadong",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      2,
			Vehicle:   "on_foot",
			DistKm:    22.0,
			EleGain:   850,
			EleMax:    1050,
			Duration:  "1~2天",
			Season:    "3-5月油菜花, 9-11月秋色",
			Downloads: 2980,
			Desc:      "中国第一条著名徒步古道，“前世不修，生在徽州，十二三岁，往外一丢”的徽商奋斗血泪路。安徽绩溪伏岭村起步，攀登江南第一关险径，沿清凉峰峡谷石板路过下雪堂、蓝天凹（最高点草甸），终达浙江临安浙川村。石板路完备，适合全家与轻户外入门。",
			WptsJSON:  "[{\"id\": \"wp_hd57_1\", \"name\": \"绩溪伏岭镇鱼川村古道入口\", \"lat\": 30.125, \"lon\": 118.852, \"ele\": 210, \"desc\": \"徽派马头墙脚下出发，步入青石古道\"}, {\"id\": \"wp_hd57_2\", \"name\": \"江南第一关(千层石阶栈道)\", \"lat\": 30.138, \"lon\": 118.885, \"ele\": 480, \"desc\": \"悬崖峭壁绝险开凿，俯瞰逍遥河峡谷深潭\"}, {\"id\": \"wp_hd57_3\", \"name\": \"施茶亭与下雪堂农家乐\", \"lat\": 30.145, \"lon\": 118.912, \"ele\": 620, \"desc\": \"古商道免费茶亭遗迹，午间土鸡汤补给\"}, {\"id\": \"wp_hd57_4\", \"name\": \"蓝天凹草甸垭口最高点(1050m)\", \"lat\": 30.158, \"lon\": 118.952, \"ele\": 1050, \"desc\": \"皖浙省界分水岭，两座险峰间的大草甸\"}, {\"id\": \"wp_hd57_5\", \"name\": \"临安浙川村永来古村终点\", \"lat\": 30.172, \"lon\": 119.012, \"ele\": 320, \"desc\": \"抵达浙江境内，乘车前往杭州完成跨省穿越\"}]",
		},
		{
			ID:        "pub_hd_58",
			Title:     "江西武功山十万亩高山草甸穿越",
			Region:    "huadong",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    42.0,
			EleGain:   2400,
			EleMax:    1918,
			Duration:  "2天1夜",
			Season:    "5月-10月(绿草如茵与云海帐篷节)",
			Downloads: 3650,
			Desc:      "“天上草原，人间仙境”。中国南方最震撼的高山云中草甸。自沈子村登山，经九龙山、铁蹄峰直达武功山最高金顶（海拔1918米），再沿山脊跌宕起伏穿过吊马桩、发云界至羊狮幕。云海、日出、金色草甸与漫山遍野的徒步帐篷构成绝美国度。",
			WptsJSON:  "[{\"id\": \"wp_hd58_1\", \"name\": \"沈子村水电站徒步传统起点\", \"lat\": 27.512, \"lon\": 114.185, \"ele\": 380, \"desc\": \"避开索道纯重装起步，溯溪竹林爬升\"}, {\"id\": \"wp_hd58_2\", \"name\": \"铁蹄峰巨石阵险段\", \"lat\": 27.485, \"lon\": 114.152, \"ele\": 1680, \"desc\": \"乱石险坡，手脚并用登上山脊线草甸\"}, {\"id\": \"wp_hd58_3\", \"name\": \"武功山金顶世纪之碑(1918m)\", \"lat\": 27.465, \"lon\": 114.162, \"ele\": 1918, \"desc\": \"江西名山之巅，古祭坛群，壮丽云海翻涌\"}, {\"id\": \"wp_hd58_4\", \"name\": \"吊马桩木栈道与玻璃桥\", \"lat\": 27.452, \"lon\": 114.145, \"ele\": 1580, \"desc\": \"山脊大风口，客栈驿站补给温水与干粮\"}, {\"id\": \"wp_hd58_5\", \"name\": \"千丈岩与绝望坡大落差\", \"lat\": 27.425, \"lon\": 114.125, \"ele\": 1720, \"desc\": \"连续近70度陡峭草坡碎石道，极度考验膝盖\"}, {\"id\": \"wp_hd58_6\", \"name\": \"发云界客栈聚落群\", \"lat\": 27.395, \"lon\": 114.102, \"ele\": 1510, \"desc\": \"高山草甸最厚密处，落日晚霞与繁星宿营\"}, {\"id\": \"wp_hd58_7\", \"name\": \"龙山村或龙王潭出山终点\", \"lat\": 27.352, \"lon\": 114.085, \"ele\": 450, \"desc\": \"下撤至萍乡乘车返程\"}]",
		},
		{
			ID:        "pub_hd_59",
			Title:     "湖北神农架原始森林无人区穿行",
			Region:    "huadong",
			Terrain:   "forest_mountain",
			Category:  "hiking",
			Diff:      4,
			Vehicle:   "on_foot",
			DistKm:    58.0,
			EleGain:   2800,
			EleMax:    3106,
			Duration:  "3天2夜",
			Season:    "5月-10月",
			Downloads: 820,
			Desc:      "“华中屋脊”与野人传说迷境。自木鱼镇进入，穿越神秘原始暗针叶林、冷杉林、泥炭藓沼泽，登顶海拔3106米的神农顶（华中第一峰），探访大九湖高山湿地。森林幽深遮天蔽日，空气负氧离子极高，需严格防范迷路与金丝猴、黑熊等野生动物接触。",
			WptsJSON:  "[{\"id\": \"wp_hd59_1\", \"name\": \"木鱼镇鸭子垭景区起点\", \"lat\": 31.685, \"lon\": 110.452, \"ele\": 1680, \"desc\": \"神农架林区探秘起点，随身携带哨子防野兽\"}, {\"id\": \"wp_hd59_2\", \"name\": \"神农谷喀斯特溶蚀深谷\", \"lat\": 31.725, \"lon\": 110.352, \"ele\": 2820, \"desc\": \"云雾缭绕奇峰林立，万级台阶下沉又爬升\"}, {\"id\": \"wp_hd59_3\", \"name\": \"神农顶华中屋脊(3106m)\", \"lat\": 31.745, \"lon\": 110.305, \"ele\": 3106, \"desc\": \"华中最高峰烽火台，眺望秦巴山脉连绵起伏\"}, {\"id\": \"wp_hd59_4\", \"name\": \"板壁岩石林与野人出没遗址\", \"lat\": 31.735, \"lon\": 110.252, \"ele\": 2580, \"desc\": \"怪石嶙峋，箭竹林海生生不息\"}, {\"id\": \"wp_hd59_5\", \"name\": \"大九湖国家湿地公园黑水河\", \"lat\": 31.552, \"lon\": 110.052, \"ele\": 1730, \"desc\": \"高山平原九个清澈湖泊连缀，晨雾如梦如幻\"}]",
		},
		{
			ID:        "pub_hd_60",
			Title:     "张家界天子山-杨家界野线徒步",
			Region:    "huadong",
			Terrain:   "canyon_gorge",
			Category:  "hiking",
			Diff:      3,
			Vehicle:   "on_foot",
			DistKm:    32.0,
			EleGain:   1650,
			EleMax:    1260,
			Duration:  "2天1夜",
			Season:    "4-11月",
			Downloads: 1850,
			Desc:      "三千奇峰拔地而起的砂岩峰林地貌。避开常规拥挤电梯索道，从金鞭溪峡谷切入乱窜坡爬升至袁家界（阿凡达哈利路亚悬浮山原型），沿未开发野径穿行至杨家界乌龙寨、天波府、一步登天绝壁险峰，直达天子山御笔峰。台阶湿滑险峻，需良好平衡感。",
			WptsJSON:  "[{\"id\": \"wp_hd60_1\", \"name\": \"国家森林公园老门票站\", \"lat\": 29.325, \"lon\": 110.452, \"ele\": 450, \"desc\": \"漫步金鞭溪幽谷，猕猴嬉戏\"}, {\"id\": \"wp_hd60_2\", \"name\": \"乱窜坡陡峭乱石石阶\", \"lat\": 29.352, \"lon\": 110.435, \"ele\": 920, \"desc\": \"2000余级台阶直线拔高，穿透峰林\"}, {\"id\": \"wp_hd60_3\", \"name\": \"袁家界迷魂台与天下第一桥\", \"lat\": 29.358, \"lon\": 110.428, \"ele\": 1050, \"desc\": \"电影《阿凡达》哈利路亚乾坤柱取景地\"}, {\"id\": \"wp_hd60_4\", \"name\": \"杨家界一步登天绝壁铁梯\", \"lat\": 29.382, \"lon\": 110.395, \"ele\": 1180, \"desc\": \"直立悬空铁梯攀爬，峰林顶端孤立平台\"}, {\"id\": \"wp_hd60_5\", \"name\": \"天子山御笔峰与仙女献花\", \"lat\": 29.412, \"lon\": 110.452, \"ele\": 1260, \"desc\": \"神工鬼斧石笔冲天，下山乘车完成穿越\"}]",
		},
		{
			ID:        "pub_hd_61",
			Title:     "恩施大峡谷·清江地缝绝壁栈道",
			Region:    "huadong",
			Terrain:   "canyon_gorge",
			Category:  "hiking",
			Diff:      2,
			Vehicle:   "on_foot",
			DistKm:    26.0,
			EleGain:   1150,
			EleMax:    1520,
			Duration:  "1~2天",
			Season:    "4-10月",
			Downloads: 1720,
			Desc:      "喀斯特地貌发育最完全的地下与天上地质博物馆。深度探访云龙地缝深潭飞瀑暗河，攀上七星寨万米绝壁长廊悬空栈道，近观世界奇观“一炷香”（高150米、细如蜡烛屹立千万年的石柱），下行跨越迎客松与母子情深峰。",
			WptsJSON:  "[{\"id\": \"wp_hd61_1\", \"name\": \"恩施大峡谷游客服务中心\", \"lat\": 30.312, \"lon\": 109.215, \"ele\": 680, \"desc\": \"峡谷启程，下行步入云龙地缝地壳裂隙\"}, {\"id\": \"wp_hd61_2\", \"name\": \"云龙地缝彩虹瀑布底\", \"lat\": 30.305, \"lon\": 109.208, \"ele\": 520, \"desc\": \"两岸绝壁垂直相峙，飞瀑奔腾轰鸣\"}, {\"id\": \"wp_hd61_3\", \"name\": \"七星寨绝壁长廊悬空栈道\", \"lat\": 30.285, \"lon\": 109.195, \"ele\": 1420, \"desc\": \"人工悬空栈道挂在近90度赤壁上，直视千米深谷\"}, {\"id\": \"wp_hd61_4\", \"name\": \"一炷香天地神迹石柱(150m)\", \"lat\": 30.275, \"lon\": 109.182, \"ele\": 1480, \"desc\": \"细长石柱历经数次大地震岿然不倒的世界地质奇迹\"}, {\"id\": \"wp_hd61_5\", \"name\": \"甘堰塘手扶电梯出口\", \"lat\": 30.265, \"lon\": 109.175, \"ele\": 850, \"desc\": \"乘亚洲最长户外手扶电梯出山\"}]",
		},
		{
			ID:        "pub_hd_62",
			Title:     "海南环岛旅游公路海滨自驾线",
			Region:    "huanan",
			Terrain:   "canyon_gorge",
			Category:  "overland",
			Diff:      1,
			Vehicle:   "suv_standard",
			DistKm:    988.0,
			EleGain:   450,
			EleMax:    320,
			Duration:  "5~6天",
			Season:    "全年皆宜(10月-次年4月最佳避寒)",
			Downloads: 3850,
			Desc:      "中国首条高标准热带滨海景观旅游公路。贯通海口、文昌航天木兰湾风车海岸、琼海博鳌亚洲论坛、万宁石梅湾/日月湾冲浪圣地、三亚海棠湾亚龙湾、乐东莺歌海千顷盐田、昌江棋子湾奇石海岸至儋州洋浦。椰影婆娑，海风轻抚，尽览南国热带海滨风光。",
			WptsJSON:  "[{\"id\": \"wp_hd62_1\", \"name\": \"海口新埠岛海边出发点\", \"lat\": 20.085, \"lon\": 110.352, \"ele\": 5, \"desc\": \"开启顺时针988公里环岛海景天路\"}, {\"id\": \"wp_hd62_2\", \"name\": \"文昌木兰湾虎头灯塔风车海岸\", \"lat\": 20.152, \"lon\": 110.852, \"ele\": 25, \"desc\": \"亚洲第一高灯塔，白色大风车立于礁石海岸\"}, {\"id\": \"wp_hd62_3\", \"name\": \"万宁日月湾与石梅湾山海天路\", \"lat\": 18.652, \"lon\": 110.215, \"ele\": 15, \"desc\": \"冲浪胜地，碧海白浪，最美沿海公路段\"}, {\"id\": \"wp_hd62_4\", \"name\": \"三亚海棠湾亚特兰蒂斯\", \"lat\": 18.325, \"lon\": 109.752, \"ele\": 10, \"desc\": \"国际旅游度假区，免税城与顶级度假酒店\"}, {\"id\": \"wp_hd62_5\", \"name\": \"乐东莺歌海千年银白盐田\", \"lat\": 18.512, \"lon\": 108.725, \"ele\": 5, \"desc\": \"海南最大海盐场，如雪地结晶倒映晚霞\"}, {\"id\": \"wp_hd62_6\", \"name\": \"昌江棋子湾多彩卵石海岸\", \"lat\": 19.325, \"lon\": 108.612, \"ele\": 20, \"desc\": \"礁石与金黄细沙相伴，海边日落壮阔\"}, {\"id\": \"wp_hd62_7\", \"name\": \"儋州洋浦千年古盐田返回海口\", \"lat\": 19.752, \"lon\": 109.185, \"ele\": 15, \"desc\": \"火山岩玄武岩开凿古盐槽，闭环回到海口\"}]",
		},
	}

	now := time.Now().Format("2006-01-02 15:04:05")
	for _, s := range seeds {
		var wpts []any
		_ = json.Unmarshal([]byte(s.WptsJSON), &wpts)
		ptsCount := len(wpts)
		if ptsCount == 0 {
			ptsCount = 6
		}

		_, err := publicDb.Exec(`
			INSERT OR IGNORE INTO public_roadbooks (
				id, author_id, author_name, title, region, terrain, category,
				difficulty, vehicle_req, distance_km, points_count, elevation_gain_m,
				elevation_max_m, estimated_duration, best_season, downloads_count,
				status, roadbook_json, created_at, reviewer_name
			) VALUES (?, 'adm_root', '山海行官方智库', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?, ?, 'SystemAutoSeed')`,
			s.ID, s.Title, s.Region, s.Terrain, s.Category,
			s.Diff, s.Vehicle, s.DistKm, ptsCount, s.EleGain,
			s.EleMax, s.Duration, s.Season, s.Downloads,
			s.WptsJSON, now,
		)
		if err != nil {
			log.Printf("[WARN] 写入官方种子路书 %s 失败: %v", s.Title, err)
		}
	}
	log.Printf("[INFO] 成功自动注入 %d 条经典公共路线至 public_roadbooks 库", len(seeds))
}

func main() {
	if err := initDatabase(); err != nil {
		log.Fatalf("初始化安全数据库失败: %v", err)
	}

	mux := http.NewServeMux()

	// 1. 移动端 App 业务接口
	mux.HandleFunc("/api/v1/health", withSecurityMiddleware(handleHealth))
	mux.HandleFunc("/api/v1/app/check_update", withSecurityMiddleware(handleCheckUpdate))
	mux.HandleFunc("/api/v1/app/download/latest", handleDownloadLatestApk)
	mux.HandleFunc("/download/", handleDownloadApkByFilename)
	mux.HandleFunc("/api/v1/auth/register", withSecurityMiddleware(handleRegister))
	mux.HandleFunc("/api/v1/auth/login", withSecurityMiddleware(handleLogin))
	mux.HandleFunc("/api/v1/user/password/change", withSecurityMiddleware(handleUserPasswordChange))
	mux.HandleFunc("/api/v1/user/ticket/submit", withSecurityMiddleware(handleUserTicketSubmit))
	mux.HandleFunc("/api/v1/sync/tracks/upload", withSecurityMiddleware(handleUploadTracks))
	mux.HandleFunc("/api/v1/sync/tracks/list", withSecurityMiddleware(handleListTracks))
	mux.HandleFunc("/api/v1/sync/roadbooks/upload", withSecurityMiddleware(handleUploadRoadbooks))
	mux.HandleFunc("/api/v1/sync/roadbooks/list", withSecurityMiddleware(handleListRoadbooks))
	
	mux.HandleFunc("/api/v1/roadbook/public/list", withSecurityMiddleware(handleListPublicRoadbooks))
	mux.HandleFunc("/api/v1/roadbook/public/detail/", withSecurityMiddleware(handleGetPublicRoadbookDetail))
	
	// 路线三维管理体系与数据字典新端点 (v0.7.7)
	mux.HandleFunc("/api/v1/dict/list", withSecurityMiddleware(handleListDicts))
	mux.HandleFunc("/api/v1/admin/dict/save", withSecurityMiddleware(handleAdminSaveDict))
	mux.HandleFunc("/api/v1/admin/dict/delete", withSecurityMiddleware(handleAdminDeleteDict))
	mux.HandleFunc("/api/v1/admin/roadbooks/team", withSecurityMiddleware(handleAdminTeamRoadbooks))
	mux.HandleFunc("/api/v1/admin/roadbooks/import", withSecurityMiddleware(handleAdminUniversalImport))
	
	mux.HandleFunc("/api/v1/admin/roadbooks/delete", withSecurityMiddleware(handleAdminDeleteRoute))
	mux.HandleFunc("/api/v1/admin/roadbooks/status", withSecurityMiddleware(handleAdminUpdateRouteStatus))
	mux.HandleFunc("/api/v1/admin/roadbooks/export", handleAdminUniversalExport)
	mux.HandleFunc("/api/v1/roadbook/share", withSecurityMiddleware(handleShareRoadbook))
	mux.HandleFunc("/api/v1/roadbook/fetch/", withSecurityMiddleware(handleFetchRoadbookByCode))

	// 2. 管理员 Web 控制台页面与端点 (/admin)
	mux.HandleFunc("/admin", handleAdminWeb)
	mux.HandleFunc("/admin/", handleAdminWeb)
	mux.HandleFunc("/admin/login", handleAdminWeb)
	mux.HandleFunc("/admin/logout", handleAdminWeb)
	mux.HandleFunc("/api/v1/admin/stats", withSecurityMiddleware(handleAdminStats))
	mux.HandleFunc("/api/v1/admin/users", withSecurityMiddleware(handleAdminUsers))
	mux.HandleFunc("/api/v1/admin/user/update", withSecurityMiddleware(handleAdminUserUpdate))
	mux.HandleFunc("/api/v1/admin/user/delete", withSecurityMiddleware(handleAdminUserDelete))
	mux.HandleFunc("/api/v1/admin/tickets", withSecurityMiddleware(handleAdminTickets))
	mux.HandleFunc("/api/v1/admin/ticket/resolve", withSecurityMiddleware(handleAdminTicketResolve))
	mux.HandleFunc("/api/v1/admin/roadbooks", withSecurityMiddleware(handleAdminRoadbooks))
	mux.HandleFunc("/api/v1/admin/release", withSecurityMiddleware(handleAdminPublishRelease))
	mux.HandleFunc("/api/v1/admin/admins", withSecurityMiddleware(handleAdminListAdmins))
	mux.HandleFunc("/api/v1/admin/admins/create", withSecurityMiddleware(handleAdminCreateAdmin))
	mux.HandleFunc("/api/v1/admin/admins/update", withSecurityMiddleware(handleAdminUpdateAdmin))
	mux.HandleFunc("/api/v1/admin/admins/delete", withSecurityMiddleware(handleAdminDeleteAdmin))

	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("==============================================================")
	log.Printf("山海行 (TerraWay) 高安全 VPS 服务端 v0.7.7 已启动，监听端口 %s", listenAddr)
	log.Printf("数据保险箱目录: %s (SQLite WAL 模式)", dataDir)
	log.Printf("管理员 Web 控制台入口: http://你的域名或IP:8080/admin")
	log.Printf("==============================================================")
	log.Fatal(srv.ListenAndServe())
}


// -----------------------------------------------------------------------------
// 公共路线广场 API: 获取公开/审核通过的线路列表 (支持分类、大区、难度、关键字与分页)
// -----------------------------------------------------------------------------
func handleListPublicRoadbooks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	q := r.URL.Query()
	category := strings.TrimSpace(q.Get("category"))
	region := strings.TrimSpace(q.Get("region"))
	difficulty := strings.TrimSpace(q.Get("difficulty"))
	keyword := strings.TrimSpace(q.Get("keyword"))

	page := 1
	if p, err := strconv.Atoi(q.Get("page")); err == nil && p > 0 {
		page = p
	}
	pageSize := 20
	if ps, err := strconv.Atoi(q.Get("page_size")); err == nil && ps > 0 && ps <= 100 {
		pageSize = ps
	}
	offset := (page - 1) * pageSize

	whereClauses := []string{"status = 'approved'"}
	args := []any{}

	if category != "" && category != "all" {
		whereClauses = append(whereClauses, "category = ?")
		args = append(args, category)
	}
	if region != "" && region != "all" {
		whereClauses = append(whereClauses, "region = ?")
		args = append(args, region)
	}
	if difficulty != "" && difficulty != "all" {
		whereClauses = append(whereClauses, "difficulty = ?")
		args = append(args, difficulty)
	}
	if keyword != "" {
		whereClauses = append(whereClauses, "(title LIKE ? OR terrain LIKE ? OR vehicle_req LIKE ?)")
		kw := "%" + keyword + "%"
		args = append(args, kw, kw, kw)
	}

	whereSQL := " WHERE " + strings.Join(whereClauses, " AND ")

	// 查询总数
	var total int
	countSQL := "SELECT COUNT(*) FROM public_roadbooks" + whereSQL
	_ = publicDb.QueryRow(countSQL, args...).Scan(&total)

	// 查询分页数据
	querySQL := `SELECT id, author_id, author_name, title, region, terrain, category, difficulty, 
		vehicle_req, distance_km, points_count, elevation_gain_m, elevation_max_m, estimated_duration, 
		best_season, downloads_count, created_at 
		FROM public_roadbooks` + whereSQL + ` ORDER BY downloads_count DESC, created_at DESC LIMIT ? OFFSET ?`

	listArgs := append(args, pageSize, offset)
	rows, err := publicDb.Query(querySQL, listArgs...)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var items []map[string]any
	for rows.Next() {
		var id, authorID, authorName, title, reg, ter, cat, vehReq, estDur, bestSea, createdAt string
		var diff, ptsCount, downCount int
		var distKm, eleGain, eleMax float64
		if err := rows.Scan(&id, &authorID, &authorName, &title, &reg, &ter, &cat, &diff, &vehReq,
			&distKm, &ptsCount, &eleGain, &eleMax, &estDur, &bestSea, &downCount, &createdAt); err == nil {
			items = append(items, map[string]any{
				"id": id,
				"author_name": authorName,
				"title": title,
				"region": reg,
				"terrain": ter,
				"category": cat,
				"difficulty": diff,
				"vehicle_req": vehReq,
				"distance_km": distKm,
				"points_count": ptsCount,
				"elevation_gain_m": eleGain,
				"elevation_max_m": eleMax,
				"estimated_duration": estDur,
				"best_season": bestSea,
				"downloads_count": downCount,
				"created_at": createdAt,
			})
		}
	}

	if items == nil {
		items = []map[string]any{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"code": 200,
		"msg": "success",
		"data": map[string]any{
			"total": total,
			"page": page,
			"page_size": pageSize,
			"items": items,
		},
	})
}

// -----------------------------------------------------------------------------
// 公共路线广场 API: 获取单条公共路书完整数据 (含完整坐标点)
// -----------------------------------------------------------------------------
func handleGetPublicRoadbookDetail(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := strings.TrimPrefix(r.URL.Path, "/api/v1/roadbook/public/detail/")
	if id == "" {
		http.Error(w, `{"error":"missing roadbook id"}`, http.StatusBadRequest)
		return
	}

	var authorName, title, reg, ter, cat, vehReq, estDur, bestSea, roadbookJSON, createdAt string
	var diff, ptsCount, downCount int
	var distKm, eleGain, eleMax float64

	err := publicDb.QueryRow(`SELECT author_name, title, region, terrain, category, difficulty,
		vehicle_req, distance_km, points_count, elevation_gain_m, elevation_max_m, estimated_duration,
		best_season, downloads_count, roadbook_json, created_at
		FROM public_roadbooks WHERE id = ? AND status = 'approved'`, id).Scan(
		&authorName, &title, &reg, &ter, &cat, &diff, &vehReq, &distKm, &ptsCount, &eleGain,
		&eleMax, &estDur, &bestSea, &downCount, &roadbookJSON, &createdAt)

	if err != nil {
		http.Error(w, `{"code":404,"msg":"roadbook not found"}`, http.StatusNotFound)
		return
	}

	// 增加下载/克隆热度计数
	_, _ = publicDb.Exec("UPDATE public_roadbooks SET downloads_count = downloads_count + 1 WHERE id = ?", id)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"code": 200,
		"msg": "success",
		"data": map[string]any{
			"id": id,
			"author_name": authorName,
			"title": title,
			"region": reg,
			"terrain": ter,
			"category": cat,
			"difficulty": diff,
			"vehicle_req": vehReq,
			"distance_km": distKm,
			"points_count": ptsCount,
			"elevation_gain_m": eleGain,
			"elevation_max_m": eleMax,
			"estimated_duration": estDur,
			"best_season": bestSea,
			"downloads_count": downCount + 1,
			"roadbook_json": roadbookJSON,
			"created_at": createdAt,
		},
	})
}


// -----------------------------------------------------------------------------
// 通用 GPX 1.1 与 JSON 路线解析/序列化引擎 (Universal Roadbook Engine)
// -----------------------------------------------------------------------------
type ParsedWaypoint struct {
	ID   string  `json:"id"`
	Name string  `json:"name"`
	Lat  float64 `json:"lat"`
	Lon  float64 `json:"lon"`
	Desc string  `json:"desc"`
}

// 解析 GPX 1.1 文本提取航迹点与途经点序列
func parseGpxToWaypoints(gpxData string) (title string, desc string, points []ParsedWaypoint, distKm float64, err error) {
	if strings.TrimSpace(gpxData) == "" {
		return "", "", nil, 0, fmt.Errorf("gpx 内容为空")
	}

	// 提取路线名称
	nameRe := regexp.MustCompile(`(?s)<metadata>.*?<name>(.*?)</name>`)
	if m := nameRe.FindStringSubmatch(gpxData); len(m) > 1 {
		title = strings.TrimSpace(m[1])
	}
	if title == "" {
		nameRe2 := regexp.MustCompile(`(?s)<trk>.*?<name>(.*?)</name>`)
		if m := nameRe2.FindStringSubmatch(gpxData); len(m) > 1 {
			title = strings.TrimSpace(m[1])
		}
	}
	if title == "" {
		title = "导入GPX路线_" + time.Now().Format("0102_1504")
	}

	// 正则提取所有 <trkpt lat="..." lon="..."> 或 <wpt lat="..." lon="...">
	ptRe := regexp.MustCompile(`(?s)<(?:trkpt|wpt)\s+lat=["']([^"']+)["']\s+lon=["']([^"']+)["'][^>]*>(.*?)</(?:trkpt|wpt)>`)
	matches := ptRe.FindAllStringSubmatch(gpxData, -1)
	if len(matches) == 0 {
		return "", "", nil, 0, fmt.Errorf("未在 GPX 中发现有效的 trkpt 或 wpt 坐标点")
	}

	// 抽稀保护: 最多保留 200 个关键途经点，符合人类领航反应
	step := 1
	if len(matches) > 150 {
		step = len(matches) / 100
		if step < 1 {
			step = 1
		}
	}

	eleRe := regexp.MustCompile(`<ele>([^<]+)</ele>`)
	wptNameRe := regexp.MustCompile(`<name>(.*?)</name>`)

	var lastLat, lastLon float64
	var totalMeters float64
	ptIndex := 1

	for i := 0; i < len(matches); i += step {
		m := matches[i]
		lat, _ := strconv.ParseFloat(m[1], 64)
		lon, _ := strconv.ParseFloat(m[2], 64)
		body := m[3]

		eleStr := ""
		if em := eleRe.FindStringSubmatch(body); len(em) > 1 {
			eleStr = strings.TrimSpace(em[1])
		}
		pName := ""
		if nm := wptNameRe.FindStringSubmatch(body); len(nm) > 1 {
			pName = strings.TrimSpace(nm[1])
		}

		if pName == "" {
			if ptIndex == 1 {
				pName = "T1·起点"
			} else {
				pName = fmt.Sprintf("P%d", ptIndex)
			}
		}

		if ptIndex > 1 {
			// Haversine 球面距离计算
			dLat := (lat - lastLat) * math.Pi / 180.0
			dLon := (lon - lastLon) * math.Pi / 180.0
			a := math.Sin(dLat/2)*math.Sin(dLat/2) +
				math.Cos(lastLat*math.Pi/180.0)*math.Cos(lat*math.Pi/180.0)*
					math.Sin(dLon/2)*math.Sin(dLon/2)
			c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
			totalMeters += 6371000.0 * c
		}

		pDesc := fmt.Sprintf("里程 %.1fkm", totalMeters/1000.0)
		if eleStr != "" {
			pDesc += fmt.Sprintf(" · 海拔 %sm", eleStr)
		}

		points = append(points, ParsedWaypoint{
			ID:   fmt.Sprintf("wp_%d_%d", time.Now().UnixMilli(), ptIndex),
			Name: pName,
			Lat:  lat,
			Lon:  lon,
			Desc: pDesc,
		})

		lastLat = lat
		lastLon = lon
		ptIndex++
	}

	// 确保最后一个点存在且标记为终点
	if len(matches) > 1 && (len(matches)-1)%step != 0 {
		lastM := matches[len(matches)-1]
		lat, _ := strconv.ParseFloat(lastM[1], 64)
		lon, _ := strconv.ParseFloat(lastM[2], 64)
		points = append(points, ParsedWaypoint{
			ID:   fmt.Sprintf("wp_%d_end", time.Now().UnixMilli()),
			Name: "T终点",
			Lat:  lat,
			Lon:  lon,
			Desc: fmt.Sprintf("全程终点 · 累计 %.1fkm", totalMeters/1000.0),
		})
	}

	distKm = math.Round(totalMeters/100.0) / 10.0
	desc = fmt.Sprintf("由 GPX 文件解析导入的标准路书，全长 %.1fkm，共 %d 个导航航点", distKm, len(points))
	return title, desc, points, distKm, nil
}

// 将路书 JSON 序列化生成标准 GPX 1.1 XML 文件
// 将路书 JSON 序列化生成标准 GPX 1.1 XML 文件
func exportRoadbookToGpx(title, desc string, pointsJSON string) string {
	var points []ParsedWaypoint
	_ = json.Unmarshal([]byte(pointsJSON), &points)

	var sb strings.Builder
	sb.WriteString("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	sb.WriteString("<gpx version=\"1.1\" creator=\"TerraWay (ShanHaiXing) GPS\"\n")
	sb.WriteString("  xmlns=\"http://www.topografix.com/GPX/1/1\"\n")
	sb.WriteString("  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\n")
	sb.WriteString("  <metadata>\n")
	sb.WriteString("    <name>" + html.EscapeString(title) + "</name>\n")
	sb.WriteString("    <desc>" + html.EscapeString(desc) + "</desc>\n")
	sb.WriteString("  </metadata>\n")

	for _, p := range points {
		sb.WriteString(fmt.Sprintf("  <wpt lat=\"%.6f\" lon=\"%.6f\">\n", p.Lat, p.Lon))
		sb.WriteString("    <name>" + html.EscapeString(p.Name) + "</name>\n")
		sb.WriteString("    <desc>" + html.EscapeString(p.Desc) + "</desc>\n")
		sb.WriteString("  </wpt>\n")
	}

	sb.WriteString("  <trk>\n")
	sb.WriteString("    <name>" + html.EscapeString(title) + "</name>\n")
	sb.WriteString("    <trkseg>\n")
	for _, p := range points {
		sb.WriteString(fmt.Sprintf("      <trkpt lat=\"%.6f\" lon=\"%.6f\">\n", p.Lat, p.Lon))
		sb.WriteString("        <name>" + html.EscapeString(p.Name) + "</name>\n")
		sb.WriteString("      </trkpt>\n")
	}
	sb.WriteString("    </trkseg>\n")
	sb.WriteString("  </trk>\n")
	sb.WriteString("</gpx>\n")

	return sb.String()
}


// -----------------------------------------------------------------------------
// 1. 数据字典管理接口 (Master Data Dict Handlers)
// -----------------------------------------------------------------------------
func handleListDicts(w http.ResponseWriter, r *http.Request) {
	dType := strings.TrimSpace(r.URL.Query().Get("type"))
	whereSQL := "WHERE is_active = 1"
	var args []any
	if dType != "" && dType != "all" {
		whereSQL += " AND dict_type = ?"
		args = append(args, dType)
	}

	rows, err := publicDb.Query(`
		SELECT id, dict_type, dict_code, dict_label, dict_desc, sort_order, is_active, meta_json, created_at 
		FROM system_dictionaries `+whereSQL+` ORDER BY dict_type ASC, sort_order ASC`, args...)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": err.Error()})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, dt, dc, dl, desc, meta, cat string
		var sort, act int
		if err := rows.Scan(&id, &dt, &dc, &dl, &desc, &sort, &act, &meta, &cat); err == nil {
			list = append(list, map[string]any{
				"id":         id,
				"dict_type":  dt,
				"dict_code":  dc,
				"dict_label": dl,
				"dict_desc":  desc,
				"sort_order": sort,
				"is_active":  act,
				"meta_json":  meta,
				"created_at": cat,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "data": list})
}

func handleAdminSaveDict(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足"})
		return
	}

	var req struct {
		ID        string `json:"id"`
		DictType  string `json:"dict_type"`
		DictCode  string `json:"dict_code"`
		DictLabel string `json:"dict_label"`
		DictDesc  string `json:"dict_desc"`
		SortOrder int    `json:"sort_order"`
		MetaJSON  string `json:"meta_json"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数解析失败"})
		return
	}

	req.DictType = strings.TrimSpace(req.DictType)
	req.DictCode = strings.TrimSpace(req.DictCode)
	req.DictLabel = strings.TrimSpace(req.DictLabel)
	if req.DictType == "" || req.DictCode == "" || req.DictLabel == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "字典类型、编码与名称均不能为空"})
		return
	}

	if req.ID == "" {
		req.ID = fmt.Sprintf("dict_%s_%s", req.DictType, req.DictCode)
	}

	_, err := publicDb.Exec(`
		INSERT INTO system_dictionaries (id, dict_type, dict_code, dict_label, dict_desc, sort_order, is_active, meta_json)
		VALUES (?, ?, ?, ?, ?, ?, 1, ?)
		ON CONFLICT(dict_type, dict_code) DO UPDATE SET 
			dict_label = excluded.dict_label,
			dict_desc = excluded.dict_desc,
			sort_order = excluded.sort_order,
			meta_json = excluded.meta_json`,
		req.ID, req.DictType, req.DictCode, req.DictLabel, req.DictDesc, req.SortOrder, req.MetaJSON,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "保存字典项失败: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "字典项保存成功", "id": req.ID})
}

func handleAdminDeleteDict(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	_, ok := checkAdminRolePermission(r, 50)
	if !ok {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "只有系统管理员及以上方可删除字典"})
		return
	}

	var req struct {
		ID string `json:"id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "未指定字典项ID"})
		return
	}

	_, _ = publicDb.Exec("DELETE FROM system_dictionaries WHERE id = ?", req.ID)
	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "字典项已移除"})
}

// -----------------------------------------------------------------------------
// 2. 团队路书与临时协助接口 (Team Roadbooks Handlers)
// -----------------------------------------------------------------------------
func handleAdminTeamRoadbooks(w http.ResponseWriter, r *http.Request) {
	_, ok := checkAdminRolePermission(r, 10)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权访问"})
		return
	}

	rows, err := publicDb.Query(`
		SELECT id, team_name, creator_id, creator_name, squad_code, mission_type, points_count, distance_km, status, expire_at, created_at
		FROM team_roadbooks ORDER BY created_at DESC LIMIT 100`)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "查询团队路线失败: " + err.Error()})
		return
	}
	defer rows.Close()

	var list []map[string]any
	for rows.Next() {
		var id, tn, cid, cname, code, mtype, status, expire, cat string
		var pts int
		var dist float64
		if err := rows.Scan(&id, &tn, &cid, &cname, &code, &mtype, &pts, &dist, &status, &expire, &cat); err == nil {
			list = append(list, map[string]any{
				"id":           id,
				"team_name":    tn,
				"creator_name": cname,
				"squad_code":   code,
				"mission_type": mtype,
				"points_count": pts,
				"distance_km":  dist,
				"status":       status,
				"expire_at":    expire,
				"created_at":   cat,
			})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "data": list})
}

// -----------------------------------------------------------------------------
// 3. 通用导入导出接口 (Universal Import / Export Engine)
// -----------------------------------------------------------------------------
func handleAdminUniversalImport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	adminUser, ok := checkAdminRolePermission(r, 10)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"code": 401, "message": "未授权导入"})
		return
	}

	var req struct {
		TargetType string `json:"target_type"` // public / team / personal
		Title      string `json:"title"`
		GpxText    string `json:"gpx_text"`
		Region     string `json:"region"`
		Terrain    string `json:"terrain"`
		Category   string `json:"category"`
		Difficulty int    `json:"difficulty"`
		VehicleReq string `json:"vehicle_req"`
		SquadCode  string `json:"squad_code"`
		TargetUser string `json:"target_user"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "请求体格式错误"})
		return
	}

	if strings.TrimSpace(req.GpxText) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "GPX 文本或航迹数据不能为空"})
		return
	}

	title, desc, points, distKm, err := parseGpxToWaypoints(req.GpxText)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "解析 GPX 失败: " + err.Error()})
		return
	}
	if req.Title != "" {
		title = req.Title
	}

	ptsBytes, _ := json.Marshal(points)
	ptsJSON := string(ptsBytes)

	now := time.Now().Format("2006-01-02 15:04:05")

	switch req.TargetType {
	case "public":
		pubID := fmt.Sprintf("pub_%d", time.Now().UnixMilli())
		reg := req.Region
		if reg == "" {
			reg = "neimenggu"
		}
		ter := req.Terrain
		if ter == "" {
			ter = "gobi_gravel"
		}
		cat := req.Category
		if cat == "" {
			cat = "offroad"
		}
		diff := req.Difficulty
		if diff <= 0 {
			diff = 3
		}
		veh := req.VehicleReq
		if veh == "" {
			veh = "at_tire"
		}

		_, err := publicDb.Exec(`
			INSERT INTO public_roadbooks (id, author_id, author_name, title, region, terrain, category, difficulty, vehicle_req, distance_km, points_count, elevation_gain_m, elevation_max_m, estimated_duration, best_season, downloads_count, status, roadbook_json, created_at, reviewer_name)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 250, 1500, '2天1夜', '5-10月', 0, 'approved', ?, ?, ?)`,
			pubID, adminUser.AdminID, adminUser.DisplayName, title, reg, ter, cat, diff, veh, distKm, len(points), ptsJSON, now, adminUser.DisplayName,
		)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "写入公共路线库失败: " + err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "成功导入并发布至公共精选广场！", "id": pubID, "title": title, "points": len(points), "dist_km": distKm})

	case "team":
		teamID := fmt.Sprintf("team_%d", time.Now().UnixMilli())
		code := strings.ToUpper(strings.TrimSpace(req.SquadCode))
		if code == "" || len(code) < 4 {
			code = fmt.Sprintf("TW%04d", time.Now().Unix()%10000)
		}
		expire := time.Now().AddDate(0, 0, 7).Format("2006-01-02 15:04:05")

		_, err := publicDb.Exec(`
			INSERT INTO team_roadbooks (id, team_name, creator_id, creator_name, squad_code, mission_type, points_count, distance_km, roadbook_json, expire_at, status, created_at)
			VALUES (?, ?, ?, ?, ?, 'fleet_travel', ?, ?, ?, ?, 'active', ?)`,
			teamID, title, adminUser.AdminID, adminUser.DisplayName, code, len(points), distKm, ptsJSON, expire, now,
		)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "创建团队协作路线失败: " + err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "成功导入团队协作路线！已分配 6 位专属口令: " + code, "squad_code": code, "id": teamID})

	case "personal":
		rbID := fmt.Sprintf("rb_%d", time.Now().UnixMilli())
		targetUID := strings.TrimSpace(req.TargetUser)
		if targetUID == "" {
			targetUID = "admin_import"
		}
		_, err := db.Exec(`
			INSERT INTO user_roadbooks (id, user_id, name, points_count, storage_path, uploaded_at)
			VALUES (?, ?, ?, ?, '', ?)`,
			rbID, targetUID, title, len(points), now,
		)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"code": 500, "message": "保存个人私有备份失败: " + err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "已成功为用户录入个人私有路线！", "id": rbID})

	default:
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "未知的目标体系类型: " + req.TargetType})
	}
	_ = desc
}

// 通用导出端点: 支持按路线类型导出为标准 GPX 1.1 或 JSON 文件

// 删除路线端点 (支持 public / team / personal)
func handleAdminDeleteRoute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足"})
		return
	}
	var req struct {
		Type string `json:"type"` // public / team / personal
		ID   string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "参数解析失败"})
		return
	}
	if req.ID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "缺少路线ID"})
		return
	}
	switch req.Type {
	case "public":
		_, _ = publicDb.Exec("DELETE FROM public_roadbooks WHERE id = ?", req.ID)
	case "team":
		_, _ = publicDb.Exec("DELETE FROM team_roadbooks WHERE id = ?", req.ID)
	case "personal":
		_, _ = db.Exec("DELETE FROM user_roadbooks WHERE id = ?", req.ID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "路线已成功删除"})
}

// 更新路线状态端点
func handleAdminUpdateRouteStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	_, ok := checkAdminRolePermission(r, 20)
	if !ok {
		writeJSON(w, http.StatusForbidden, map[string]any{"code": 403, "message": "权限不足"})
		return
	}
	var req struct {
		Type   string `json:"type"` // public / team
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.ID == "" || req.Status == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"code": 400, "message": "缺少必要参数"})
		return
	}
	switch req.Type {
	case "public":
		_, _ = publicDb.Exec("UPDATE public_roadbooks SET status = ? WHERE id = ?", req.Status, req.ID)
	case "team":
		_, _ = publicDb.Exec("UPDATE team_roadbooks SET status = ? WHERE id = ?", req.Status, req.ID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"code": 0, "message": "状态已更新"})
}

func handleAdminUniversalExport(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	rType := q.Get("type") // public / team / personal
	id := q.Get("id")
	format := strings.ToLower(q.Get("format"))
	if format == "" {
		format = "gpx"
	}

	if id == "" {
		http.Error(w, "missing route id", http.StatusBadRequest)
		return
	}

	var title, desc, pointsJSON string
	var err error

	switch rType {
	case "public":
		err = publicDb.QueryRow("SELECT title, '公共精选路线', roadbook_json FROM public_roadbooks WHERE id = ?", id).Scan(&title, &desc, &pointsJSON)
	case "team":
		err = publicDb.QueryRow("SELECT team_name, '车队协作应急路线', roadbook_json FROM team_roadbooks WHERE id = ?", id).Scan(&title, &desc, &pointsJSON)
	case "personal":
		err = db.QueryRow("SELECT name, '个人私有备份路线', COALESCE(storage_path, '') FROM user_roadbooks WHERE id = ?", id).Scan(&title, &desc, &pointsJSON)
		if pointsJSON == "" || !strings.HasPrefix(pointsJSON, "[") {
			// 兜底示例途经点
			pointsJSON = `[{"id":"wp_1","name":"起点","lat":39.8,"lon":102.4,"desc":"私有备份起点"}]`
		}
	default:
		http.Error(w, "invalid route type", http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, "Route not found: "+err.Error(), http.StatusNotFound)
		return
	}

	cleanTitle := strings.ReplaceAll(title, " ", "_")
	if format == "json" {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Content-Disposition", "attachment; filename="+cleanTitle+".json")
		_, _ = w.Write([]byte(pointsJSON))
		return
	}

	// 导出为标准 GPX 1.1
	gpxStr := exportRoadbookToGpx(title, desc, pointsJSON)
	w.Header().Set("Content-Type", "application/gpx+xml; charset=utf-8")
	w.Header().Set("Content-Disposition", "attachment; filename="+cleanTitle+".gpx")
	_, _ = w.Write([]byte(gpxStr))
}
