# 山海行 (TerraWay) 高安全轻量 VPS 服务端部署与发版操作指南 (v0.7.0)

本服务端采用 **Go (Golang 1.22) + SQLite (WAL 模式)** 编写，专为追求**极致稳定、内存安全、零运维负担**的户外工具后台设计。

## 一、 为什么选择 Go + SQLite WAL 架构？

1. **编译期强类型与内存安全**：无缓冲区溢出漏洞，无动态语言运行期崩溃，内置全局 `recover()` 防崩溃守护中间件，确保服务 7×24 小时永不宕机。
2. **单文件零依赖部署**：纯 Go 编译产出单一静态二进制文件，内存占用低于 20MB，1 核 2G 轻量云 VPS 可轻松承载上千人同时同步轨迹。
3. **内置多重安全防线**：
   - **100% 防 SQL 注入**：全量数据库读写采用预编译参数化占位符（`?`）；
   - **Bcrypt 慢哈希密码加密**：用户密码经过加盐慢哈希不可逆加密；
   - **IP 令牌桶防暴力破解限流**：自动拦截高频撞库与恶意请求；
   - **单文件热备份**：整个云端数据均保存在 `./data` 文件夹下，复制该文件夹即可完成 100% 灾备。

## 二、 3 分钟极简一键部署步骤

1. 将本项目中的 `server/` 文件夹上传至你的云服务器（如 `/opt/terraway-server`）。
2. 进入目录并执行一键部署脚本：
   ```bash
   cd /opt/terraway-server
   chmod +x deploy_vps.sh
   ./deploy_vps.sh
   ```
3. 脚本会自动生成专属于你的随机高强度管理员密钥（`TERRAWAY_ADMIN_KEY`）并启动服务。

## 三、 如何推送新版本提醒给所有手机用户？

每次当你通过 GitHub Actions 编译出新版本 APK（例如未来的 `v0.8.0` 离线卫星地图版）后，只需在电脑或服务器终端执行以下一行命令，所有打开「山海行」App 的用户都会在首页自动收到高反差更新弹窗提醒：

```bash
curl -X POST http://你的服务器IP或域名:8080/api/v1/admin/release \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: 你的TERRAWAY_ADMIN_KEY" \
  -d '{
    "version_code": 16,
    "version_name": "0.8.0",
    "apk_url": "https://github.com/qingmi2001/terraway-app/releases/latest/download/terraway_gps_v0.8.0.apk",
    "apk_size_mb": 21.4,
    "changelog_zh": "1. 重磅新增离线卫星遥感底图与等高线图层\n2. 支持沿途 10km 离线瓦片一键预下载",
    "changelog_en": "1. Added offline satellite imagery & contour maps\n2. Added 10km corridor tile pre-fetching",
    "is_forced": false
  }'
```

> **提示**：即便你暂时还没有购买或部署自己的 VPS，客户端也内置了 **GitHub Releases 自动回退探测机制**——只要你的 GitHub 仓库发布了新的 Release Tag（如 `v0.8.0`），手机端同样能自动检测到新版本并弹窗提醒用户一键下载升级！
