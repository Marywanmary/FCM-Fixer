#!/system/bin/sh

# ============================================================
# FCM-Fixer 安装脚本（调试版）
# 每一步都有 ui_print 输出，确保能看到交互和下载过程
# ============================================================

# 强制设置这些变量（Magisk/KernelSU 标准）
SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# 创建日志文件，记录所有输出
mkdir -p /data/adb/box/run
LOG_FILE="/data/adb/box/run/fcm_fixer_install.log"
echo "[$(date)] ========== 安装开始 ==========" > "$LOG_FILE"
# 将后续所有输出同时写入日志和屏幕（但 ui_print 已经会显示到屏幕，我们重定向标准输出到日志）
exec >> "$LOG_FILE" 2>&1

# 定义一个函数，同时输出到 ui_print 和日志
log_and_ui() {
    echo "$1"
    ui_print "$1"
}

# 检查环境
log_and_ui "==========================================="
log_and_ui "          FCM-Fixer 安装程序"
log_and_ui "==========================================="
log_and_ui "• 清理防火墙拦截规则"
log_and_ui "• 安装优选 FCM Hosts"
log_and_ui "• 实时监控连接状态"
log_and_ui "==========================================="

# 解压模块文件（必须）
log_and_ui "- 解压模块文件"
unzip -o "$ZIPFILE" -d "$MODPATH" >&2
if [ $? -ne 0 ]; then
    log_and_ui "❌ 解压失败！"
    abort "解压模块文件出错"
fi
log_and_ui "✓ 解压完成"

# ---------- 定义下载函数 ----------
download_hosts() {
    local type="$1"
    local output="$2"
    local url=""
    local fallback=""
    case "$type" in
        dual)
            url="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
            fallback="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
            ;;
        ipv4)
            url="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
            fallback="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"
            ;;
        *) return 1 ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        log_and_ui "⚠️ curl 命令不存在，无法下载"
        return 1
    fi

    for i in 1 2; do
        log_and_ui "  尝试下载 ($i/2): $url"
        if curl -s -o "$output" -L "$url" 2>/dev/null && [ -s "$output" ]; then
            log_and_ui "  ✓ 下载成功"
            return 0
        fi
        sleep 1
    done

    log_and_ui "  官方地址失败，切换到备用地址"
    for i in 1 2; do
        log_and_ui "  备用尝试 ($i/2): $fallback"
        if curl -s -o "$output" -L "$fallback" 2>/dev/null && [ -s "$output" ]; then
            log_and_ui "  ✓ 备用地址下载成功"
            return 0
        fi
        sleep 1
    done
    log_and_ui "  ✗ 下载失败"
    return 1
}

# ---------- 音量键检测（参考 Box 实现）----------
KEY_LISTENER_PID=""
KEY_FIFO=""

start_key_listener() {
    [ -n "$KEY_LISTENER_PID" ] && kill -0 "$KEY_LISTENER_PID" 2>/dev/null && return
    KEY_FIFO=$(mktemp -u -p /dev/tmp)
    mkfifo "$KEY_FIFO" || exit 1
    getevent -ql > "$KEY_FIFO" &
    KEY_LISTENER_PID=$!
}

stop_key_listener() {
    [ -n "$KEY_LISTENER_PID" ] && kill "$KEY_LISTENER_PID" 2>/dev/null
    [ -n "$KEY_FIFO" ] && rm -f "$KEY_FIFO"
    KEY_LISTENER_PID=""
    KEY_FIFO=""
}

