#!/bin/bash
# ============================================================
# OpenClaw Gateway 监控一键部署脚本
# 仓库：mzhscan/openclaw-gateway-start
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/mzhscan/openclaw-gateway-start/main/install.sh)
# ============================================================

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 脚本保存目录
INSTALL_DIR="/opt/scripts"
LOG_DIR="/var/log/monitor"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  OpenClaw Gateway 监控 - 一键部署脚本        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# ============== 选择部署模式 ==============
echo -e "${YELLOW}请选择部署模式：${NC}"
echo "  1) 本机监控（监控本机 OpenClaw Gateway，挂了自动拉起）"
echo "  2) 远程监控（部署在远端，监控另一台机器的 Gateway）"
echo ""
read -p "请输入选项 [1/2]: " MODE

case "$MODE" in
    1) SCRIPT_TYPE="local" ;;
    2) SCRIPT_TYPE="remote" ;;
    *) echo -e "${RED}❌ 无效选项${NC}"; exit 1 ;;
esac

echo ""
echo -e "${GREEN}✅ 已选择：$([[ $SCRIPT_TYPE == local ]] && echo '本机监控' || echo '远程监控')${NC}"
echo ""

# ============== 是否配置 Bark 推送 ==============
read -p "是否配置 Bark 推送通知？[y/N]: " USE_BARK

USE_BARK_FLAG=false
BARK_BASE=""
BARK_KEY=""
BARK_GROUP=""
BARK_ICON=""

