#!/bin/bash
# ============================================================
# OpenClaw Gateway 远程监控脚本
# 用途：部署在监控端，远程检测目标机器的 Gateway 状态
# 服务：monitor-gateway-remote.service
# ============================================================

# 加载配置
CONF_FILE="/opt/scripts/monitor-gateway-remote.conf"
if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
fi

# 默认值
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
PROCESS_NAME="openclaw.*gateway"

# Bark URL 构建函数
build_bark_url() {
    local title="$1"
    local body="$2"
    local url="${BARK_BASE}/${BARK_KEY}"
    if [[ -n "$BARK_GROUP" ]]; then
        url="${url}/${BARK_GROUP}"
    fi
    url="${url}/${title}/${body}"
    if [[ -n "$BARK_ICON" ]]; then
        url="${url}?icon=${BARK_ICON}"
    fi
    echo "$url"
}

send_bark() {
    local title="$1"
    local body="$2"
    if [[ "$USE_BARK" != "true" ]]; then
        return 0
    fi
    if [[ -z "$BARK_BASE" || -z "$BARK_KEY" ]]; then
        return 0
    fi
    local url
    url=$(build_bark_url "$title" "$body")
    curl -s "$url" >/dev/null 2>&1
}

# 状态标志：0=正常 1=已告警SSH  2=已告警gateway 死
ALERT=0

mkdir -p /var/log/monitor
LOG="/var/log/monitor/gateway-remote.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$REMOTE_HOST] $*" >> "$LOG"
}

# 检查依赖
if ! command -v sshpass >/dev/null 2>&1; then
    log "❌ sshpass 未安装，退出"
    exit 1
fi

if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_PASS" || -z "$REMOTE_PORT" ]]; then
    log "❌ 远程配置不完整，请检查 $CONF_FILE"
    exit 1
fi

log "远程 Gateway 监控已启动"

# 远程检测函数
check_remote_gateway() {
    sshpass -p "$REMOTE_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -p "$REMOTE_PORT" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "pgrep -f '$PROCESS_NAME' >/dev/null 2>&1 && echo OK || echo DEAD" 2>/dev/null
}

# 主循环
while true; do
    RESULT=$(check_remote_gateway)
    SSH_EXIT=$?

    if [[ $SSH_EXIT -ne 0 ]] || [[ -z "$RESULT" ]]; then
        # SSH 连不上
        if [[ $ALERT -ne 1 ]]; then
            log "SSH 连不上，退出码: $SSH_EXIT"
            send_bark "无法连接到 OpenClaw 所在服务器" "无法 SSH 到 ${REMOTE_HOST}:${REMOTE_PORT}"
            ALERT=1
        fi
    elif [[ "$RESULT" == *"DEAD"* ]]; then
        # SSH 连上但 gateway 死了
        if [[ $ALERT -ne 2 ]]; then
            log "Gateway 已停止"
            send_bark "OpenClaw Gateway 已停止" "${REMOTE_HOST} 上的 Gateway 已停止运行"
            ALERT=2
        fi
    elif [[ "$RESULT" == *"OK"* ]]; then
        # 正常
        if [[ $ALERT -ne 0 ]]; then
            log "Gateway 已恢复正常"
            # 恢复不推送（按需求）
        fi
        ALERT=0
    fi

    sleep "$CHECK_INTERVAL"
done