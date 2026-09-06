#!/usr/bin/env bash
# ==============================================================================
# QQ Runtime 服务器智能一键部署脚本
# 支持自动化自检、Docker 状态监控、国内镜像加速源配置与伴生自动更新
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 打印工具函数
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 确保能从终端交互读取（兼容 curl ... | bash）
get_input() {
    local prompt="$1"
    local default_val="$2"
    local answer=""
    if [ -t 0 ]; then
        read -r -p "$prompt" answer
    elif [ -r /dev/tty ]; then
        read -r -p "$prompt" answer </dev/tty
    else
        answer="$default_val"
    fi
    if [ -z "$answer" ]; then
        echo "$default_val"
    else
        echo "$answer"
    fi
}

echo -e "${PURPLE}${BOLD}"
cat << 'EOF'
   ____  ____     ____              _   _                
  / __ \/ __ \   |  _ \ _   _ _ __ | |_(_)_ __ ___   ___ 
 / / _` / / _` |  | |_) | | | | '_ \| __| | '_ ` _ \ / _ \
| | (_| | | (_| | |  _ <| |_| | | | | |_| | | | | | |  __/
 \ \__,_|\ \__,_| |_| \_\\__,_|_| |_|\__|_|_| |_| |_|\___|
  \____/  \____/                                         
EOF
echo -e "${NC}"
echo -e "${BOLD}欢迎使用 QQ Runtime 生产级 Docker 部署脚本${NC}"
echo -e "${BLUE}文档与发布仓库: https://github.com/Chinachani/Runtime-doc${NC}"
echo "=================================================================="

# 1. 系统架构与权限检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH_NAME="x86_64 (amd64)" ;;
    aarch64|arm64) ARCH_NAME="aarch64 (arm64)" ;;
    *) warn "当前系统架构为 $ARCH，官方镜像主要针对 amd64 / arm64 优化，可能会影响部分二进制依赖" ;;
esac
info "检测到系统架构: ${BOLD}${ARCH_NAME:-$ARCH}${NC}"

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
        info "当前为非 root 用户，后续涉及系统操作将自动调用 sudo"
    else
        warn "当前为非 root 用户且未检测到 sudo，若权限不足可能会导致安装失败"
    fi
fi

# 2. Docker 与 Docker Compose 检测
info "正在检测 Docker 运行环境..."
if ! command -v docker >/dev/null 2>&1; then
    warn "未检测到 Docker，正在准备自动安装 Docker..."
    echo -e "是否立即自动安装 Docker 引擎？ [Y/n]"
    INSTALL_DOCKER_CONFIRM=$(get_input "> " "Y")
    case "$INSTALL_DOCKER_CONFIRM" in
        [yY][eE][sS]|[yY]|"")
            info "正在通过国内阿里云加速源安装 Docker 官方包..."
            curl -fsSL https://get.docker.com | $SUDO_CMD bash -s docker --mirror Aliyun || error "Docker 自动安装失败，请手动安装 Docker 后重试"
            ;;
        *)
            error "部署需要 Docker 环境，请先安装 Docker 后再运行本脚本"
            ;;
    esac
fi

# 检查 Docker Daemon 运行状态
if ! docker info >/dev/null 2>&1; then
    warn "Docker 守护进程未启动，正在尝试自动启动 Docker 服务..."
    $SUDO_CMD systemctl start docker >/dev/null 2>&1 || $SUDO_CMD service docker start >/dev/null 2>&1 || true
    sleep 2
    if ! docker info >/dev/null 2>&1; then
        error "无法连接到 Docker 守护进程，请检查并启动 Docker 服务（如执行: sudo systemctl start docker）后重试"
    fi
fi
success "Docker 守护进程状态正常"

# 检查 Compose 支持 (docker compose 或 docker-compose)
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    info "正在为当前环境配置 Docker Compose 插件..."
    $SUDO_CMD apt-get update >/dev/null 2>&1 && $SUDO_CMD apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        error "未找到 Docker Compose，请安装 docker-compose-plugin 或 docker-compose"
    fi
fi
success "Docker Compose 检测通过: $($COMPOSE_CMD version)"

# 3. 安装参数配置
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第一步】配置安装目录与端口${NC}"
DEFAULT_INSTALL_DIR="/opt/qq-runtime"
if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO_CMD" ]; then
    DEFAULT_INSTALL_DIR="$HOME/qq-runtime"
fi

INSTALL_DIR=$(get_input "请输入安装目录路径 [默认: ${DEFAULT_INSTALL_DIR}]: " "$DEFAULT_INSTALL_DIR")
INSTALL_PORT=$(get_input "请输入管理台外部访问端口 [默认: 8080]: " "8080")

# 4. 镜像源交互选择
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第二步】选择 Docker 镜像加速源${NC}"
echo " 1) ghcr.1ms.run          (推荐：国内毫秒级高速分发)"
echo " 2) ghcr.nju.edu.cn       (南京大学开源镜像站)"
echo " 3) ghcr.milu.moe         (麋鹿社区开源加速)"
echo " 4) docker.m.daocloud.io  (DaoCloud 镜像)"
echo " 5) ghcr.io (官方全球源)  (海外服务器首选)"
echo ""
MIRROR_CHOICE=$(get_input "请选择镜像源编号 (1-5) [默认: 1]: " "1")

case "$MIRROR_CHOICE" in
    1)
        IMAGE_NAME="ghcr.1ms.run/chinachani/qq-runtime:latest"
        IMAGE_DESC="ghcr.1ms.run (国内毫秒级高速)"
        ;;
    2)
        IMAGE_NAME="ghcr.nju.edu.cn/chinachani/qq-runtime:latest"
        IMAGE_DESC="ghcr.nju.edu.cn (南京大学镜像)"
        ;;
    3)
        IMAGE_NAME="ghcr.milu.moe/chinachani/qq-runtime:latest"
        IMAGE_DESC="ghcr.milu.moe (麋鹿社区加速)"
        ;;
    4)
        IMAGE_NAME="docker.m.daocloud.io/ghcr.io/chinachani/qq-runtime:latest"
        IMAGE_DESC="docker.m.daocloud.io (DaoCloud 加速)"
        ;;
    5)
        IMAGE_NAME="ghcr.io/chinachani/qq-runtime:latest"
        IMAGE_DESC="ghcr.io (GitHub 官方全球源)"
        ;;
    *)
        IMAGE_NAME="ghcr.1ms.run/chinachani/qq-runtime:latest"
        IMAGE_DESC="ghcr.1ms.run (国内毫秒级高速)"
        ;;
esac
info "已选择镜像: ${BOLD}$IMAGE_NAME${NC} ($IMAGE_DESC)"

# 5. 管理员账号与安全密钥配置
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第三步】管理员初始账户配置${NC}"
ADMIN_USER=$(get_input "请输入初始管理员用户名 [默认: admin]: " "admin")

# 自动生成 16 位高强度安全密码
AUTO_GEN_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 16 2>/dev/null || openssl rand -base64 12 2>/dev/null || echo "QqRuntime@2026")
ADMIN_PASS=$(get_input "请输入管理员初始密码 [默认自动随机高强度密码]: " "$AUTO_GEN_PASS")

# 强随机 Master Key 与 Updater Token
MASTER_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 64)
UPDATER_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)

# 6. 创建目录并写入配置
info "正在初始化安装目录: $INSTALL_DIR"
$SUDO_CMD mkdir -p "$INSTALL_DIR"
$SUDO_CMD mkdir -p "$INSTALL_DIR/data"
if [ "$(id -u)" -ne 0 ] && [ -n "$SUDO_CMD" ]; then
    $SUDO_CMD chown -R "$(id -u):$(id -g)" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 写入 .env 文件
info "正在生成环境配置文件 (.env)..."
cat > .env << EOF
# QQ Runtime 生产环境部署配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 服务核心密钥与账号
RUNTIME_MASTER_KEY=${MASTER_KEY}
RUNTIME_BOOTSTRAP_ADMIN_USERNAME=${ADMIN_USER}
RUNTIME_BOOTSTRAP_ADMIN_PASSWORD=${ADMIN_PASS}

# 端口与网络
RUNTIME_HOST=0.0.0.0
RUNTIME_PORT=8080
RUNTIME_COOKIE_SECURE=false

# 数据目录
RUNTIME_DATA_DIR=/app/data
HOME=/app/data
XDG_DATA_HOME=/app/data
XDG_CONFIG_HOME=/app/data/config
XDG_CACHE_HOME=/app/data/cache

# 伴生更新服务安全通信 Token
RUNTIME_UPDATER_URL=http://updater:8080/v1/update
RUNTIME_UPDATER_TOKEN=${UPDATER_TOKEN}

# 插件沙箱默认策略
RUNTIME_PLUGIN_SANDBOX_ENABLED=true
RUNTIME_PLUGIN_SANDBOX_NETWORK=true
RUNTIME_PLUGIN_SANDBOX_TIMEOUT_SECONDS=300
RUNTIME_PLUGIN_SANDBOX_CPU_SECONDS=120
EOF
chmod 600 .env

# 写入 compose.yaml 文件
info "正在生成生产级容器编排文件 (compose.yaml)..."
cat > compose.yaml << EOF
services:
  runtime:
    image: ${IMAGE_NAME}
    container_name: qq-runtime
    env_file: .env
    ports:
      - "${INSTALL_PORT}:8080"
    volumes:
      - ./data:/app/data
    read_only: true
    tmpfs:
      - /tmp
    init: true
    security_opt:
      - no-new-privileges:true
    dns:
      - 223.5.5.5
      - 223.6.6.6
      - 119.29.29.29
      - 1.1.1.1
    healthcheck:
      test:
        - CMD
        - python
        - -c
        - >-
          import json,urllib.request;
          data=json.load(urllib.request.urlopen('http://127.0.0.1:8080/api/health', timeout=3));
          raise SystemExit(0 if data.get('ready') else 1)
      interval: 30s
      timeout: 5s
      start_period: 20s
      retries: 3
    stop_grace_period: 30s
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  updater:
    image: containrrr/watchtower:latest
    container_name: qq-runtime-updater
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      WATCHTOWER_HTTP_API_UPDATE: "true"
      WATCHTOWER_HTTP_API_TOKEN: ${UPDATER_TOKEN}
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_NO_STARTUP_MESSAGE: "true"
      WATCHTOWER_LABEL_ENABLE: "true"
    expose:
      - "8080"
EOF

# 7. 拉取镜像并启动
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第四步】拉取镜像并启动服务${NC}"
info "正在拉取镜像: $IMAGE_NAME ..."
$COMPOSE_CMD pull || error "镜像拉取失败，请检查网络连接或更换镜像加速源后重试"

info "正在启动容器集群..."
$COMPOSE_CMD up -d || error "容器启动失败，请检查 docker 日志"

# 8. 健康检查
info "等待服务就绪中..."
HEALTHY=false
for i in $(seq 1 30); do
    sleep 2
    if curl -s -f "http://127.0.0.1:${INSTALL_PORT}/api/health" >/dev/null 2>&1 || curl -s -f "http://127.0.0.1:${INSTALL_PORT}/healthz" >/dev/null 2>&1 || curl -s "http://127.0.0.1:${INSTALL_PORT}/" | grep -q "QQ Runtime" >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    echo -n "."
done
echo ""

if [ "$HEALTHY" = true ]; then
    success "QQ Runtime 服务已成功启动并通过健康检查！"
else
    warn "服务已启动，但在 60 秒内健康检查未完全就绪，请使用 '${COMPOSE_CMD} logs runtime' 观察日志"
fi

# 获取公网与内网 IP
PUBLIC_IP=$(curl -s4 -m 3 ifconfig.me 2>/dev/null || curl -s4 -m 3 ip.sb 2>/dev/null || echo "服务器公网IP")
LOCAL_IP=$(ip -4 addr show scope global 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1 || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

# 9. 打印安装成功卡片
echo ""
echo "=================================================================="
echo -e "${GREEN}${BOLD}🎉 QQ Runtime 部署成功！${NC}"
echo "=================================================================="
echo -e " 🌐 ${BOLD}控制台访问地址:${NC}"
echo -e "    - 公网访问: ${CYAN}http://${PUBLIC_IP}:${INSTALL_PORT}${NC}"
echo -e "    - 内网访问: ${CYAN}http://${LOCAL_IP}:${INSTALL_PORT}${NC}"
echo -e "    - 本地访问: ${CYAN}http://127.0.0.1:${INSTALL_PORT}${NC}"
echo ""
echo -e " 🔑 ${BOLD}管理员登录凭证:${NC}"
echo -e "    - 初始用户名: ${YELLOW}${ADMIN_USER}${NC}"
echo -e "    - 初始密码:   ${YELLOW}${ADMIN_PASS}${NC}"
echo -e "    - 主密钥:     ${PURPLE}${MASTER_KEY}${NC}"
echo ""
echo -e " 📁 ${BOLD}部署目录与数据:${NC}"
echo -e "    - 安装目录:   ${INSTALL_DIR}"
echo -e "    - 配置文件:   ${INSTALL_DIR}/.env"
echo -e "    - 数据目录:   ${INSTALL_DIR}/data"
echo ""
echo -e " 🛠️  ${BOLD}常用运维指令 (需在 ${INSTALL_DIR} 目录下执行):${NC}"
echo -e "    - 查看运行日志: ${BOLD}${COMPOSE_CMD} logs -f runtime${NC}"
echo -e "    - 查看容器状态: ${BOLD}${COMPOSE_CMD} ps${NC}"
echo -e "    - 重启整个服务: ${BOLD}${COMPOSE_CMD} restart${NC}"
echo -e "    - 停止服务:     ${BOLD}${COMPOSE_CMD} down${NC}"
echo -e "    - 镜像一键更新: ${BOLD}${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d${NC}"
echo "=================================================================="
echo -e "${YELLOW}提示: 请妥善保存上述密码与密钥。首次登录后建议在控制台修改密码。${NC}"
echo ""
