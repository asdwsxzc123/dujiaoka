#!/bin/bash

#######################################
# 独角数卡 - 远程一键升级/安装脚本
# 通过 curl 远程执行，自动判断安装或升级
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/update.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/asdwsxzc123/dujiaoka/master/update.sh | bash -s -- /自定义目录
#######################################

set -e

# ========== 颜色 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

# ========== 配置 ==========
REPO_URL="https://github.com/asdwsxzc123/dujiaoka.git"
REPO_BRANCH="master"
# 默认安装目录，可通过参数覆盖
PROJECT_DIR="${1:-$HOME/dujiaoka}"

echo "========================================="
echo "  独角���卡 - 远程一键部署/升级"
echo "========================================="
echo ""

# ========== 环境检查 ==========
log_info "检查环境..."

# 检查 Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装，请先安装: https://docs.docker.com/engine/install/"
    exit 1
fi
log_ok "Docker: $(docker --version)"

# 检查 Git
if ! command -v git &> /dev/null; then
    log_error "Git 未安装，请先安装 Git"
    exit 1
fi
log_ok "Git: $(git --version)"
echo ""

# ========== 判断安装 or 升级 ==========
if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    # ===== 升级模式 =====
    log_info "检测到已有项目: ${PROJECT_DIR}"
    log_info "进入升级模式..."
    echo ""

    cd "$PROJECT_DIR"

    # 记录当前版本，用于判断是否需要拉取新镜像
    OLD_COMMIT=$(git rev-parse --short HEAD)

    # 拉取最新代码（包含最新的 upgrade.sh 和升级 SQL）
    log_info "拉取最新代码..."
    git fetch origin "$REPO_BRANCH"
    git reset --hard "origin/$REPO_BRANCH"
    NEW_COMMIT=$(git rev-parse --short HEAD)
    log_ok "代码已更新: ${OLD_COMMIT} → ${NEW_COMMIT}"

    # 仅当代码有变更时才拉取最新 Docker 镜像
    if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
        log_info "拉取最新镜像..."
        ENV_DOCKER_FLAG=""
        if [ -f ".env.docker" ]; then
            ENV_DOCKER_FLAG="--env-file .env.docker"
        fi
        docker compose ${ENV_DOCKER_FLAG} pull web
        log_ok "镜像已更新"
    else
        log_info "代码无变更，跳过镜像拉取"
    fi

    # 执行升级脚本
    echo ""
    log_info "执行升级脚本..."
    echo ""
    bash upgrade.sh

else
    # ===== 安装模式 =====
    log_info "未检测到项目，进入安装模式"
    log_info "安装目录: ${PROJECT_DIR}"
    echo ""

    # 克隆项目
    log_info "克隆项目..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$PROJECT_DIR"
    log_ok "项目已克隆"

    cd "$PROJECT_DIR"

    # 执行安装脚本
    echo ""
    log_info "执行安装脚本..."
    echo ""
    bash install.sh
fi