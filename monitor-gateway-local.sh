#!/bin/bash
# ============================================================
# OpenClaw Gateway 本机监控脚本
# 用途：监控本机 OpenClaw Gateway，死了自动拉起 + Bark 推送
# 服务：monitor-gateway-local.service
# ============================================================

# 加载配置
CONF_FILE="/opt/scripts/monitor-gateway-local.conf"
if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
fi

# 默认值
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"
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

# ALERT 标志位：0=正常 1=已告警
ALERT=0

mkdir -p /var/log/monitor
LOG="/var/log/monitor/gateway-local.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 本机 Gateway 监控已启动" >> "$LOG"

# 启动时检测一次
if pgrep -f "$PROCESS_NAME" >/dev/null 2>&1; then
    log "启动检测：Gateway 已在运行"
    send_bark "${BARK_TITLE}" "${BARK_BODY}"
    log "已推送启动通知"
    ALERT=0
else
    log "启动检测：Gateway 未运行，尝试拉起"
    if command -v openclaw >/dev/null 2>&1; then
        openclaw gateway start >/dev/null 2>&1
        sleep 3
        if pgrep -f "$PROCESS_NAME" >/dev/null 2>&1; then
            log "启动检测：Gateway 已成功拉起"
            send_bark "${BARK_TITLE}" "${BARK_BODY}"
            log "已推送启动通知"
            ALERT=0
        else
            log "启动检测：拉起失败，等待下次循环"
            ALERT=1
        fi
    else
        log "启动检测：未找到 openclaw 命令，跳过拉起"
        ALERT=1
    fi
fi

# 主循环
while true; do
    if pgrep -f "$PROCESS_NAME" >/dev/null 2>&1; then
        if [[ $ALERT -eq 1 ]]; then
            # 死 → 活，推一次
            log "Gateway 已恢复"
            send_bark "${BARK_TITLE}" "${BARK_BODY}"
            log "已推送恢复通知"
            ALERT=0
        fi
    else
        if [[ $ALERT -eq 0 ]]; then
            log "Gateway 已停止，尝试拉起"
            ALERT=1
        fi
        # 尝试拉起
        if command -v openclaw >/dev/null 2>&1; then
            openclaw gateway start >/dev/null 2>&1
            sleep 3
            if pgrep -f "$PROCESS_NAME" >/dev/null 2>&1; then
                log "Gateway 拉起成功"
                send_bark "${BARK_TITLE}" "${BARK_BODY}"
                ALERT=0
            fi
        fi
    fi
    sleep "$CHECK_INTERVAL"
done