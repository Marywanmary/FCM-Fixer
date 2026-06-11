#!/system/bin/sh

# ============================================================
# FCM-Fixer 核心函数库
# ============================================================

SCRIPT_DIR=${0%/*}
BOX_RUN_DIR="/data/adb/box/run"

# 安装日志（仅安装时写入）
INSTALL_LOG="${BOX_RUN_DIR}/fcm_fixer_install.log"

# 清理日志（开机清理防火墙时写入）
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

# 安装日志记录（同时输出到 ui_print 和日志文件）
log_install() {
    local msg="$1"
    echo "[$(date)] $msg" >> "$INSTALL_LOG"
    ui_print "$msg"
}

# 清理日志轮转
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
    # ... 与之前相同，略 ...
    # 注意：此函数使用 CLEAN_LOG 记录
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

    log_install "正在下载 $hosts_type hosts..."
    if ! download_hosts "$hosts_type" "$temp_file"; then
        log_install "❌ 下载失败，请检查网络"
        return 1
    fi

    local module_hosts_dir="${module_dir}/system/etc"
    local module_hosts_file="${module_hosts_dir}/hosts"
    mkdir -p "$module_hosts_dir"
    cp -f "$temp_file" "$module_hosts_file"
    chmod 644 "$module_hosts_file"
    rm -f "$temp_file"

    log_install "✅ hosts 已保存到模块目录: $module_hosts_file"
    # 显示前5行预览
    log_install "--- hosts 内容预览（前5行） ---"
    head -5 "$module_hosts_file" | while read line; do
        log_install "  $line"
    done
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
    # ... 与之前相同，略 ...
}