if [[ "$USE_BARK" =~ ^[Yy]$ ]]; then
    USE_BARK_FLAG=true

    echo ""
    echo -e "${YELLOW}📱 Bark 配置${NC}"
    echo "----------------------------------------"

    # Bark Base URL
    while true; do
        read -p "请输入 Bark 服务地址（例：https://bark.doogeee.cn:3210）: " BARK_BASE
        if [[ -z "$BARK_BASE" ]]; then
            echo -e "${RED}❌ Bark 地址不能为空${NC}"
            continue
        fi
        if [[ ! "$BARK_BASE" =~ ^https?:// ]]; then
            BARK_BASE="https://$BARK_BASE"
        fi
        BARK_BASE="${BARK_BASE%/}"
        break
    done

    # Bark Key
    while true; do
        read -p "请输入 Bark 设备 Key: " BARK_KEY
        if [[ -z "$BARK_KEY" ]]; then
            echo -e "${RED}❌ Bark Key 不能为空${NC}"
            continue
        fi
        break
    done

    # 分组（可选）
    read -p "是否设置推送分组？[y/N]: " USE_GROUP
    if [[ "$USE_GROUP" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "请输入分组名称: " BARK_GROUP
            if [[ -z "$BARK_GROUP" ]]; then
                echo -e "${RED}❌ 分组名称不能为空${NC}"
                continue
            fi
            break
        done
    fi

    # 标题（必填）
    while true; do
        read -p "请输入推送标题: " BARK_TITLE
        if [[ -z "$BARK_TITLE" ]]; then
            echo -e "${RED}❌ 标题不能为空${NC}"
            continue
        fi
        break
    done

    # 通知内容（必填）
    while true; do
        read -p "请输入通知内容: " BARK_BODY
        if [[ -z "$BARK_BODY" ]]; then
            echo -e "${RED}❌ 通知内容不能为空${NC}"
            continue
        fi
        break
    done

    # 图标（可选）
    read -p "是否设置自定义推送图标？[y/N]: " USE_ICON
    if [[ "$USE_ICON" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "请输入图标 URL（必须以 http:// 或 https:// 开头）: " BARK_ICON
            if [[ -z "$BARK_ICON" ]]; then
                echo -e "${RED}❌ 图标 URL 不能为空${NC}"
                continue
            fi
            if [[ ! "$BARK_ICON" =~ ^https?:// ]]; then
                echo -e "${RED}❌ 图标 URL 必须以 http:// 或 https:// 开头${NC}"
                continue
            fi
            break
        done
    fi

    echo ""
    echo -e "${GREEN}✅ Bark 配置完成${NC}"
    echo "----------------------------------------"
    echo "Bark 地址: $BARK_BASE"
    echo "设备 Key: $BARK_KEY"
    [[ -n "$BARK_GROUP" ]] && echo "分组: $BARK_GROUP"
    echo "标题: $BARK_TITLE"
    echo "内容: $BARK_BODY"
    [[ -n "$BARK_ICON" ]] && echo "图标: $BARK_ICON"
    echo "----------------------------------------"
    echo ""
fi

# ============== 远程模式额外配置 ==============
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PASS=""
REMOTE_PORT=""
SSH_TIMEOUT=10

if [[ "$SCRIPT_TYPE" == "remote" ]]; then
    echo -e "${YELLOW}🖥️  被监控机器配置${NC}"
    echo "----------------------------------------"

    while true; do
        read -p "请输入被监控机器的 IP 或域名: " REMOTE_HOST
        if [[ -z "$REMOTE_HOST" ]]; then
            echo -e "${RED}❌ IP/域名不能为空${NC}"
            continue
        fi
        break
    done

    while true; do
        read -p "请输入 SSH 用户名: " REMOTE_USER
        if [[ -z "$REMOTE_USER" ]]; then
            echo -e "${RED}❌ 用户名不能为空${NC}"
            continue
        fi
        break
    done

    while true; do
        read -sp "请输入 SSH 密码: " REMOTE_PASS
        echo ""
        if [[ -z "$REMOTE_PASS" ]]; then
            echo -e "${RED}❌ 密码不能为空${NC}"
            continue
        fi
        break
    done

    while true; do
        read -p "请输入 SSH 端口 [默认 22]: " REMOTE_PORT
        REMOTE_PORT="${REMOTE_PORT:-22}"
        if ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ 端口必须是数字${NC}"
            continue
        fi
        break
    done

    echo ""
    echo -e "${GREEN}✅ 远程配置完成${NC}"
    echo "----------------------------------------"
    echo "目标主机: $REMOTE_HOST"
    echo "用户名: $REMOTE_USER"
    echo "端口: $REMOTE_PORT"
    echo "----------------------------------------"
    echo ""

    # 检查/安装 sshpass
    if ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  sshpass 未安装，正在自动安装...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y sshpass
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y sshpass
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y sshpass
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add sshpass
        else
            echo -e "${RED}❌ 无法自动安装 sshpass，请手动安装后重试${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✅ sshpass 已就绪${NC}"
fi

# ============== 检查 root 权限 ==============
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 请使用 sudo 重新运行本脚本${NC}"
    echo -e "${YELLOW}   示例: sudo bash <(curl -Ls ...)${NC}"
    exit 1
else
    SUDO=""
fi

# ============== 创建目录 ==============
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO mkdir -p "$LOG_DIR"

# ============== 下载脚本本体 ==============
echo ""
echo -e "${BLUE}📥 正在下载脚本...${NC}"

REPO_BASE="https://raw.githubusercontent.com/mzhscan/openclaw-gateway-start/main"

if [[ "$SCRIPT_TYPE" == "local" ]]; then
    SCRIPT_NAME="monitor-gateway-local.sh"
else
    SCRIPT_NAME="monitor-gateway-remote.sh"
fi

SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

if curl -fsSL "$REPO_BASE/$SCRIPT_NAME" -o "$SCRIPT_PATH.tmp"; then
    $SUDO mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
    $SUDO chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}✅ 脚本已下载到 $SCRIPT_PATH${NC}"
else
    rm -f "$SCRIPT_PATH.tmp"
    echo -e "${RED}❌ 下载失败，请检查网络${NC}"
    exit 1
fi

# ============== 生成配置文件 ==============
CONFIG_PATH="$INSTALL_DIR/${SCRIPT_NAME%.sh}.conf"

cat > "/tmp/gateway_monitor.conf" <<EOF
# OpenClaw Gateway 监控配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
USE_BARK=$USE_BARK_FLAG
BARK_BASE=$BARK_BASE
BARK_KEY=$BARK_KEY
BARK_GROUP=$BARK_GROUP
BARK_TITLE=$BARK_TITLE
BARK_BODY=$BARK_BODY
BARK_ICON=$BARK_ICON
CHECK_INTERVAL=5
EOF

if [[ "$SCRIPT_TYPE" == "remote" ]]; then
cat >> "/tmp/gateway_monitor.conf" <<EOF
REMOTE_HOST=$REMOTE_HOST
REMOTE_USER=$REMOTE_USER
REMOTE_PASS=$REMOTE_PASS
REMOTE_PORT=$REMOTE_PORT
SSH_TIMEOUT=$SSH_TIMEOUT
EOF
fi

$SUDO mv "/tmp/gateway_monitor.conf" "$CONFIG_PATH"
$SUDO chmod 600 "$CONFIG_PATH"

echo -e "${GREEN}✅ 配置已保存到 $CONFIG_PATH${NC}"

# ============== 创建 systemd 服务 ==============
SERVICE_NAME="monitor-gateway-${SCRIPT_TYPE}.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

cat > "/tmp/$SERVICE_NAME" <<EOF
[Unit]
Description=OpenClaw Gateway Monitor ($SCRIPT_TYPE)
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/gateway-${SCRIPT_TYPE}.log
StandardError=append:$LOG_DIR/gateway-${SCRIPT_TYPE}.log

[Install]
WantedBy=multi-user.target
EOF

$SUDO mv "/tmp/$SERVICE_NAME" "$SERVICE_PATH"
$SUDO systemctl daemon-reload
$SUDO systemctl enable "$SERVICE_NAME"
$SUDO systemctl restart "$SERVICE_NAME"

echo -e "${GREEN}✅ systemd 服务已创建并启动: $SERVICE_NAME${NC}"

# ============== 完成 ==============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 部署完成！                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "📍 脚本路径: $SCRIPT_PATH"
echo "📍 配置文件: $CONFIG_PATH"
echo "📍 日志路径: $LOG_DIR/gateway-${SCRIPT_TYPE}.log"
echo "📍 服务名称: $SERVICE_NAME"
echo ""
echo "🔧 常用命令:"
echo "  查看状态:  sudo systemctl status $SERVICE_NAME"
echo "  查看日志:  sudo journalctl -u $SERVICE_NAME -f"
echo "  重启服务:  sudo systemctl restart $SERVICE_NAME"
echo "  停止服务:  sudo systemctl stop $SERVICE_NAME"
echo "  卸载服务:  sudo systemctl disable --now $SERVICE_NAME && sudo rm $SERVICE_PATH"
