#!/bin/bash
# ============================================================
# OpenClaw Gateway 远程监控脚本
# 用途：部署在监控端，远程检测目标机器的 Gateway 状态
# 服务：monitor-gateway-remote.service
# 区分：
#   - SSH 连不上 → 推"无法连接到 OpenClaw 所在服务器"
#   - SSH 连上但 gateway 死了 → 推"对方 Gateway 已停止"
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
#   0 = 正常（Gateway 跑着）
#   1 = 已告警 SSH 连不上
#   2 = 已告警 Gateway 停止（SSH 通但进程死）
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
# 返回值（通过 stdout）：
#   "OK"         = Gateway 在跑
#   "DEAD"       = Gateway 死了
#   "SSH_FAIL"   = SSH 连不上（含密码错、连不上、认证失败）
check_remote_gateway() {
    local result
    local ssh_exit
    local sshpass_exit

    # 先捕获 stdout 和 stderr
    local tmp_err
    tmp_err=$(mktemp)
    trap 'rm -f "$tmp_err"' RETURN

    result=$(sshpass -p "$REMOTE_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o BatchMode=no \
        -p "$REMOTE_PORT" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "ps -eo cmd --no-headers 2>/dev/null | grep -E 'openclaw.*gateway|gateway.*openclaw' | grep -v grep | head -1" 2>"$tmp_err")
    ssh_exit=$?
    sshpass_exit=$?

    # 详细诊断：捕获 stderr
    local err_msg=""
    if [[ -s "$tmp_err" ]]; then
        err_msg=$(head -1 "$tmp_err")
    fi

    # SSH 完全没连上（sshpass 退出码非 0 或 ssh 退出码非 0 且无 stdout）
    # sshpass 退出码：1=参数错，3=密码错，4=主机错，5=密钥问题，6=ssh 没找到
    # ssh 退出码：255=网络问题
    if [[ $sshpass_exit -ne 0 ]] || [[ $ssh_exit -ne 0 ]]; then
        # 没拿到任何 stdout，肯定是连接问题
        if [[ -z "$result" ]]; then
            echo "SSH_FAIL"
            # 把错误信息也返回（用全局变量）
            LAST_SSH_ERROR="$err_msg"
            return 1
        fi
        # 有 stdout 但 ssh_exit 非 0，可能是远程命令执行失败（比如 grep 没匹到）
        # 这种情况下要继续判断 result 是否为空
    fi

    # SSH 连上了，根据 result 内容判断
    if [[ -z "$result" ]]; then
        echo "DEAD"
        return 0
    else
        echo "OK"
        return 0
    fi
}

# 初始化全局变量
LAST_SSH_ERROR=""

log "远程 Gateway 监控已就绪"

# 主循环
while true; do
    RESULT=$(check_remote_gateway)
    CHECK_EXIT=$?

    if [[ "$RESULT" == "SSH_FAIL" ]]; then
        # SSH 连不上
        if [[ $ALERT -ne 1 ]]; then
            log "SSH 连不上: $LAST_SSH_ERROR"
            send_bark "无法连接到 OpenClaw 所在服务器" "无法 SSH 到 ${REMOTE_HOST}:${REMOTE_PORT}"
            log "已推送'SSH连接失败'通知"
            ALERT=1
        fi
    elif [[ "$RESULT" == "DEAD" ]]; then
        # SSH 连上但 gateway 死了
        if [[ $ALERT -ne 2 ]]; then
            log "Gateway 已停止（SSH 通但进程死）"
            send_bark "OpenClaw Gateway 已停止" "${REMOTE_HOST} 上的 Gateway 已停止运行"
            log "已推送'Gateway已停止'通知"
            ALERT=2
        fi
    elif [[ "$RESULT" == "OK" ]]; then
        # 正常
        if [[ $ALERT -ne 0 ]]; then
            log "Gateway 已恢复正常（恢复不推送）"
        fi
        ALERT=0
    else
        # 未知状态
        log "⚠️ 未知检测结果: $RESULT"
    fi

    sleep "$CHECK_INTERVAL"
done