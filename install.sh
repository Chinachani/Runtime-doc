#!/usr/bin/env bash
# ==============================================================================
# QQ Runtime 服务器智能一键部署脚本
# 支持系统自检、硬件规格评估、可选服务编排、国内镜像加速源配置与伴生自动更新
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

# 确保能从终端交互读取（兼容 curl ... | bash 与 CI 自动化）
get_input() {
    local prompt="$1"
    local default_val="$2"
    local answer=""
    if [ -n "$CI" ] || [ -n "$NONINTERACTIVE" ] || [ "$DEBIAN_FRONTEND" = "noninteractive" ]; then
        echo "$default_val"
        return
    fi
    if [ -t 0 ]; then
        read -r -p "$prompt" answer
    elif [ -r /dev/tty ] && [ -w /dev/tty ]; then
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

# 2. 系统硬件自检与规格评估
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
TOTAL_MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
AVAIL_MEM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
AVAIL_MEM_MB=$((AVAIL_MEM_KB / 1024))
if [ "$TOTAL_MEM_MB" -ge 1024 ]; then
    TOTAL_MEM_STR="$(awk "BEGIN {printf \"%.1f GB\", $TOTAL_MEM_MB/1024}")"
else
    TOTAL_MEM_STR="${TOTAL_MEM_MB} MB"
fi
DISK_AVAIL_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "未知")

echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【硬件自检与规格评估】${NC}"
echo -e " • CPU 核心数:     ${CYAN}${CPU_CORES} 核心${NC}"
echo -e " • 系统物理内存:   ${CYAN}${TOTAL_MEM_STR}${NC} (当前可用: ${AVAIL_MEM_MB} MB)"
echo -e " • 根分区可用磁盘: ${CYAN}${DISK_AVAIL_GB} GB${NC}"
echo ""
echo -e "${BOLD}💡 官方推荐硬件规格建议:${NC}"
echo -e " [1] 核心最小化 (Runtime + Dashboard + Watchtower):"
echo -e "     - 最低配置: 1 核 CPU / 1 GB 内存 (建议配置 1~2G Swap) / 5 GB 磁盘"
echo -e "     - 适用场景: 基础群管、官方原生 Markdown 卡片、指令互动 (常驻内存 ~350MB)"
echo -e " [2] 媒体增强版 (核心 + B站独立解析 + 抖音独立解析) ${GREEN}[推荐]${NC}:"
echo -e "     - 最低配置: 2 核 CPU / 1.5 GB ~ 2 GB 内存 / 10 GB 磁盘"
echo -e "     - 适用场景: 群内高频分享 B站/抖音 视频解析、音视频转码发送"
echo -e " [3] 全功能套件 (媒体增强版 + 文件/视频水印清理):"
echo -e "     - 最低配置: 2 核 CPU / 2.5 GB ~ 3 GB 内存 / 15 GB 磁盘 (推荐 4G 内存)"
echo -e "     - 适用场景: 全媒体解析 + PDF/文档/图片/视频元数据与水印强力清理"
echo "------------------------------------------------------------------"

if [ "$TOTAL_MEM_MB" -gt 0 ] && [ "$TOTAL_MEM_MB" -lt 1500 ]; then
    warn "⚠️  检测到当前可用物理内存小于 1.5 GB (${TOTAL_MEM_STR})！"
    warn "强烈建议在后续步骤中选择【2) 核心最小化】模式，或在部署前为服务器配置 1~2GB Swap 虚拟内存，以防 OOM。"
fi

# 磁盘剩余空间硬性检测
if [ "$DISK_AVAIL_GB" != "未知" ]; then
    if [ "$DISK_AVAIL_GB" -lt 2 ]; then
        error "根分区可用磁盘空间仅剩 ${DISK_AVAIL_GB} GB（不足 2 GB）！拉取与解压 Docker 镜像可能会耗尽磁盘空间，请先清理磁盘后重试。"
    elif [ "$DISK_AVAIL_GB" -lt 5 ]; then
        warn "⚠️  根分区可用磁盘空间为 ${DISK_AVAIL_GB} GB（较为紧张），建议部署后定期执行 docker system prune 清理构建缓存。"
    fi
fi

