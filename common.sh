#!/system/bin/sh

# ============================================================
# FCM-Fixer 核心函数库
# 功能：清理防火墙规则、下载 hosts、EROFS 兼容、日志管理
# 适用：Magisk / KernelSU / APatch
# ============================================================

# ---------- 路径定义 ----------
SCRIPT_DIR=${0%/*}
LOGFILE="${SCRIPT_DIR}/reject_rules.log"
BAKLOG="${SCRIPT_DIR}/reject_rules.log.bak"

# Box 共享日志目录
BOX_RUN_DIR="/data/adb/box/run"
FCM_LOG_FILE="${BOX_RUN_DIR}/fcm_fixer.log"
FCM_LOG_OLD="${BOX_RUN_DIR}/fcm_fixer.old.log"
FCM_MONITOR_PID_FILE="${BOX_RUN_DIR}/fcm_monitor.pid"

# Hosts 相关变量（方便维护）
# 官方地址
HOSTS_URL_DUAL="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
HOSTS_URL_IPV4="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
# 备用地址（使用 GitHub 加速代理）
HOSTS_FALLBACK_DUAL="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
HOSTS_FALLBACK_IPV4="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"

# ---------- 日志轮转 ----------
# 功能：每次开机时备份旧的 FCM 日志，创建新日志文件
# 注：Box 共享目录 /data/adb/box/run 若不存在则自动创建
rotate_fcm_log() {
    # 如果已有日志文件，先备份为 .old
    if [ -f "$FCM_LOG_FILE" ]; then
        mv -f "$FCM_LOG_FILE" "$FCM_LOG_OLD"
        echo "[$(date)] FCM 日志已轮转: $FCM_LOG_OLD" >> "$LOGFILE"
    fi
    # 确保目录存在且可写（兼容未安装 Box 的情况）
    mkdir -p "$BOX_RUN_DIR"
    chmod 755 "$BOX_RUN_DIR"
    touch "$FCM_LOG_FILE"
    chmod 644 "$FCM_LOG_FILE"
    echo "[$(date)] 新 FCM 日志已创建: $FCM_LOG_FILE" >> "$LOGFILE"
}

# ---------- 删除防火墙规则（核心功能）----------
# 参数说明：
#   $1 = 表名（通常为 filter）
#   $2 = 链名（如 fw_OUTPUT）
#   $3 = 协议类型（ipv4 或 ipv6）
remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"

    # 根据协议选择对应的 iptables 命令
    local cmd=""
    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *) echo "[$(date)] 错误：不支持的协议 $proto" >> "$LOGFILE"; return 1 ;;
    esac

    # 检查命令是否存在（某些精简系统可能没有 ip6tables）
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "[$(date)] 跳过 $proto：$cmd 命令不存在" >> "$LOGFILE"
        return 0
    fi

    # 获取该链中所有包含 REJECT 或 DROP 的规则行号，按降序排列
    # 降序排列是为了从后往前删除，避免删除后行号变化导致出错
    local line_numbers
    line_numbers=$(
        $cmd -t "$table" -nvL "$chain" --line-numbers 2>/dev/null \
            | awk '/REJECT|DROP/ {print $1}' \
            | sort -rn
    )

    if [ -z "$line_numbers" ]; then
        echo "[$(date)] $proto: $chain 链中未发现 REJECT/DROP 规则" >> "$LOGFILE"
        return 0
    fi

    # 逐条删除规则并记录日志
    local deleted_count=0
    for line_num in $line_numbers; do
        # 获取要删除的规则内容（用于日志记录）
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
        if $cmd -t "$table" -D "$chain" "$line_num" 2> /dev/null; then
            echo "[$(date)] 已删除 ($proto) $chain 第 ${line_num} 行: ${full_rule:-REJECT/DROP规则}" >> "$LOGFILE"
            deleted_count=$((deleted_count + 1))
        else
            echo "[$(date)] 删除失败 ($proto) $chain 第 ${line_num} 行" >> "$LOGFILE"
        fi
    done
    echo "[$(date)] $proto: $chain 链共删除 ${deleted_count} 条 REJECT/DROP 规则" >> "$LOGFILE"
}

# ---------- EROFS 检测 ----------
# 功能：检查 /system 分区是否为只读的 EROFS 格式
# 返回值：0 = 不是 EROFS（可常规操作），1 = 是 EROFS（需特殊处理）
# 检测方法：查看 mount 输出中 /system 对应的文件系统类型是否为 "erofs"
is_erofs_system() {
    # 从 /proc/mounts 或 mount 命令中查找 /system 分区的文件系统类型
    local fs_type=$(mount | grep " /system " | awk '{print $5}')
    if [ "$fs_type" = "erofs" ]; then
        echo "[$(date)] 检测到 /system 分区为 EROFS 只读格式" >> "$LOGFILE"
        return 0
    else
        echo "[$(date)] /system 分区文件系统: $fs_type (非 EROFS)" >> "$LOGFILE"
        return 1
    fi
}

# ---------- 检测命令是否存在 ----------
# 参数：$1 = 命令名
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# ---------- 下载 Hosts（支持重试和备用地址）----------
# 参数：$1 = 类型（dual 或 ipv4），$2 = 输出路径
download_hosts() {
    local hosts_type="$1"
    local output="$2"
    local url=""
    local fallback_url=""

    # 根据类型选择对应的下载地址
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
            echo "[$(date)] 未知 hosts 类型: $hosts_type" >> "$LOGFILE"
            return 1
            ;;
    esac

    # 重试配置：最多尝试 2 次
    local retry=2
    local success=0

    # 尝试官方地址
    for i in $(seq 1 $retry); do
        if curl -s -o "$output" -L "$url" 2>/dev/null; then
            if [ -s "$output" ]; then
                echo "[$(date)] ✓ 成功下载 hosts ($hosts_type): $url" >> "$LOGFILE"
                success=1
                break
            fi
        fi
        echo "[$(date)] 官方地址下载失败 ($i/$retry): $url" >> "$LOGFILE"
        sleep 1
    done

    # 如果官方地址失败，尝试备用地址
    if [ $success -eq 0 ]; then
        echo "[$(date)] 切换到备用地址..." >> "$LOGFILE"
        for i in $(seq 1 $retry); do
            if curl -s -o "$output" -L "$fallback_url" 2>/dev/null && [ -s "$output" ]; then
                echo "[$(date)] ✓ 备用地址下载成功: $fallback_url" >> "$LOGFILE"
                success=1
                break
            fi
            sleep 1
        done
    fi

    if [ $success -eq 1 ]; then
        return 0
    else
        echo "[$(date)] ✗ 所有地址下载失败，跳过 hosts 安装" >> "$LOGFILE"
        return 1
    fi
}

# ---------- 显示 Hosts 内容（前10行和后10行）----------
# 参数：$1 = hosts 文件路径
show_hosts_content() {
    local hosts_file="$1"
    if [ ! -f "$hosts_file" ]; then
        echo "[$(date)] hosts 文件不存在，无法显示内容" >> "$LOGFILE"
        return 1
    fi

    local line_count=$(wc -l < "$hosts_file")
    echo "[$(date)] ========================================" >> "$LOGFILE"
    echo "[$(date)] 已安装的 Hosts 文件内容概览（共 $line_count 行）" >> "$LOGFILE"
    echo "[$(date)] ---------- 头部 10 行 ----------" >> "$LOGFILE"
    head -10 "$hosts_file" | while IFS= read -r line; do
        echo "[$(date)] $line" >> "$LOGFILE"
    done
    echo "[$(date)] ---------- 尾部 10 行 ----------" >> "$LOGFILE"
    tail -10 "$hosts_file" | while IFS= read -r line; do
        echo "[$(date)] $line" >> "$LOGFILE"
    done
    echo "[$(date)] ========================================" >> "$LOGFILE"
}

# ---------- 安装 Hosts（兼容 EROFS）----------
# 功能：将下载的 hosts 写入模块目录，并通过 bind mount 生效
# 参数：$1 = 类型（dual 或 ipv4）
install_hosts() {
    local hosts_type="$1"
    local temp_file="/data/local/tmp/fcm_hosts_${hosts_type}.tmp"

    # 1. 下载 hosts 文件
    if ! download_hosts "$hosts_type" "$temp_file"; then
        return 1
    fi

    # 2. 确保模块目录存在
    local module_hosts_dir="${SCRIPT_DIR}/system/etc"
    local module_hosts_file="${module_hosts_dir}/hosts"
    mkdir -p "$module_hosts_dir"

    # 3. 复制下载的 hosts 到模块目录
    cp -f "$temp_file" "$module_hosts_file"
    chmod 644 "$module_hosts_file"
    rm -f "$temp_file"

    echo "[$(date)] hosts 已写入模块目录: $module_hosts_file" >> "$LOGFILE"

    # 4. 显示 hosts 内容到日志
    show_hosts_content "$module_hosts_file"

    # 5. 通过 bind mount 立即生效（兼容 EROFS 的关键）
    #    bind mount 不要求目标分区可写，它只是在内存中创建一个挂载覆盖点
    #    这是 Magisk / KernelSU 推荐的做法，完全兼容 EROFS 只读分区
    if mount -o bind "$module_hosts_file" /system/etc/hosts 2>/dev/null; then
        echo "[$(date)] ✓ 已通过 bind mount 立即生效 hosts" >> "$LOGFILE"
    else
        echo "[$(date)] ⚠ bind mount 失败（可能权限不足），重启后模块会自动生效" >> "$LOGFILE"
        # 尝试替代方案：使用 mount --bind 的不同写法
        if mount --bind "$module_hosts_file" /system/etc/hosts 2>/dev/null; then
            echo "[$(date)] ✓ 使用 --bind 方式挂载成功" >> "$LOGFILE"
        else
            echo "[$(date)] ✗ 挂载失败，请检查 root 权限" >> "$LOGFILE"
        fi
    fi

    return 0
}

# ---------- 音量键检测（10秒超时）----------
# 返回值：
#   0 = 超时/无操作，默认双栈
#   1 = 音量+，选择双栈
#   2 = 音量-，选择 IPv4
wait_for_volume_key() {
    local timeout=10
    local end=$(( $(date +%s) + timeout ))
    local keypress=""
    local VOLUME_UP=115
    local VOLUME_DOWN=114

    # 列出所有输入设备
    local devices=$(ls /dev/input/event* 2>/dev/null)
    if [ -z "$devices" ]; then
        echo "[$(date)] 警告：未找到输入设备，跳过音量键检测" >> "$LOGFILE"
        return 0
    fi

    echo "[$(date)] 等待音量键选择（10秒内）:" >> "$LOGFILE"
    echo "[$(date)]   • 按【音量+】→ 安装双栈 hosts（IPv4+IPv6，推荐）" >> "$LOGFILE"
    echo "[$(date)]   • 按【音量-】→ 安装仅 IPv4 hosts" >> "$LOGFILE"
    echo "[$(date)]   • 无操作 10 秒后 → 自动安装双栈 hosts" >> "$LOGFILE"

    while [ $(date +%s) -lt $end ]; do
        for dev in $devices; do
            # 使用 getevent 读取按键事件，超时 0.3 秒
            keypress=$(timeout 0.3 getevent -c 1 -q "$dev" 2>/dev/null | awk '{print $3}')
            if [ -n "$keypress" ]; then
                # 转换为十进制
                keypress=$((keypress))
                if [ $keypress -eq $VOLUME_UP ]; then
                    echo "[$(date)] ✓ 检测到【音量+】，选择双栈 hosts" >> "$LOGFILE"
                    return 1
                elif [ $keypress -eq $VOLUME_DOWN ]; then
                    echo "[$(date)] ✓ 检测到【音量-】，选择 IPv4 hosts" >> "$LOGFILE"
                    return 2
                fi
            fi
        done
        sleep 0.3
    done
    echo "[$(date)] ⏱ 超时未操作，默认选择双栈 hosts" >> "$LOGFILE"
    return 0
}

# ---------- FCM 诊断监控（后台进程）----------
# 功能：持续收集 FCM 相关日志、网络状态、诊断信息
start_fcm_monitor() {
    # 避免重复启动
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local old_pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "[$(date)] FCM 监控已在运行，PID: $old_pid" >> "$LOGFILE"
            return 0
        else
            rm -f "$FCM_MONITOR_PID_FILE"
        fi
    fi

    echo "[$(date)] 启动 FCM 监控后台进程..." >> "$LOGFILE"

    (
        while true; do
            {
                echo "========================================"
                echo "[$(date)] FCM 诊断快照"
                echo "========================================"

                # 1. FCM 相关 logcat（最近 30 秒）
                echo "--- Logcat (FCM/GCM/Push 相关) ---"
                if command_exists logcat; then
                    logcat -b main -b system -d -t 30 | grep -i -E "FCM|Firebase|GCM|GooglePlayServices|c2dm|regist|push|gms" 2>/dev/null | head -50
                else
                    echo "logcat 命令不可用"
                fi

                # 2. 网络连接状态（FCM 常用端口）
                echo "--- 网络连接 (FCM 端口 5228-5231, 443) ---"
                netstat -an 2>/dev/null | grep -E "5228|5229|5230|5231|:443" | grep -i "ESTABLISHED\|LISTEN" | head -20

                # 3. dumpsys 诊断信息
                echo "--- Google Play 服务版本信息 ---"
                if command_exists dumpsys; then
                    dumpsys package com.google.android.gms 2>/dev/null | grep -i -E "versionName|versionCode|gms|fcm" | head -10
                    echo "--- 网络连接诊断 ---"
                    dumpsys connectivity 2>/dev/null | grep -i "google" | head -15
                else
                    echo "dumpsys 命令不可用"
                fi

                # 4. 连通性测试
                echo "--- 连通性测试 (ping google.com) ---"
                ping -c 1 -W 3 google.com 2>/dev/null | head -5

                echo "========================================"
                echo ""
            } >> "$FCM_LOG_FILE" 2>&1

            # 每 60 秒记录一次
            sleep 60
        done
    ) &
    local pid=$!
    echo "$pid" > "$FCM_MONITOR_PID_FILE"
    echo "[$(date)] FCM 监控已启动，PID: $pid" >> "$LOGFILE"
}

# ---------- 停止 FCM 监控 ----------
stop_fcm_monitor() {
    if [ -f "$FCM_MONITOR_PID_FILE" ]; then
        local pid=$(cat "$FCM_MONITOR_PID_FILE" 2>/dev/null)
        kill "$pid" 2>/dev/null
        rm -f "$FCM_MONITOR_PID_FILE"
        echo "[$(date)] 已停止 FCM 监控" >> "$LOGFILE"
    fi
}
