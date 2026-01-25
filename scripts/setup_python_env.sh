#!/bin/bash
#
# 为 Site Manager 配置系统级 Python 环境
# 类似宝塔面板的 /www/server/panel/pyenv 架构
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PYENV_DIR="/opt/site_manager/pyenv"  # 系统级 Python 环境

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}>>> $1${NC}"; }

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 权限运行"
    exit 1
fi

log_step "配置 Site Manager 系统级 Python 环境..."

# 1. 安装 uv（如果未安装）
if ! command -v uv &> /dev/null; then
    log_info "安装 uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="/root/.local/bin:$PATH"

    if ! command -v uv &> /dev/null; then
        log_error "uv 安装失败"
        exit 1
    fi
    log_info "uv 安装成功: $(uv --version)"
else
    log_info "uv 已安装: $(uv --version)"
fi

# 2. 创建系统级 Python 环境
if [ -d "$PYENV_DIR" ]; then
    log_warn "Python 环境已存在: $PYENV_DIR"
    read -p "是否重新创建？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$PYENV_DIR"
    else
        log_info "跳过创建"
        exit 0
    fi
fi

log_info "创建系统级 Python 环境..."
uv venv "$PYENV_DIR" --python 3.12
log_info "虚拟环境创建成功: $PYENV_DIR"

# 3. 安装基础依赖
log_info "安装基础依赖..."
cd "$PROJECT_ROOT"

# 激活环境并安装依赖
source "$PYENV_DIR/bin/activate"

# 安装常用包
uv pip install \
    requests \
    loguru \
    psutil \
    pyyaml \
    click \
    jinja2

log_info "基础依赖安装完成"

# 安装 Certbot（SSL 证书管理）
log_info "安装 Certbot..."
uv pip install certbot certbot-dns-cloudflare

log_info "Certbot 安装完成: $(source $PYENV_DIR/bin/activate && certbot --version)"

# 4. 保存已安装包列表
uv pip freeze > "$PYENV_DIR/requirements.txt"
log_info "已保存包列表: $PYENV_DIR/requirements.txt"

# 5. 创建便捷命令包装器
log_info "创建命令包装器..."

# Python 包装器
cat > "/usr/local/bin/site-python" << EOF
#!/bin/bash
# Site Manager 系统级 Python 环境
exec "$PYENV_DIR/bin/python" "\$@"
EOF
chmod +x "/usr/local/bin/site-python"

# pip 包装器（使用 uv pip）
cat > "/usr/local/bin/site-pip" << 'EOF'
#!/bin/bash
# Site Manager 系统级 pip
source /opt/site_manager/pyenv/bin/activate
exec uv pip "$@"
EOF
chmod +x "/usr/local/bin/site-pip"

# certbot 包装器
cat > "/usr/local/bin/certbot" << 'EOF'
#!/bin/bash
# Site Manager Certbot 包装器（使用 pyenv 环境）
exec /opt/site_manager/pyenv/bin/certbot "$@"
EOF
chmod +x "/usr/local/bin/certbot"

log_step "配置完成！"
echo ""
log_info "环境路径: $PYENV_DIR"
log_info "Python 版本: $($PYENV_DIR/bin/python --version)"
log_info "Certbot 版本: $(source $PYENV_DIR/bin/activate && certbot --version)"
echo ""
log_info "使用方法："
echo "  1. 使用系统级 Python: site-python your_script.py"
echo "  2. 安装包: site-pip install <package>"
echo "  3. 查看已安装: site-pip list"
echo "  4. SSL 证书: certbot (或 site ssl 命令)"
echo "  5. 激活环境: source $PYENV_DIR/bin/activate"
echo ""
log_info "已安装的包："
source "$PYENV_DIR/bin/activate"
uv pip list
