#!/system/bin/sh
MODDIR=${0%/*}

# 日志目录与 Box 共享，不存在则创建
BOX_RUN_DIR="/data/adb/box/run"
mkdir -p "$BOX_RUN_DIR"
LOGFILE="$BOX_RUN_DIR/fcm_fixer.log"
LOGFILE_OLD="$BOX_RUN_DIR/fcm_fixer_old.log"

remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"
    local cmd=""

    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *) echo "[$(date)] 错误：不支持的协议 $proto" >> "$LOGFILE"; return 1 ;;
    esac

    if ! command -v "$cmd" > /dev/null 2>&1; then return 0; fi

    local line_numbers=$( $cmd -t "$table" -nvL "$chain" --line-numbers 2> /dev/null | awk '/REJECT|DROP/ {print $1}' | sort -rn )
    if [ -z "$line_numbers" ]; then return 0; fi

    local deleted_count=0
    for line_num in $line_numbers; do
        if $cmd -t "$table" -D "$chain" "$line_num" 2> /dev/null; then
            deleted_count=$((deleted_count + 1))
        fi
    done
    echo "[$(date)] $proto: $chain 链清理了 ${deleted_count} 条阻断规则" >> "$LOGFILE"
}

wait_for_network() {
    local i=0
    while [ $i -lt 30 ]; do
        if ping -c 1 -W 1 223.5.5.5 > /dev/null 2>&1; then
            echo "[$(date)] 网络就绪，开始拉取 Hosts..." >> "$LOGFILE"
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    echo "[$(date)] 等待网络超时，将尝试直接运行。" >> "$LOGFILE"
    return 1
}

update_hosts() {
    local hosts_mode="dual"
    [ -f "$MODDIR/hosts_mode.conf" ] && hosts_mode=$(cat "$MODDIR/hosts_mode.conf")

    local primary_url=""
    local fallback_url=""

    if [ "$hosts_mode" = "ipv4" ]; then
        primary_url="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
        fallback_url="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"
    else
        primary_url="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
        fallback_url="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
    fi

    # 直接输出至模块内 systemless 挂载目录
    local dest_hosts="$MODDIR/system/etc/hosts"
    mkdir -p "$MODDIR/system/etc"
    
    local success=0
    if curl -sL --connect-timeout 5 -o "${dest_hosts}.tmp" "$primary_url"; then
        success=1
    elif curl -sL --connect-timeout 10 -o "${dest_hosts}.tmp" "$fallback_url"; then
        success=1
    elif wget -T 5 -qO "${dest_hosts}.tmp" "$primary_url"; then
        success=1
    elif wget -T 10 -qO "${dest_hosts}.tmp" "$fallback_url"; then
        success=1
    fi

    if [ $success -eq 1 ] && grep -q -i "google" "${dest_hosts}.tmp" 2>/dev/null; then
        mv -f "${dest_hosts}.tmp" "$dest_hosts"
        chmod 644 "$dest_hosts"
        echo "[$(date)] Hosts 成功更新 (模式: $hosts_mode)" >> "$LOGFILE"
        echo "===================================" >> "$LOGFILE"
        echo "--- 最新 Hosts 完整内容 ---" >> "$LOGFILE"
        cat "$dest_hosts" >> "$LOGFILE"
        echo "===================================" >> "$LOGFILE"
    else
        echo "[$(date)] Hosts 下载失败或内容不合法，保持系统默认。" >> "$LOGFILE"
        rm -f "${dest_hosts}.tmp"
    fi
}

log_fcm_info() {
    echo "===================================" >> "$LOGFILE"
    echo "[$(date)] FCM 状态与诊断截取:" >> "$LOGFILE"
    
    echo "--- GcmService 核心状态 ---" >> "$LOGFILE"
    dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -E -i "connection|endpoint|connected|status|error|network" -A 5 >> "$LOGFILE"
    
    echo "--- GmsCore Logcat 错误追踪 ---" >> "$LOGFILE"
    logcat -d -s GmsCore GCM FCM | tail -n 30 >> "$LOGFILE"
    echo "===================================" >> "$LOGFILE"
}