volume_key_detection() {
    local timeout_seconds="${1:-0}"
    local detection_result_file=$(mktemp -u -p /dev/tmp)
    (
        while read -r line; do
            if echo "$line" | grep -Eiq "(KEY_)?VOLUME ?UP|KEYCODE_VOLUME_UP" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "0" > "$detection_result_file"
                exit 0
            elif echo "$line" | grep -Eiq "(KEY_)?VOLUME ?DOWN|KEYCODE_VOLUME_DOWN" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "1" > "$detection_result_file"
                exit 0
            fi
        done < "$KEY_FIFO"
    ) &
    local detection_pid=$!
    
    if [ "$timeout_seconds" -gt 0 ]; then
        (
            sleep "$timeout_seconds"
            kill -0 "$detection_pid" 2>/dev/null && kill "$detection_pid" 2>/dev/null && echo "2" > "$detection_result_file"
        ) &
        local timeout_pid=$!
        wait "$detection_pid" 2>/dev/null
        kill "$timeout_pid" 2>/dev/null
    else
        wait "$detection_pid" 2>/dev/null
    fi
    
    if [ -f "$detection_result_file" ]; then
        local result=$(cat "$detection_result_file")
        rm -f "$detection_result_file"
        return "$result"
    fi
    rm -f "$detection_result_file"
    return 2
}

handle_choice() {
    local question="$1"
    local choice_yes="${2:-是}"
    local choice_no="${3:-否}"
    local timeout_seconds="${4:-10}"

    log_and_ui " "
    log_and_ui "-----------------------------------------------------------"
    log_and_ui "- ${question}"
    log_and_ui "- [ 音量加(+) ]: ${choice_yes}"
    log_and_ui "- [ 音量减(-) ]: ${choice_no}"
    log_and_ui "- [ ${timeout_seconds}秒内未选择将默认选择: ${choice_yes} ]"

    # 预热 getevent（确保设备可用）
    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        log_and_ui "  => 您选择了: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        log_and_ui "  => 您选择了: ${choice_no}"
        return 1
    else
        log_and_ui "  => 超时未选择，默认选择: ${choice_yes}"
        return 0
    fi
}

# ---------- 选择 hosts 类型 ----------
log_and_ui "开始交互选择..."
if handle_choice "请选择要安装的 Hosts 类型：" "双栈 hosts (IPv4+IPv6，推荐)" "仅 IPv4 hosts"; then
    HOSTS_TYPE="dual"
else
    HOSTS_TYPE="ipv4"
fi
log_and_ui "✅ 已选择: $HOSTS_TYPE"
echo "$HOSTS_TYPE" > /data/adb/box/run/hosts_choice

# ---------- 下载 hosts 到模块目录 ----------
log_and_ui "📥 正在下载 hosts 文件..."
TEMP_HOSTS="/data/local/tmp/fcm_hosts_${HOSTS_TYPE}.tmp"
if download_hosts "$HOSTS_TYPE" "$TEMP_HOSTS"; then
    mkdir -p "$MODPATH/system/etc"
    cp -f "$TEMP_HOSTS" "$MODPATH/system/etc/hosts"
    chmod 644 "$MODPATH/system/etc/hosts"
    rm -f "$TEMP_HOSTS"
    touch "$MODPATH/.hosts_installed"
    log_and_ui "✅ Hosts 安装成功"
    # 显示前5行预览
    log_and_ui "--- hosts 内容预览（前5行） ---"
    head -5 "$MODPATH/system/etc/hosts" | while read line; do
        log_and_ui "  $line"
    done
else
    log_and_ui "⚠️  Hosts 下载失败（网络问题或 curl 不可用）"
    log_and_ui "   您可以在开机后执行以下命令手动重试："
    log_and_ui "   su -c /data/adb/modules/fcm-fixer/action.sh --hosts"
fi

# ---------- 设置权限 ----------
log_and_ui "- 设置权限"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/etc/hosts 0 0 0644 2>/dev/null

# ---------- 完成 ----------
log_and_ui "==========================================="
log_and_ui "✅ FCM-Fixer 安装完成"
log_and_ui "📁 日志目录: /data/adb/box/run/"
log_and_ui "🔄 请重启手机以生效"
log_and_ui "==========================================="

# 确保以成功状态退出
exit 0