# 网络与 DNS 解析健康连通性检测
info "正在探测网络与 DNS 域名解析连通性..."
DNS_PROBE_SUCCESS=false
for probe_domain in "ghcr.1ms.run" "ghcr.nju.edu.cn" "ghcr.io" "github.com"; do
    if command -v getent >/dev/null 2>&1 && getent ahosts "$probe_domain" >/dev/null 2>&1; then
        DNS_PROBE_SUCCESS=true
        break
    elif command -v nslookup >/dev/null 2>&1 && nslookup "$probe_domain" >/dev/null 2>&1; then
        DNS_PROBE_SUCCESS=true
        break
    fi
done
if [ "$DNS_PROBE_SUCCESS" = true ]; then
    success "DNS 域名解析与网络探测正常"
else
    warn "⚠️  未能成功解析公网镜像源域名，请检查服务器网络或 /etc/resolv.conf 中的 nameserver 配置（推荐 223.5.5.5 或 119.29.29.29）"
fi

# 3. Docker 与 Docker Compose 检测
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

# 4. 安装参数配置
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第一步】配置安装目录与端口${NC}"
DEFAULT_INSTALL_DIR=${INSTALL_DIR:-"/opt/qq-runtime"}
if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO_CMD" ]; then
    DEFAULT_INSTALL_DIR=${INSTALL_DIR:-"$HOME/qq-runtime"}
fi

INSTALL_DIR=$(get_input "请输入安装目录路径 [默认: ${DEFAULT_INSTALL_DIR}]: " "$DEFAULT_INSTALL_DIR")

# 端口可用性与冲突检测函数
check_port_occupied() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -qE "(:|\])${p}\b"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -qE "(:|\])${p}\b"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
    else
        (echo >/dev/tcp/127.0.0.1/"$p") >/dev/null 2>&1
    fi
}

DEFAULT_PORT=${INSTALL_PORT:-8080}
while true; do
    INSTALL_PORT=$(get_input "请输入管理台外部访问端口 [默认: ${DEFAULT_PORT}]: " "$DEFAULT_PORT")
    if [[ ! "$INSTALL_PORT" =~ ^[0-9]+$ ]] || [ "$INSTALL_PORT" -lt 1 ] || [ "$INSTALL_PORT" -gt 65535 ]; then
        warn "端口必须是 1~65535 之间的有效端口号，请重新输入"
        continue
    fi
    if check_port_occupied "$INSTALL_PORT"; then
        warn "⚠️  检测到端口 ${INSTALL_PORT} 已处于监听状态（可能已被 Nginx/Apache/其他容器占用）！"
        OCCUPIED_INFO=""
        if command -v ss >/dev/null 2>&1; then
            OCCUPIED_INFO=$(ss -tulnp 2>/dev/null | grep -E "(:|\])${INSTALL_PORT}\b" | head -n 1 || true)
        elif command -v lsof >/dev/null 2>&1; then
            OCCUPIED_INFO=$(lsof -iTCP:"$INSTALL_PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -n 1 || true)
        fi
        if [ -n "$OCCUPIED_INFO" ]; then
            warn "   占用进程信息: $OCCUPIED_INFO"
        fi
        warn "如果端口冲突，Docker 容器将无法正常绑定外部访问端口。"
        CONFIRM_PORT=$(get_input "是否仍要强制使用端口 ${INSTALL_PORT}？[y/N]: " "N")
        case "$CONFIRM_PORT" in
            [yY][eE][sS]|[yY]) break ;;
            *) DEFAULT_PORT="8081"; continue ;;
        esac
    else
        success "端口 ${INSTALL_PORT} 检测通过（空闲可用）"
        break
    fi
done

# 检测防火墙规则并给出放行指引
FIREWALL_HINT=""
if command -v ufw >/dev/null 2>&1 && $SUDO_CMD ufw status 2>/dev/null | grep -q "Status: active"; then
    FIREWALL_HINT="sudo ufw allow ${INSTALL_PORT}/tcp"
    info "检测到系统启用了 UFW 防火墙。若安装后外部无法访问，请执行: ${BOLD}${FIREWALL_HINT}${NC}"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    FIREWALL_HINT="sudo firewall-cmd --add-port=${INSTALL_PORT}/tcp --permanent && sudo firewall-cmd --reload"
    info "检测到系统启用了 firewalld 防火墙。若安装后外部无法访问，请执行: ${BOLD}${FIREWALL_HINT}${NC}"
fi

