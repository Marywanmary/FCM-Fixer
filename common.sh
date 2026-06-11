#!/system/bin/sh

# ============================================================
# FCM-Fixer 核心函数库
# 功能：清理防火墙、下载 hosts、EROFS 兼容、日志管理
# ============================================================

# ---------- 路径定义 ----------
SCRIPT_DIR=${0%/*}
BOX_RUN_DIR="/data/adb/box/run"

# 安装日志（记录安装过程中的动作）
INSTALL_LOG="${BOX_RUN_DIR}/fcm_fixer_install.log"

# 清理日志（每次开机记录 iptables 清理动作）
CLEAN_LOG="${BOX_RUN_DIR}/fcm_fixer_clean.log"
CLEAN_LOG_BAK="${BOX_RUN_DIR}/fcm_fixer_clean.old.log"

# FCM 监控日志
FCM_LOG="${BOX_RUN_DIR}/fcm_fixer.log"
FCM_LOG_OLD="${BOX_RUN_DIR}/fcm_fixer.old.log"
FCM_MONITOR_PID_FILE="${BOX_RUN_DIR}/fcm_monitor.pid"

# Hosts 下载地址
HOSTS_URL_DUAL="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
HOSTS_URL_IPV4="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
HOSTS_FALLBACK_DUAL="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
HOSTS_FALLBACK_IPV4="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"

# 用户选择文件（安装时写入，开机时读取）
HOSTS_CHOICE_FILE="${BOX_RUN_DIR}/hosts_choice"

# ---------- 日志初始化 ----------
init_log_dir() {
    mkdir -p "$BOX_RUN_DIR" 2>/dev/null
    chmod 755 "$BOX_RUN_DIR" 2>/dev/null
}

rotate_clean_log() {
    init_log_dir
    [ -f "$CLEAN_LOG" ] && mv -f "$CLEAN_LOG" "$CLEAN_LOG_BAK"
    echo "[$(date)] ========== 新会话开始 ==========" > "$CLEAN_LOG"
}

rotate_fcm_log() {
    init_log_dir
    [ -f "$FCM_LOG" ] && mv -f "$FCM_LOG" "$FCM_LOG_OLD"
    echo "[$(date)] 开始 FCM 监控" > "$FCM_LOG"
}

# ---------- 删除防火墙规则 ----------
remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"

    local cmd=""
    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *) echo "[$(date)] 错误：不支持的协议 $proto" >> "$CLEAN_LOG"; return 1 ;;
    esac

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[$(date)] 跳过 $proto：$cmd 命令不存在" >> "$CLEAN_LOG"
        return 0
    fi

    local line_numbers
    line_numbers=$(
        $cmd -t "$table" -nvL "$chain" --line-numbers 2>/dev/null \
            | awk '/REJECT|DROP/ {print $1}' \
            | sort -rn
    )

    [ -z "$line_numbers" ] && {
        echo "[$(date)] $proto: $chain 链中未发现 REJECT/DROP 规则" >> "$CLEAN_LOG"
        return 0
    }

    local deleted_count=0
    for line_num in $line_numbers; do
        local full_rule
        full_rule=$(
            $cmd -t "$table" -nvL "$chain" --line-numbers 2>/dev/null \
                | awk -v ln="$line_num" '
                $1 == ln {
                    sub(/^[ \t]*[0-9]+[ \t]+/, "");
                    print
                }
            '
        )
        if $cmd -t "$table" -D "$chain" "$line_num" 2>/dev/null; then
            echo "[$(date)] 已删除 ($proto) $chain 第 ${line_num} 行: ${full_rule:-REJECT/DROP规则}" >> "$CLEAN_LOG"
            deleted_count=$((deleted_count + 1))
        else
            echo "[$(date)] 删除失败 ($proto) $chain 第 ${line_num} 行" >> "$CLEAN_LOG"
        fi
    done
    echo "[$(date)] $proto: $chain 链共删除 ${deleted_count} 条 REJECT/DROP 规则" >> "$CLEAN_LOG"
}

# ---------- 下载 Hosts ----------
download_hosts() {
    local hosts_type="$1"
    local output="$2"
    local url=""
    local fallback_url=""

    case "$hosts_type" in
        dual)
            url="$HOSTS_URL_DUAL"
            fallback_url="$HOSTS_FALLBACK_DUAL"
            ;;
        ipv4)
            url="$HOSTS_URL_IPV4"
            fallback_url="$HOSTS_FALLBACK_IPV4"
            ;;
        *) return 1 ;;
    esac

    for i in 1 2; do
        if curl -s -o "$output" -L "$url" 2>/dev/null && [ -s "$output" ]; then
            return 0
        fi
        sleep 1
    done

    if [ -n "$fallback_url" ]; then
        for i in 1 2; do
            if curl -s -o "$output" -L "$fallback_url" 2>/dev/null && [ -s "$output" ]; then
                return 0
            fi
            sleep 1
        done
    fi
    return 1
}

# ---------- 安装 Hosts 到模块目录 ----------
# 参数：$1 = hosts类型 (dual/ipv4), $2 = 模块目录
install_hosts_to_module() {
    local hosts_type="$1"
    local module_dir="$2"
    local temp_file="/data/local/tmp/fcm_hosts_${hosts_type}.tmp"

    if ! download_hosts "$hosts_type" "$temp_file"; then
        return 1
    fi

    local module_hosts_dir="${module_dir}/system/etc"
    local module_hosts_file="${module_hosts_dir}/hosts"
    mkdir -p "$module_hosts_dir"
    cp -f "$temp_file" "$module_hosts_file"
    chmod 644 "$module_hosts_file"
    rm -f "$temp_file"

    # 记录 hosts 内容摘要到清理日志
    echo "[$(date)] 已安装 hosts 类型: $hosts_type" >> "$CLEAN_LOG"
    echo "--- hosts 文件前10行 ---" >> "$CLEAN_LOG"
    head -10 "$module_hosts_file" >> "$CLEAN_LOG" 2>/dev/null
    echo "---" >> "$CLEAN_LOG"
    return 0
}

# ---------- 立即生效 hosts（bind mount）----------
apply_hosts_bind_mount() {
    local module_hosts_file="${SCRIPT_DIR}/system/etc/hosts"
    if [ -f "$module_hosts_file" ]; then
        mount -o bind "$module_hosts_file" /system/etc/hosts 2>/dev/null && \
            echo "[$(date)] bind mount 生效 hosts" >> "$CLEAN_LOG" || \
            echo "[$(date)] bind mount 失败，重启后生效" >> "$CLEAN_LOG"
    fi
}

# ---------- FCM 监控后台进程 ----------
start_fcm_monitor() {
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local old_pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        kill -0 "$old_pid" 2>/dev/null && return 0
        rm -f "$FCM_MONITOR_PID_FILE"
    fi

    (
        while true; do
            {
                echo "========================================"
                echo "[$(date)] FCM 诊断快照"
                echo "--- Logcat (FCM相关) ---"
                logcat -b main -b system -d -t 30 | grep -i -E "FCM|Firebase|GCM|GooglePlayServices|gms" 2>/dev/null | head -30
                echo "--- 网络连接 (FCM端口) ---"
                netstat -an 2>/dev/null | grep -E "5228|5229|5230|5231|:443" | head -10
                echo "--- Google Play 服务版本 ---"
                dumpsys package com.google.android.gms 2>/dev/null | grep -i "version" | head -5
                echo "--- 连通性测试 ---"
                ping -c 1 -W 2 google.com 2>/dev/null | head -2
                echo "========================================"
            } >> "$FCM_LOG" 2>&1
            sleep 60
        done
    ) &
    echo $! > "$FCM_MONITOR_PID_FILE"
}
