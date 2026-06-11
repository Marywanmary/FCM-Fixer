#!/system/bin/sh

# ============================================================
# FCM-Fixer 核心函数库
# 功能：清理防火墙规则、下载 hosts、EROFS 兼容、日志管理
# 适用：Magisk / KernelSU / APatch
# ============================================================

# ---------- 路径定义 ----------
SCRIPT_DIR=${0%/*}

# 统一日志目录（与 Box 共享）
BOX_RUN_DIR="/data/adb/box/run"

# 安装日志（仅在模块安装时写入）
INSTALL_LOG="${BOX_RUN_DIR}/fcm_fixer_install.log"

# 防火墙清理日志
CLEAN_LOG="${BOX_RUN_DIR}/fcm_fixer_clean.log"
CLEAN_LOG_BAK="${BOX_RUN_DIR}/fcm_fixer_clean.old.log"

# FCM 监控日志
FCM_LOG="${BOX_RUN_DIR}/fcm_fixer.log"
FCM_LOG_OLD="${BOX_RUN_DIR}/fcm_fixer.old.log"
FCM_MONITOR_PID_FILE="${BOX_RUN_DIR}/fcm_monitor.pid"

# Hosts 相关变量（方便维护）
HOSTS_URL_DUAL="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
HOSTS_URL_IPV4="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
HOSTS_FALLBACK_DUAL="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
HOSTS_FALLBACK_IPV4="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"

# ---------- 日志初始化函数 ----------
# 作用：确保日志目录存在，并轮转旧日志（由调用者决定何时调用）
init_log_dir() {
    mkdir -p "$BOX_RUN_DIR" 2>/dev/null
    chmod 755 "$BOX_RUN_DIR" 2>/dev/null
}

# 轮转清理日志（每次开机执行）
rotate_clean_log() {
    init_log_dir
    if [ -f "$CLEAN_LOG" ]; then
        mv -f "$CLEAN_LOG" "$CLEAN_LOG_BAK"
        echo "[$(date)] 清理日志已轮转" >> "$CLEAN_LOG"
    else
        touch "$CLEAN_LOG"
    fi
    echo "[$(date)] ========== 新会话开始 ==========" >> "$CLEAN_LOG"
}

# 轮转 FCM 监控日志（每次开机执行）
rotate_fcm_log() {
    init_log_dir
    if [ -f "$FCM_LOG" ]; then
        mv -f "$FCM_LOG" "$FCM_LOG_OLD"
        echo "[$(date)] FCM 日志已轮转" >> "$FCM_LOG"
    else
        touch "$FCM_LOG"
    fi
    echo "[$(date)] 开始 FCM 监控" >> "$FCM_LOG"
}

# ---------- 删除防火墙规则 ----------
# 参数：$1=表名(默认filter), $2=链名, $3=协议(ipv4/ipv6)
remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"

    local cmd=""
    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *) 
            echo "[$(date)] 错误：不支持的协议 $proto" >> "$CLEAN_LOG"
            return 1
            ;;
    esac

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[$(date)] 跳过 $proto：$cmd 命令不存在" >> "$CLEAN_LOG"
        return 0
    fi

    # 获取包含 REJECT 或 DROP 的规则行号（降序）
    local line_numbers
    line_numbers=$(
        $cmd -t "$table" -nvL "$chain" --line-numbers 2>/dev/null \
            | awk '/REJECT|DROP/ {print $1}' \
            | sort -rn
    )

    if [ -z "$line_numbers" ]; then
        echo "[$(date)] $proto: $chain 链中未发现 REJECT/DROP 规则" >> "$CLEAN_LOG"
        return 0
    fi

    local deleted_count=0
    for line_num in $line_numbers; do
        # 获取规则内容用于日志
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

# ---------- EROFS 检测 ----------
is_erofs_system() {
    local fs_type=$(mount | grep " /system " | awk '{print $5}')
    if [ "$fs_type" = "erofs" ]; then
        echo "[$(date)] 检测到 /system 分区为 EROFS 只读格式" >> "$CLEAN_LOG"
        return 0
    else
        echo "[$(date)] /system 分区文件系统: $fs_type (非 EROFS)" >> "$CLEAN_LOG"
        return 1
    fi
}

# ---------- 下载 Hosts ----------
# 参数：$1 = 类型(dual/ipv4)，$2 = 输出文件路径
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
        *)
            echo "[$(date)] 未知 hosts 类型: $hosts_type"
            return 1
            ;;
    esac

    local retry=2
    local success=0

    for i in $(seq 1 $retry); do
        if curl -s -o "$output" -L "$url" 2>/dev/null; then
            if [ -s "$output" ]; then
                echo "[$(date)] ✓ 成功下载 hosts ($hosts_type): $url"
                success=1
                break
            fi
        fi
        echo "[$(date)] 官方地址下载失败 ($i/$retry): $url"
        sleep 1
    done

    if [ $success -eq 0 ] && [ -n "$fallback_url" ]; then
        echo "[$(date)] 切换到备用地址..."
        for i in $(seq 1 $retry); do
            if curl -s -o "$output" -L "$fallback_url" 2>/dev/null && [ -s "$output" ]; then
                echo "[$(date)] ✓ 备用地址下载成功: $fallback_url"
                success=1
                break
            fi
            sleep 1
        done
    fi

    if [ $success -eq 1 ]; then
        return 0
    else
        echo "[$(date)] ✗ 所有地址下载失败"
        return 1
    fi
}

# ---------- 显示 Hosts 内容摘要 ----------
show_hosts_content() {
    local hosts_file="$1"
    if [ ! -f "$hosts_file" ]; then
        echo "[$(date)] hosts 文件不存在，无法显示内容"
        return 1
    fi

    local line_count=$(wc -l < "$hosts_file")
    echo "[$(date)] ========================================"
    echo "[$(date)] 已安装的 Hosts 文件内容概览（共 $line_count 行）"
    echo "[$(date)] ---------- 头部 10 行 ----------"
    head -10 "$hosts_file" | while IFS= read -r line; do
        echo "[$(date)] $line"
    done
    echo "[$(date)] ---------- 尾部 10 行 ----------"
    tail -10 "$hosts_file" | while IFS= read -r line; do
        echo "[$(date)] $line"
    done
    echo "[$(date)] ========================================"
}

# ---------- 安装 Hosts 到模块目录（兼容 EROFS）----------
# 参数：$1 = 类型(dual/ipv4)，$2 = 模块目录（即 ${0%/*}）
install_hosts_to_module() {
    local hosts_type="$1"
    local module_dir="$2"
    local temp_file="/data/local/tmp/fcm_hosts_${hosts_type}.tmp"

    # 下载
    if ! download_hosts "$hosts_type" "$temp_file"; then
        return 1
    fi

    # 模块内的 system/etc 目录
    local module_hosts_dir="${module_dir}/system/etc"
    local module_hosts_file="${module_hosts_dir}/hosts"
    mkdir -p "$module_hosts_dir"

    # 复制并设权限
    cp -f "$temp_file" "$module_hosts_file"
    chmod 644 "$module_hosts_file"
    rm -f "$temp_file"

    # 显示内容
    show_hosts_content "$module_hosts_file"

    # 注意：安装时无需 bind mount，因为模块会在下次重启时由管理器自动挂载
    # 但在 service.sh 中可以立即 bind mount 生效（可选）
    return 0
}

# ---------- 音量键检测（用于安装时，超时 10 秒）----------
# 返回值：
#   0 = 超时/无操作，默认双栈
#   1 = 音量+，双栈
#   2 = 音量-，IPv4
wait_for_volume_key() {
    local timeout=10
    local end=$(( $(date +%s) + timeout ))
    local keypress=""
    local VOLUME_UP=115
    local VOLUME_DOWN=114

    local devices=$(ls /dev/input/event* 2>/dev/null)
    if [ -z "$devices" ]; then
        echo "[$(date)] 警告：未找到输入设备，跳过音量键检测"
        return 0
    fi

    echo "[$(date)] 等待音量键选择（10秒内）:"
    echo "[$(date)]   • 按【音量+】→ 安装双栈 hosts（IPv4+IPv6，推荐）"
    echo "[$(date)]   • 按【音量-】→ 安装仅 IPv4 hosts"
    echo "[$(date)]   • 无操作 10 秒后 → 自动安装双栈 hosts"

    while [ $(date +%s) -lt $end ]; do
        for dev in $devices; do
            keypress=$(timeout 0.3 getevent -c 1 -q "$dev" 2>/dev/null | awk '{print $3}')
            if [ -n "$keypress" ]; then
                keypress=$((keypress))
                if [ $keypress -eq $VOLUME_UP ]; then
                    echo "[$(date)] ✓ 检测到【音量+】，选择双栈 hosts"
                    return 1
                elif [ $keypress -eq $VOLUME_DOWN ]; then
                    echo "[$(date)] ✓ 检测到【音量-】，选择 IPv4 hosts"
                    return 2
                fi
            fi
        done
        sleep 0.3
    done
    echo "[$(date)] ⏱ 超时未操作，默认选择双栈 hosts"
    return 0
}

# ---------- FCM 监控后台进程 ----------
start_fcm_monitor() {
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local old_pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "[$(date)] FCM 监控已在运行，PID: $old_pid" >> "$FCM_LOG"
            return 0
        else
            rm -f "$FCM_MONITOR_PID_FILE"
        fi
    fi

    echo "[$(date)] 启动 FCM 监控后台进程..." >> "$FCM_LOG"

    (
        while true; do
            {
                echo "========================================"
                echo "[$(date)] FCM 诊断快照"
                echo "========================================"
                echo "--- Logcat (FCM/GCM/Push 相关) ---"
                if command -v logcat >/dev/null 2>&1; then
                    logcat -b main -b system -d -t 30 | grep -i -E "FCM|Firebase|GCM|GooglePlayServices|c2dm|regist|push|gms" 2>/dev/null | head -50
                else
                    echo "logcat 命令不可用"
                fi
                echo "--- 网络连接 (FCM 端口 5228-5231, 443) ---"
                netstat -an 2>/dev/null | grep -E "5228|5229|5230|5231|:443" | grep -i "ESTABLISHED\|LISTEN" | head -20
                echo "--- Google Play 服务版本信息 ---"
                if command -v dumpsys >/dev/null 2>&1; then
                    dumpsys package com.google.android.gms 2>/dev/null | grep -i -E "versionName|versionCode|gms|fcm" | head -10
                    echo "--- 网络连接诊断 ---"
                    dumpsys connectivity 2>/dev/null | grep -i "google" | head -15
                else
                    echo "dumpsys 命令不可用"
                fi
                echo "--- 连通性测试 (ping google.com) ---"
                ping -c 1 -W 3 google.com 2>/dev/null | head -5
                echo "========================================"
                echo ""
            } >> "$FCM_LOG" 2>&1
            sleep 60
        done
    ) &
    local pid=$!
    echo "$pid" > "$FCM_MONITOR_PID_FILE"
    echo "[$(date)] FCM 监控已启动，PID: $pid" >> "$FCM_LOG"
}

stop_fcm_monitor() {
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        kill "$pid" 2>/dev/null
        rm -f "$FCM_MONITOR_PID_FILE"
        echo "[$(date)] 已停止 FCM 监控" >> "$FCM_LOG"
    fi
}
