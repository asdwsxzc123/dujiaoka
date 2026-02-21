# 独角数卡 部署文档

## 快速开始

一行命令完成安装或升级：

```bash
curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/update.sh | bash
```

脚本自动判断：项目不存在 → 安装，项目已存在 → 升级。

自定义安装目录（默认 `/opt/dujiaoka`）：

```bash
curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/update.sh | bash -s -- /home/www/dujiaoka
```

## 前提条件

- Linux 服务器（Ubuntu/Debian/CentOS）
- Docker >= 20.10
- Docker Compose（Docker 新版自带）
- Git
- （可选）Caddy 用于 HTTPS

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
systemctl start docker && systemctl enable docker
```

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/install.sh | bash
```

自定义安装目录（默认 `/opt/dujiaoka`）：

```bash
curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/install.sh | bash -s -- /home/www/dujiaoka
```

安装过程会交互式询问：
- 域名
- 数据库名 / 用户 / 密码
- 数据存储目录

安装完成后：
- 前台: `https://你的域名`
- 后台: `https://你的域名/admin`
- 默认账号: `admin` / `admin`（请立即修改）

## 升级

```bash
curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/update.sh | bash
```

升级流程：
1. 备份数据库 + .env + 旧镜像
2. 拉取最新代码和 Docker 镜像
3. 同步 .env 新增配置项
4. 重建 Web 容器
5. 执行升级 SQL（自动跳过已执行的）
6. 清理缓存并验证

## 回滚

升级出问题时：

```bash
cd /opt/dujiaoka
bash rollback.sh
```

恢复内容：Docker 镜像、数据库、.env 配置、代码，全部回到升级前状态。

## 日常运维

```bash
cd /opt/dujiaoka

# 启动
docker compose --env-file .env.docker up -d

# 停止
docker compose --env-file .env.docker down

# 重启
docker compose --env-file .env.docker restart

# 查看日志
docker compose --env-file .env.docker logs -f web

# 查看状态
docker compose --env-file .env.docker ps

# 清理缓存
docker exec dujiaoka php artisan cache:clear
docker exec dujiaoka php artisan config:clear
```

## 端口说明

| 服务 | 容器端口 | 主机端口 |
|------|---------|---------|
| Web | 80 | 8080 |
| MySQL | 3306 | 3307 |
| Redis | 6379 | 6380 |

## 升级 SQL 规范

升级 SQL 放在 `database/sql/upgrades/` 目录，按编号命名：

```
001_affiliate_commission.sql
002_add_new_feature.sql
```

- 按文件名排序执行，已执行的记录在 `schema_upgrades` 表，不会重复
- SQL 中建议使用 `IF NOT EXISTS` 等幂等写法

## GitHub Actions

代码推送到 `master` 后自动构建 Docker 镜像推送到 Docker Hub。

需要在 GitHub 仓库 Settings → Secrets 中配置：
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

## 脚本说明

| 脚本 | 用途 |
|------|------|
| `update.sh` | 远程一键安装/升级（curl 执行） |
| `install.sh` | 本地首次安装 |
| `upgrade.sh` | 本地升级 |
| `rollback.sh` | 回滚到上一次升级前 |
