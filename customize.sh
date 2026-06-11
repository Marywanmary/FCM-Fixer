#!/system/bin/sh

# ============================================================
# FCM-Fixer 安装脚本（Magisk / KernelSU / APatch）
# 功能：音量键选择 hosts 类型，立即下载到模块目录
# ============================================================

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# 检查安装环境
if [ "$BOOTMODE" != true ]; then
  abort "❌ 请在 Magisk/KernelSU/APatch Manager 中安装，不支持 Recovery 模式"
fi

# 加载公共函数（此时 common.sh 在同目录）
. ${0%/*}/common.sh

# 确保日志目录存在
init_log_dir

# 清空或创建安装日志
echo "[$(date)] ========== FCM-Fixer 安装开始 ==========" > "$INSTALL_LOG"

# 显示欢迎信息
ui_print "==========================================="
ui_print "          FCM-Fixer 模块安装程序"
ui_print "==========================================="
ui_print "  • 清理防火墙拦截规则"
ui_print "  • 安装优选 FCM Hosts"
ui_print "  • 实时监控连接状态"
ui_print "==========================================="

# ---------- 音量键检测函数（完全参考 Box 模块）----------
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

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ 音量加(+) ]: ${choice_yes}"
    ui_print "- [ 音量减(-) ]: ${choice_no}"
    ui_print "- [ ${timeout_seconds}秒内未选择将默认选择: ${choice_yes} ]"

    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        ui_print "  => 您选择了: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        ui_print "  => 您选择了: ${choice_no}"
        return 1
    else
        ui_print "  => 超时未选择，默认选择: ${choice_yes}"
        return 0
    fi
}

# ---------- 交互选择 hosts 类型 ----------
if handle_choice "请选择要安装的 Hosts 类型：" "双栈 hosts (IPv4+IPv6，推荐)" "仅 IPv4 hosts"; then
    HOSTS_TYPE="dual"
else
    HOSTS_TYPE="ipv4"
fi

# 记录用户选择（供开机后使用，例如重新下载或日志）
echo "$HOSTS_TYPE" > "$HOSTS_CHOICE_FILE"
log_install "用户选择: $HOSTS_TYPE"

# ---------- 立即下载 hosts 到模块目录 ----------
# 注意：此时 MODPATH 是模块临时目录，安装完成后会被复制到 /data/adb/modules/fcm-fixer/
log_install "开始下载 hosts 文件..."
if install_hosts_to_module "$HOSTS_TYPE" "$MODPATH"; then
    touch "${MODPATH}/.hosts_installed"
    log_install "✅ Hosts 下载并安装成功"
else
    log_install "⚠️ Hosts 下载失败，模块仍将继续安装"
    log_install "   您可以在重启后执行以下命令手动重试："
    log_install "   su -c /data/adb/modules/fcm-fixer/action.sh --hosts"
fi

# ---------- 释放模块其他文件 ----------
ui_print "📦 正在释放模块文件..."
unzip -o "$ZIPFILE" -d "$MODPATH" >&2

# 创建模块内的 system/etc 目录（确保存在，尽管 install_hosts_to_module 已创建）
mkdir -p "${MODPATH}/system/etc"

# 设置权限
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/etc/hosts 0 0 0644 2>/dev/null

# 完成提示
ui_print " "
ui_print "==========================================="
ui_print "✅ FCM-Fixer 安装完成"
if [ -f "${MODPATH}/.hosts_installed" ]; then
    ui_print "📁 Hosts 已安装，重启后立即生效"
else
    ui_print "⚠️  Hosts 下载失败，请参阅上述提示手动重试"
fi
ui_print "📁 日志目录: /data/adb/box/run/"
ui_print "🔄 请重启手机以完成设置"
ui_print "==========================================="

# 记录安装结束
log_install "========== 安装结束 =========="