# 5. 镜像源交互选择
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
        IMAGE_PREFIX="ghcr.1ms.run"
        IMAGE_DESC="ghcr.1ms.run (国内毫秒级高速)"
        ;;
    2)
        IMAGE_PREFIX="ghcr.nju.edu.cn"
        IMAGE_DESC="ghcr.nju.edu.cn (南京大学开源镜像站)"
        ;;
    3)
        IMAGE_PREFIX="ghcr.milu.moe"
        IMAGE_DESC="ghcr.milu.moe (麋鹿社区加速)"
        ;;
    4)
        IMAGE_PREFIX="docker.m.daocloud.io/ghcr.io"
        IMAGE_DESC="docker.m.daocloud.io (DaoCloud 加速)"
        ;;
    5)
        IMAGE_PREFIX="ghcr.io"
        IMAGE_DESC="ghcr.io (GitHub 官方全球源)"
        ;;
    *)
        IMAGE_PREFIX="ghcr.1ms.run"
        IMAGE_DESC="ghcr.1ms.run (国内毫秒级高速)"
        ;;
esac

# 推导全系列容器镜像地址
IMAGE_NAME="${IMAGE_PREFIX}/chinachani/qq-runtime:latest"
DASHBOARD_IMAGE_NAME="${IMAGE_PREFIX}/chinachani/qq-runtime-dashboard:latest"
BILI_IMAGE_NAME="${IMAGE_PREFIX}/chinachani/bilibiliwatch-api:latest"
DY_IMAGE_NAME="${IMAGE_PREFIX}/chinachani/douyinwatch-api:latest"
if [ "$MIRROR_CHOICE" = "5" ]; then
    WATERMARKS_IMAGE_NAME="ghcr.io/guillaumemeyer/watermarks-remover:latest"
else
    WATERMARKS_IMAGE_NAME="${IMAGE_PREFIX}/guillaumemeyer/watermarks-remover:latest"
fi

info "已选主镜像:   ${BOLD}$IMAGE_NAME${NC} ($IMAGE_DESC)"
info "控制台镜像:   ${BOLD}$DASHBOARD_IMAGE_NAME${NC}"

# 6. 服务部署档位选择
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第三步】选择服务部署模式${NC}"
echo -e " 1) ${GREEN}媒体增强版 [推荐]${NC} (Runtime + 控制台 + 伴生更新 + B站解析 + 抖音解析)"
echo " 2) 核心最小化        (仅 Runtime + 控制台 + 伴生更新，超低内存占用，适合 1G 机器)"
echo " 3) 全功能套件        (包含全部附加容器：核心 + B站 + 抖音 + 水印清理)"
echo " 4) 自定义组件选择    (由您自主勾选需要启用的解析容器)"
echo ""

PROFILE_CHOICE=${INSTALL_PROFILE:-""}
if [ -z "$PROFILE_CHOICE" ]; then
    PROFILE_CHOICE=$(get_input "请选择部署模式 (1-4) [默认: 1]: " "1")
fi

ENABLE_BILI=false
ENABLE_DY=false
ENABLE_WATERMARKS=false

case "$PROFILE_CHOICE" in
    1)
        ENABLE_BILI=true
        ENABLE_DY=true
        ENABLE_WATERMARKS=false
        PROFILE_NAME="媒体增强版 (核心 + B站解析 + 抖音解析)"
        ;;
    2)
        ENABLE_BILI=false
        ENABLE_DY=false
        ENABLE_WATERMARKS=false
        PROFILE_NAME="核心最小化 (仅基础核心与控制台)"
        ;;
    3)
        ENABLE_BILI=true
        ENABLE_DY=true
        ENABLE_WATERMARKS=true
        PROFILE_NAME="全功能套件 (全量服务包含水印清理)"
        ;;
    4)
        PROFILE_NAME="自定义组件组合"
        echo ""
        info "请配置各项附加组件开关："

        BILI_INPUT=$(get_input "• 是否部署 B站音视频解析容器 (bilibiliwatch-api)？[Y/n]: " "Y")
        case "$BILI_INPUT" in
            [nN][oO]|[nN]) ENABLE_BILI=false ;;
            *) ENABLE_BILI=true ;;
        esac

        DY_INPUT=$(get_input "• 是否部署 抖音分享链接解析容器 (douyinwatch-api)？[Y/n]: " "Y")
        case "$DY_INPUT" in
            [nN][oO]|[nN]) ENABLE_DY=false ;;
            *) ENABLE_DY=true ;;
        esac

        WM_INPUT=$(get_input "• 是否部署 文件/视频水印清理容器 (watermarks-remover)？[y/N]: " "N")
        case "$WM_INPUT" in
            [yY][eE][sS]|[yY]) ENABLE_WATERMARKS=true ;;
            *) ENABLE_WATERMARKS=false ;;
        esac
        ;;
    *)
        ENABLE_BILI=true
        ENABLE_DY=true
        ENABLE_WATERMARKS=false
        PROFILE_NAME="媒体增强版 (核心 + B站解析 + 抖音解析)"
        ;;
