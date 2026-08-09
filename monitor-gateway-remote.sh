#!/bin/bash
# ============================================================
# OpenClaw Gateway 远程监控脚本（端口检测版）
# 用途：SSH 到目标机器，检查 Gateway 端口是否监听
# 服务：monitor-gateway-remote.service
#
# 推送文案（固定，两种情况严格区分）：
#   情况1 - SSH 连不上:
#     标题: 无法连接到 OpenClaw 所在服务器
#     内容: 无法连接到 OpenClaw 所在服务器！
#   情况2 - SSH 连上但 Gateway 端口没监听:
#     标题: OpenClaw Gateway 已停止
#     内容: OpenClaw%20%20Gateway%20%20已停止！
# ============================================================

# 加载配置
CONF_FILE="/opt/scripts/monitor-gateway-remote.conf"
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
fi

# 默认值
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
GATEWAY_PORT="${GATEWAY_PORT:-15318}"

# ===== 固定推送文案（两种情况严格区分）=====
SSH_FAIL_TITLE="无法连接到 OpenClaw 所在服务器"
SSH_FAIL_BODY="无法连接到 OpenClaw 所在服务器！"
GW_DEAD_TITLE="OpenClaw Gateway 已停止"
GW_DEAD_BODY="OpenClaw%20%20Gateway%20%20已停止！"

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
    curl -s --max-time 5 "$url" >/dev/null 2>&1
}

# 状态标志：
#   0 = 正常（Gateway 端口在监听）
#   1 = 已告警 SSH 连不上
#   2 = 已告警 Gateway 停止（SSH 通但端口没监听）
ALERT=0
LAST_SSH_ERROR=""

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

log "远程 Gateway 监控已启动（端口检测模式，端口 ${GATEWAY_PORT}）"

# 远程检测函数
# 返回值（stdout）：
#   "OK"         = Gateway 端口在监听
#   "DEAD"       = Gateway 端口未监听（SSH 通）
#   "SSH_FAIL"   = SSH 连不上
check_remote_gateway() {
    local result
    local ssh_exit
    local sshpass_exit
    local tmp_err
    tmp_err=$(mktemp)

    # 在远程机器执行 ss 命令检测端口
    result=$(sshpass -p "$REMOTE_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -p "$REMOTE_PORT" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "ss -tln 2>/dev/null | grep -q ':${GATEWAY_PORT} ' && echo OK || echo DEAD" 2>"$tmp_err")
    ssh_exit=$?
    sshpass_exit=$?

    # 捕获错误信息
    local err_msg=""
    if [[ -s "$tmp_err" ]]; then
        err_msg=$(head -1 "$tmp_err")
    fi
    rm -f "$tmp_err"

    # SSH 完全没连上
    if [[ $sshpass_exit -ne 0 ]] || [[ $ssh_exit -ne 0 ]]; then
        if [[ -z "$result" ]]; then
            LAST_SSH_ERROR="$err_msg"
            echo "SSH_FAIL"
            return 0
        fi
        # 有 stdout 但退出码非 0（不太可能但保留处理）
    fi

    # SSH 连上了，根据 result 内容判断
    if [[ "$result" == *"OK"* ]]; then
        echo "OK"
    elif [[ "$result" == *"DEAD"* ]]; then
        echo "DEAD"
    else
        # 远程命令执行了但返回未知结果
        LAST_SSH_ERROR="远程命令返回未知结果: $result"
        echo "DEAD"
    fi
    return 0
}

log "远程 Gateway 监控已就绪"

# 主循环
while true; do
    RESULT=$(check_remote_gateway)

    case "$RESULT" in
        SSH_FAIL)
            # ===== 情况1：SSH 连不上 =====
            if [[ $ALERT -ne 1 ]]; then
                log "❌ SSH 连不上: ${LAST_SSH_ERROR}"
                send_bark "$SSH_FAIL_TITLE" "$SSH_FAIL_BODY"
                log "📤 已推送[SSH连接失败]通知"
                ALERT=1
            fi
            ;;
        DEAD)
            # ===== 情况2：SSH 通但 Gateway 端口未监听 =====
            if [[ $ALERT -ne 2 ]]; then
                log "❌ Gateway 已停止（端口 ${GATEWAY_PORT} 未监听）"
                send_bark "$GW_DEAD_TITLE" "$GW_DEAD_BODY"
                log "📤 已推送[Gateway已停止]通知"
                ALERT=2
            fi
            ;;
        OK)
            # 正常状态
            if [[ $ALERT -ne 0 ]]; then
                log "✅ Gateway 已恢复正常（端口 ${GATEWAY_PORT} 恢复监听）"
            fi
            ALERT=0
            ;;
        *)
            log "⚠️ 未知检测结果: $RESULT"
            ;;
    esac

    sleep "$CHECK_INTERVAL"
done