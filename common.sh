#!/system/bin/sh

# ============================================================
# FCM-Fixer 核心函数库
# 用途：提供清理防火墙、下载 Hosts、监控 FCM 等公共函数
# 使用：被 service.sh 和 action.sh 调用
# ============================================================

# ---------- 1. 定义全局路径 ----------
# 脚本所在目录（模块安装目录）
SCRIPT_DIR=${0%/*}

# 统一日志目录（与 Box 工具共享，便于管理）
BOX_RUN_DIR="/data/adb/box/run"

# 安装日志（仅在模块刷入时记录）
INSTALL_LOG="${BOX_RUN_DIR}/fcm_fixer_install.log"

# 清理日志（每次开机时记录防火墙清理和 hosts 检查）
CLEAN_LOG="${BOX_RUN_DIR}/fcm_fixer_clean.log"
CLEAN_LOG_BAK="${BOX_RUN_DIR}/fcm_fixer_clean.old.log"

# FCM 监控日志（后台持续记录诊断信息）
FCM_LOG="${BOX_RUN_DIR}/fcm_fixer.log"
FCM_LOG_OLD="${BOX_RUN_DIR}/fcm_fixer.old.log"
FCM_MONITOR_PID_FILE="${BOX_RUN_DIR}/fcm_monitor.pid"

# 用户选择的 Hosts 类型（安装时写入，开机时读取）
HOSTS_CHOICE_FILE="${BOX_RUN_DIR}/hosts_choice"

# Hosts 下载地址（官方 + 备用，自动切换）
HOSTS_URL_DUAL="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
HOSTS_URL_IPV4="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
HOSTS_FALLBACK_DUAL="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
HOSTS_FALLBACK_IPV4="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"

# ---------- 2. 日志初始化函数 ----------
# 确保日志目录存在
init_log_dir() {
    mkdir -p "$BOX_RUN_DIR" 2>/dev/null
    chmod 755 "$BOX_RUN_DIR" 2>/dev/null
}

# 轮转清理日志（每次开机时执行，保留旧日志为 .old）
rotate_clean_log() {
    init_log_dir
    if [ -f "$CLEAN_LOG" ]; then
        mv -f "$CLEAN_LOG" "$CLEAN_LOG_BAK"
    fi
    echo "[$(date)] ========== 新会话开始 ==========" > "$CLEAN_LOG"
}

# 轮转 FCM 监控日志（每次开机时执行）
rotate_fcm_log() {
    init_log_dir
    if [ -f "$FCM_LOG" ]; then
        mv -f "$FCM_LOG" "$FCM_LOG_OLD"
    fi
    echo "[$(date)] 开始 FCM 监控" > "$FCM_LOG"
}

# ---------- 3. 删除防火墙规则（核心功能）----------
# 参数：$1=表名（默认filter），$2=链名，$3=协议（ipv4/ipv6）
remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"

    # 根据协议选择命令
    local cmd=""
    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *)
            echo "[$(date)] 错误：不支持的协议 $proto" >> "$CLEAN_LOG"
            return 1
            ;;
    esac

    # 检查命令是否存在（某些精简系统可能没有 ip6tables）
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[$(date)] 跳过 $proto：$cmd 命令不存在" >> "$CLEAN_LOG"
        return 0
    fi

    # 获取所有包含 REJECT 或 DROP 的规则行号（降序排列）
    local line_numbers
    line_numbers=$(
        $cmd -t "$table" -nvL "$chain" --line-numbers 2>/dev/null \
            | awk '/REJECT|DROP/ {print $1}' \
            | sort -rn
    )

    # 如果没有找到规则，直接返回
    if [ -z "$line_numbers" ]; then
        echo "[$(date)] $proto: $chain 链中未发现 REJECT/DROP 规则" >> "$CLEAN_LOG"
        return 0
    fi

    # 逐条删除规则
    local deleted_count=0
    for line_num in $line_numbers; do
        # 获取规则内容（用于日志）
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

        # 执行删除
        if $cmd -t "$table" -D "$chain" "$line_num" 2>/dev/null; then
            echo "[$(date)] 已删除 ($proto) $chain 第 ${line_num} 行: ${full_rule:-REJECT/DROP规则}" >> "$CLEAN_LOG"
            deleted_count=$((deleted_count + 1))
        else
            echo "[$(date)] 删除失败 ($proto) $chain 第 ${line_num} 行" >> "$CLEAN_LOG"
        fi
    done
    echo "[$(date)] $proto: $chain 链共删除 ${deleted_count} 条 REJECT/DROP 规则" >> "$CLEAN_LOG"
}

# ---------- 4. 下载 Hosts（支持重试和备用地址）----------
# 参数：$1=类型（dual/ipv4），$2=输出文件路径
# 返回值：0=成功，1=失败
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
            echo "[$(date)] 未知的 hosts 类型: $hosts_type"
            return 1
            ;;
    esac

    # 检查 curl 命令是否存在
    if ! command -v curl >/dev/null 2>&1; then
        echo "[$(date)] curl 命令不存在，无法下载"
        return 1
    fi

    # 尝试官方地址（最多2次）
    for i in 1 2; do
        echo "[$(date)] 尝试下载 ($i/2): $url"
        if curl -s -o "$output" -L "$url" 2>/dev/null && [ -s "$output" ]; then
            echo "[$(date)] ✓ 下载成功"
            return 0
        fi
        sleep 1
    done

    # 官方失败，尝试备用地址（最多2次）
    echo "[$(date)] 官方地址失败，切换到备用地址: $fallback_url"
    for i in 1 2; do
        if curl -s -o "$output" -L "$fallback_url" 2>/dev/null && [ -s "$output" ]; then
            echo "[$(date)] ✓ 备用地址下载成功"
            return 0
        fi
        sleep 1
    done

    echo "[$(date)] ✗ 所有下载地址均失败"
    return 1
}

# ---------- 5. 安装 Hosts 到模块目录 ----------
# 参数：$1=类型（dual/ipv4），$2=模块目录（如 /data/adb/modules/fcm-fixer）
# 返回值：0=成功，1=失败
install_hosts_to_module() {
    local hosts_type="$1"
    local module_dir="$2"
    local temp_file="/data/local/tmp/fcm_hosts_${hosts_type}.tmp"

    echo "[$(date)] 开始下载 $hosts_type 类型 hosts..." >> "$CLEAN_LOG"
    if ! download_hosts "$hosts_type" "$temp_file"; then
        echo "[$(date)] 下载失败，请检查网络" >> "$CLEAN_LOG"
        return 1
    fi

    # 创建模块内的 system/etc 目录
    local module_hosts_dir="${module_dir}/system/etc"
    local module_hosts_file="${module_hosts_dir}/hosts"
    mkdir -p "$module_hosts_dir"

    # 复制 hosts 文件并设置权限
    cp -f "$temp_file" "$module_hosts_file"
    chmod 644 "$module_hosts_file"
    rm -f "$temp_file"

    echo "[$(date)] ✓ hosts 已保存到: $module_hosts_file" >> "$CLEAN_LOG"

    # 显示 hosts 文件前5行（供用户参考）
    echo "[$(date)] --- hosts 内容预览（前5行） ---" >> "$CLEAN_LOG"
    head -5 "$module_hosts_file" | while read line; do
        echo "[$(date)]   $line" >> "$CLEAN_LOG"
    done
    echo "[$(date)] ---" >> "$CLEAN_LOG"

    return 0
}

# ---------- 6. 立即生效 hosts（通过 bind mount）----------
# 作用：覆盖系统 /system/etc/hosts，无需重启（兼容 EROFS）
apply_hosts_bind_mount() {
    local module_hosts_file="${SCRIPT_DIR}/system/etc/hosts"
    if [ -f "$module_hosts_file" ]; then
        if mount -o bind "$module_hosts_file" /system/etc/hosts 2>/dev/null; then
            echo "[$(date)] ✓ bind mount 成功，hosts 已生效" >> "$CLEAN_LOG"
        else
            echo "[$(date)] ⚠ bind mount 失败（可能权限不足），重启后生效" >> "$CLEAN_LOG"
        fi
    else
        echo "[$(date)] hosts 文件不存在，无法 bind mount" >> "$CLEAN_LOG"
    fi
}

# ---------- 7. 音量键检测（用于首次开机选择）----------
# 返回值：0=超时/无操作（默认双栈），1=音量+（双栈），2=音量-（IPv4）
wait_for_volume_key() {
    local timeout=10
    local end=$(( $(date +%s) + timeout ))
    local keypress=""
    local VOLUME_UP=115
    local VOLUME_DOWN=114

    # 检查 getevent 命令
    if ! command -v getevent >/dev/null 2>&1; then
        echo "[$(date)] getevent 命令不存在，跳过音量检测，默认双栈" >> "$CLEAN_LOG"
        return 0
    fi

    # 获取输入设备列表
    local devices=$(ls /dev/input/event* 2>/dev/null)
    if [ -z "$devices" ]; then
        echo "[$(date)] 未找到输入设备，跳过音量检测，默认双栈" >> "$CLEAN_LOG"
        return 0
    fi

    echo "[$(date)] 等待音量键选择（10秒内）:" >> "$CLEAN_LOG"
    echo "[$(date)]   • 按【音量+】→ 双栈 hosts（推荐）" >> "$CLEAN_LOG"
    echo "[$(date)]   • 按【音量-】→ 仅 IPv4 hosts" >> "$CLEAN_LOG"
    echo "[$(date)]   • 无操作 → 默认双栈" >> "$CLEAN_LOG"

    while [ $(date +%s) -lt $end ]; do
        for dev in $devices; do
            # 读取一个按键事件，超时0.3秒
            keypress=$(timeout 0.3 getevent -c 1 -q "$dev" 2>/dev/null | awk '{print $3}')
            if [ -n "$keypress" ]; then
                keypress=$((keypress))
                if [ $keypress -eq $VOLUME_UP ]; then
                    echo "[$(date)] ✓ 检测到音量+，选择双栈 hosts" >> "$CLEAN_LOG"
                    return 1
                elif [ $keypress -eq $VOLUME_DOWN ]; then
                    echo "[$(date)] ✓ 检测到音量-，选择 IPv4 hosts" >> "$CLEAN_LOG"
                    return 2
                fi
            fi
        done
        sleep 0.3
    done
    echo "[$(date)] ⏱ 超时未操作，默认双栈 hosts" >> "$CLEAN_LOG"
    return 0
}

# ---------- 8. FCM 监控后台进程 ----------
# 功能：每60秒记录一次 logcat、网络连接、dumpsys 等信息
start_fcm_monitor() {
    # 防止重复启动
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local old_pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "[$(date)] FCM 监控已在运行，PID: $old_pid" >> "$CLEAN_LOG"
            return 0
        else
            rm -f "$FCM_MONITOR_PID_FILE"
        fi
    fi

    echo "[$(date)] 启动 FCM 监控后台进程..." >> "$CLEAN_LOG"

    # 后台无限循环
    (
        while true; do
            {
                echo "========================================"
                echo "[$(date)] FCM 诊断快照"
                echo "--- 1. Logcat (FCM/GCM/Push 相关) ---"
                if command -v logcat >/dev/null 2>&1; then
                    logcat -b main -b system -d -t 30 | grep -i -E "FCM|Firebase|GCM|GooglePlayServices|c2dm|regist|push|gms" 2>/dev/null | head -30
                else
                    echo "logcat 命令不可用"
                fi

                echo "--- 2. 网络连接 (FCM 端口 5228-5231, 443) ---"
                netstat -an 2>/dev/null | grep -E "5228|5229|5230|5231|:443" | grep -i "ESTABLISHED\|LISTEN" | head -15

                echo "--- 3. Google Play 服务版本 ---"
                if command -v dumpsys >/dev/null 2>&1; then
                    dumpsys package com.google.android.gms 2>/dev/null | grep -i -E "versionName|versionCode" | head -3
                    echo "--- 4. 网络连接诊断 ---"
                    dumpsys connectivity 2>/dev/null | grep -i "google" | head -10
                else
                    echo "dumpsys 命令不可用"
                fi

                echo "--- 5. 连通性测试 ---"
                ping -c 1 -W 2 google.com 2>/dev/null | head -2

                echo "========================================"
                echo ""
            } >> "$FCM_LOG" 2>&1

            sleep 60
        done
    ) &
    local pid=$!
    echo "$pid" > "$FCM_MONITOR_PID_FILE"
    echo "[$(date)] FCM 监控已启动，PID: $pid" >> "$CLEAN_LOG"
}

# ---------- 9. 停止 FCM 监控（可选）----------
stop_fcm_monitor() {
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        kill "$pid" 2>/dev/null
        rm -f "$FCM_MONITOR_PID_FILE"
        echo "[$(date)] 已停止 FCM 监控" >> "$CLEAN_LOG"
    fi
}