esac

# 允许环境变量外部覆盖
if [ -n "$INSTALL_ENABLE_BILI" ]; then ENABLE_BILI="$INSTALL_ENABLE_BILI"; fi
if [ -n "$INSTALL_ENABLE_DY" ]; then ENABLE_DY="$INSTALL_ENABLE_DY"; fi
if [ -n "$INSTALL_ENABLE_WATERMARKS" ]; then ENABLE_WATERMARKS="$INSTALL_ENABLE_WATERMARKS"; fi

info "已选部署档位: ${BOLD}${PROFILE_NAME}${NC}"
info "附加服务状态: B站解析 [$( [ "$ENABLE_BILI" = true ] && echo -e "${GREEN}启用${NC}" || echo -e "${YELLOW}未启用${NC}" )] | 抖音解析 [$( [ "$ENABLE_DY" = true ] && echo -e "${GREEN}启用${NC}" || echo -e "${YELLOW}未启用${NC}" )] | 水印清理 [$( [ "$ENABLE_WATERMARKS" = true ] && echo -e "${GREEN}启用${NC}" || echo -e "${YELLOW}未启用${NC}" )]"

# 7. 管理员账号与安全密钥配置
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第四步】管理员初始账户配置${NC}"
ADMIN_USER=$(get_input "请输入初始管理员用户名 [默认: admin]: " "admin")

# 自动生成 16 位高强度安全密码
AUTO_GEN_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 16 2>/dev/null || openssl rand -base64 12 2>/dev/null || echo "QqRuntime@2026")
ADMIN_PASS=$(get_input "请输入管理员初始密码 [默认自动随机高强度密码]: " "$AUTO_GEN_PASS")

if [ "${#ADMIN_PASS}" -lt 8 ]; then
    warn "⚠️  您输入的管理员密码长度小于 8 位，密码强度较弱，容易遭受字典暴力破解！"
    warn "建议首次登录管理台后尽快在【系统与管理 -> 账户安全】中修改为更强密码。"
fi

# 强随机 Master Key 与通信 Token
MASTER_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 64)
UPDATER_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)
BILI_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)
DY_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)
WATERMARKS_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)

# 8. 创建目录并写入配置
info "正在初始化安装目录: $INSTALL_DIR"
PARENT_DIR="$(dirname "$INSTALL_DIR" 2>/dev/null || echo "")"
if [ -w "$INSTALL_DIR" ] || { [ ! -e "$INSTALL_DIR" ] && [ -w "$PARENT_DIR" ]; }; then
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/data"
    if [ "$ENABLE_BILI" = true ]; then mkdir -p "$INSTALL_DIR/data/bilibili"; fi
    if [ "$ENABLE_DY" = true ]; then mkdir -p "$INSTALL_DIR/data/douyin"; fi
else
    $SUDO_CMD mkdir -p "$INSTALL_DIR"
    $SUDO_CMD mkdir -p "$INSTALL_DIR/data"
    if [ "$ENABLE_BILI" = true ]; then $SUDO_CMD mkdir -p "$INSTALL_DIR/data/bilibili"; fi
    if [ "$ENABLE_DY" = true ]; then $SUDO_CMD mkdir -p "$INSTALL_DIR/data/douyin"; fi
    if [ "$(id -u)" -ne 0 ] && [ -n "$SUDO_CMD" ]; then
        $SUDO_CMD chown -R "$(id -u):$(id -g)" "$INSTALL_DIR"
    fi
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

# 新版 Next.js 控制台服务（compose 内部网络地址）
RUNTIME_DASHBOARD_URL=http://dashboard:3000

# 伴生更新服务安全通信 Token
RUNTIME_UPDATER_URL=http://updater:8080/v1/update
RUNTIME_UPDATER_TOKEN=${UPDATER_TOKEN}
EOF

# 按需写入附加解析服务配置（内部容器网络直连，无需向外暴露端口）
if [ "$ENABLE_BILI" = true ]; then
    cat >> .env << EOF

# B站音视频解析服务 (独立 sidecar 容器网络)
BILI_VIDEO_API_BASE_URL=http://bilibiliwatch:8000
BILI_VIDEO_API_LOGIN_TOKEN=${BILI_TOKEN}
EOF
fi

