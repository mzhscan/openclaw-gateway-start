#!/bin/bash
# ============================================================
# OpenClaw Gateway 本机监控脚本（端口检测版）
# 用途：检测本机 OpenClaw Gateway 端口（默认 15318），
#       死了就 kill openclaw 进程让 bun 自动重启 + Bark 推送
# 服务：monitor-gateway-local.service
#
# 推送文案（固定）：
#   标题: OpenClaw Gateway 已启动
#   内容: OpenClaw%20%20Gateway%20%20已启动！
# ============================================================

# 加载配置
CONF_FILE="/opt/scripts/monitor-gateway-local.conf"
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
fi

# 默认值
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"
GATEWAY_PORT="${GATEWAY_PORT:-15318}"
GATEWAY_PROCESS="openclaw"

# ===== 固定推送文案 =====
BARK_TITLE="OpenClaw Gateway 已启动"
BARK_BODY="OpenClaw%20%20Gateway%20%20已启动！"

# Bark URL 编码函数
url_encode() {
    local string="$1"
    # 用 python 做 URL 编码（bash 原生不支持中文 encode）
    python3 -c "
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
" "$string" 2>/dev/null || echo "$string"
}

# Bark URL 构建函数
build_bark_url() {
    local title="$1"
    local body="$2"
    local enc_title enc_body enc_group enc_icon
    enc_title=$(url_encode "$title")
    enc_body=$(url_encode "$body")
    local url="${BARK_BASE}/${BARK_KEY}"
    if [[ -n "$BARK_GROUP" ]]; then
        enc_group=$(url_encode "$BARK_GROUP")
        url="${url}/${enc_group}"
    fi
    url="${url}/${enc_title}/${enc_body}"
    if [[ -n "$BARK_ICON" ]]; then
        url="${url}?icon=${BARK_ICON}"
    fi
    echo "$url"
}

send_bark() {
    local title="$1"
    local body="$2"
    if [[ "$USE_BARK" != "true" ]]; then
        log "⚠️ send_bark 跳过: USE_BARK 不为 true（当前值: ${USE_BARK}）"
        return 0
    fi
    if [[ -z "$BARK_BASE" || -z "$BARK_KEY" ]]; then
        log "⚠️ send_bark 跳过: BARK 配置缺失（BASE='${BARK_BASE}' KEY='${BARK_KEY}'）"
        return 0
    fi
    local url
    url=$(build_bark_url "$title" "$body")
    log "📤 推送 Bark: $url"
    local http_code
    http_code=$(curl -s --max-time 10 -w '%{http_code}' -o /tmp/bark_response.txt "$url" 2>&1)
    log "📥 Bark 响应: HTTP ${http_code:-失败}"
    if [[ -f /tmp/bark_response.txt ]] && [[ -s /tmp/bark_response.txt ]]; then
        log "📄 Bark 响应内容: $(head -c 200 /tmp/bark_response.txt)"
    fi
    rm -f /tmp/bark_response.txt
}

# ALERT 标志位：0=正常 1=已告警（Gateway 端口没监听）
ALERT=0

mkdir -p /var/log/monitor
LOG="/var/log/monitor/gateway-local.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# 检测 Gateway 端口是否在监听
is_gateway_running() {
    # 检查指定端口是否被监听
    if ss -tln 2>/dev/null | grep -q ":${GATEWAY_PORT} "; then
        return 0
    fi
    # 也检查一下 netstat（兼容老系统）
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":${GATEWAY_PORT} "; then
            return 0
        fi
    fi
    return 1
}

# 拉起 Gateway：杀掉 openclaw 进程，让 bun server.js 自动重启它
start_gateway() {
    log "尝试拉起：杀掉 ${GATEWAY_PROCESS} 进程，让 bun 自动重启"
    # 杀掉 openclaw 子进程（PPID 通常是 bun server.js）
    pkill -f "^${GATEWAY_PROCESS}" 2>/dev/null
    # 等待并检测
    sleep 5
    if is_gateway_running; then
        log "✅ 拉起成功（端口 ${GATEWAY_PORT} 已恢复）"
        return 0
    fi
    log "❌ 拉起失败（端口 ${GATEWAY_PORT} 未恢复）"
    return 1
}

log "本机 Gateway 监控已启动（端口检测模式，端口 ${GATEWAY_PORT}）"

# 启动时检测一次
if is_gateway_running; then
    log "启动检测：Gateway 端口 ${GATEWAY_PORT} 已在监听"
    send_bark "$BARK_TITLE" "$BARK_BODY"
    log "已推送启动通知"
    ALERT=0
else
    log "启动检测：Gateway 端口 ${GATEWAY_PORT} 未监听，尝试拉起"
    if start_gateway; then
        send_bark "$BARK_TITLE" "$BARK_BODY"
        log "已推送启动通知"
        ALERT=0
    else
        ALERT=1
    fi
fi

# 主循环
while true; do
    if is_gateway_running; then
        if [[ $ALERT -eq 1 ]]; then
            # 死 → 活，推一次
            log "Gateway 已恢复（端口 ${GATEWAY_PORT} 恢复监听）"
            send_bark "$BARK_TITLE" "$BARK_BODY"
            log "已推送恢复通知"
            ALERT=0
        fi
    else
        if [[ $ALERT -eq 0 ]]; then
            log "❌ Gateway 已停止（端口 ${GATEWAY_PORT} 不再监听）"
            ALERT=1
        fi
        # 尝试拉起
        if start_gateway; then
            send_bark "$BARK_TITLE" "$BARK_BODY"
            ALERT=0
        else
            log "拉起失败，下次循环重试"
        fi
    fi
    sleep "$CHECK_INTERVAL"
done