if [ "$ENABLE_DY" = true ]; then
    cat >> .env << EOF

# 抖音音视频解析服务 (独立 sidecar 容器网络)
DY_DOUYIN_API_BASE_URL=http://douyinwatch:8001
DY_DOUYIN_API_TOKEN=${DY_TOKEN}
EOF
fi

if [ "$ENABLE_WATERMARKS" = true ]; then
    cat >> .env << EOF

# 水印清理服务 Token
WATERMARKS_SERVICE_TOKEN=${WATERMARKS_TOKEN}
EOF
fi

cat >> .env << EOF

# 插件沙箱默认策略
RUNTIME_PLUGIN_SANDBOX_ENABLED=true
RUNTIME_PLUGIN_SANDBOX_NETWORK=true
RUNTIME_PLUGIN_SANDBOX_TIMEOUT_SECONDS=300
RUNTIME_PLUGIN_SANDBOX_MEMORY_MB=1024
RUNTIME_PLUGIN_SANDBOX_CPU_SECONDS=0
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

  dashboard:
    # 新版 Next.js 管理台。runtime 通过 RUNTIME_DASHBOARD_URL 同源代理该服务；
    # 缺失它会静默回退到旧版 legacy 静态控制台。
    image: ${DASHBOARD_IMAGE_NAME}
    container_name: qq-runtime-dashboard
    environment:
      NODE_ENV: production
      PORT: "3000"
      RUNTIME_API_ORIGIN: "http://runtime:8080"
    init: true
    security_opt:
      - no-new-privileges:true
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

if [ "$ENABLE_BILI" = true ]; then
    cat >> compose.yaml << EOF

  bilibiliwatch:
    # B站音视频解析独立 sidecar 服务（FastAPI 端口 8000）
    image: ${BILI_IMAGE_NAME}
    container_name: qq-runtime-bilibili
    environment:
      LOGIN_TOKEN: ${BILI_TOKEN}
      API_TOKEN: ${BILI_TOKEN}
      CONFIG_FILE: /app/data/config.json
      TZ: Asia/Shanghai
    volumes:
      - ./data/bilibili:/app/data
    expose:
      - "8000"
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
fi

if [ "$ENABLE_DY" = true ]; then
    cat >> compose.yaml << EOF

  douyinwatch:
    # 抖音分享解析独立 sidecar 服务（FastAPI 端口 8001）
    image: ${DY_IMAGE_NAME}
    container_name: qq-runtime-douyin
    environment:
      API_TOKEN: ${DY_TOKEN}
      DATA_DIR: /data
      TZ: Asia/Shanghai
    volumes:
      - ./data/douyin:/data
    expose:
      - "8001"
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
fi

if [ "$ENABLE_WATERMARKS" = true ]; then
    cat >> compose.yaml << EOF

  watermarks-remover:
    # 水印清理 sidecar（上游官方镜像，内置 exiftool/qpdf/ghostscript/ffmpeg）
    image: ${WATERMARKS_IMAGE_NAME}
    container_name: qq-runtime-watermarks
    environment:
      WATERMARKS_SERVER_API_KEY: ${WATERMARKS_TOKEN}
    expose:
      - "8765"
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    restart: unless-stopped
EOF
fi

# 9. 拉取镜像并启动
echo ""
echo "------------------------------------------------------------------"
echo -e "${BOLD}【第五步】拉取镜像并启动服务${NC}"
info "正在拉取核心镜像: $IMAGE_NAME ..."
$COMPOSE_CMD pull runtime updater || error "核心镜像拉取失败，请检查网络连接或更换镜像加速源后重试"

SCALE_ARGS=""

# dashboard 镜像随正式版本发布；拉取失败时降级为旧版 legacy 控制台而不是中断安装
if $COMPOSE_CMD pull dashboard 2>/dev/null; then
    info "新版控制台镜像拉取成功"
else
    warn "新版控制台镜像 ($DASHBOARD_IMAGE_NAME) 拉取失败，本次将使用旧版 legacy 控制台"
    warn "可稍后执行: ${COMPOSE_CMD} pull dashboard && ${COMPOSE_CMD} up -d 切换到新版控制台"
    SCALE_ARGS="$SCALE_ARGS --scale dashboard=0"
fi

if [ "$ENABLE_BILI" = true ]; then
    info "正在拉取 B站解析服务镜像: $BILI_IMAGE_NAME ..."
    if $COMPOSE_CMD pull bilibiliwatch 2>/dev/null; then
        info "B站解析服务镜像拉取成功"
    else
        warn "B站解析镜像拉取失败或尚未构建完成，该服务将暂时跳过启动"
        warn "可稍后执行: ${COMPOSE_CMD} pull bilibiliwatch && ${COMPOSE_CMD} up -d"
        SCALE_ARGS="$SCALE_ARGS --scale bilibiliwatch=0"
    fi
fi

if [ "$ENABLE_DY" = true ]; then
    info "正在拉取 抖音解析服务镜像: $DY_IMAGE_NAME ..."
    if $COMPOSE_CMD pull douyinwatch 2>/dev/null; then
        info "抖音解析服务镜像拉取成功"
    else
        warn "抖音解析镜像拉取失败或尚未构建完成，该服务将暂时跳过启动"
        warn "可稍后执行: ${COMPOSE_CMD} pull douyinwatch && ${COMPOSE_CMD} up -d"
        SCALE_ARGS="$SCALE_ARGS --scale douyinwatch=0"
    fi
fi

if [ "$ENABLE_WATERMARKS" = true ]; then
    info "正在拉取 水印清理服务镜像: $WATERMARKS_IMAGE_NAME ..."
    if $COMPOSE_CMD pull watermarks-remover 2>/dev/null; then
        info "水印清理服务镜像拉取成功"
    else
        warn "水印清理服务镜像拉取失败，可稍后执行: ${COMPOSE_CMD} pull watermarks-remover && ${COMPOSE_CMD} up -d"
        SCALE_ARGS="$SCALE_ARGS --scale watermarks-remover=0"
    fi
fi

info "正在启动容器集群..."
$COMPOSE_CMD up -d $SCALE_ARGS || error "容器启动失败，请检查 docker 日志"

# 10. 健康检查
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

# 11. 打印安装成功卡片
echo ""
echo "=================================================================="
echo -e "${GREEN}${BOLD}🎉 QQ Runtime 部署成功！${NC}"
echo "=================================================================="
echo -e " 🌐 ${BOLD}控制台访问地址:${NC}"
echo -e "    - 公网访问: ${CYAN}http://${PUBLIC_IP}:${INSTALL_PORT}${NC}"
echo -e "    - 内网访问: ${CYAN}http://${LOCAL_IP}:${INSTALL_PORT}${NC}"
echo -e "    - 本地访问: ${CYAN}http://127.0.0.1:${INSTALL_PORT}${NC}"
echo ""
echo -e " 📦 ${BOLD}服务部署模式:${NC} ${BOLD}${PROFILE_NAME}${NC}"
echo -e "    - 核心引擎: ${GREEN}[正常运行]${NC} (Runtime + Next.js 控制台 + 伴生自动更新)"
echo -e "    - B站解析:  $( [ "$ENABLE_BILI" = true ] && echo -e "${GREEN}[已启用]${NC} (bilibiliwatch-api 独立容器)" || echo -e "${YELLOW}[未启用]${NC}" )"
echo -e "    - 抖音解析: $( [ "$ENABLE_DY" = true ] && echo -e "${GREEN}[已启用]${NC} (douyinwatch-api 独立容器)" || echo -e "${YELLOW}[未启用]${NC}" )"
echo -e "    - 水印清理: $( [ "$ENABLE_WATERMARKS" = true ] && echo -e "${GREEN}[已启用]${NC} (watermarks-remover 独立容器)" || echo -e "${YELLOW}[未启用]${NC}" )"
echo ""
echo -e " 🔑 ${BOLD}管理员登录凭证:${NC}"
echo -e "    - 初始用户名: ${YELLOW}${ADMIN_USER}${NC}"
echo -e "    - 初始密码:   ${YELLOW}${ADMIN_PASS}${NC}"
echo -e "    - 主密钥:     ${PURPLE}${MASTER_KEY}${NC}"
echo ""
if [ -n "$FIREWALL_HINT" ]; then
    echo -e " 🛡️  ${BOLD}防火墙放行提示:${NC}"
    echo -e "    - 本机防火墙指令: ${YELLOW}${FIREWALL_HINT}${NC}"
    echo -e "    - 云服务器安全组: 请确认已在阿里云/腾讯云/华为云等控制台【安全组】放行 TCP ${INSTALL_PORT} 入方向端口"
    echo ""
fi
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
