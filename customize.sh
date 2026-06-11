#!/system/bin/sh

# 设置环境变量
SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# 检查安装环境
if [ "$BOOTMODE" != true ]; then
  abort "❌ 请在 Magisk/KernelSU/APatch Manager 中安装"
fi

# 创建日志目录
mkdir -p /data/adb/box/run
LOG_FILE="/data/adb/box/run/fcm_fixer_install.log"
echo "[$(date)] ========== 安装开始 ==========" > "$LOG_FILE"

# 加载公共函数（此时模块文件尚未解压，需要先解压 common.sh 和 module.prop 等）
# 由于 SKIPUNZIP=1，我们需要手动解压必要文件
unzip -o "$ZIPFILE" -d "$MODPATH" >&2

# 加载 common.sh
if [ -f "$MODPATH/common.sh" ]; then
    . $MODPATH/common.sh
else
    echo "[$(date)] 错误：无法找到 common.sh" >> "$LOG_FILE"
    abort "模块文件不完整"
fi

# ---------- 音量键检测（参考 Box 实现）----------
KEY_LISTENER_PID=""
KEY_FIFO=""

start_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ] && kill -0 "$KEY_LISTENER_PID" 2>/dev/null; then
        return
    fi
    KEY_FIFO=$(mktemp -u -p /dev/tmp)
    mkfifo "$KEY_FIFO" || exit 1
    getevent -ql > "$KEY_FIFO" &
    KEY_LISTENER_PID=$!
}

stop_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ]; then
        kill "$KEY_LISTENER_PID" >/dev/null 2>&1
        KEY_LISTENER_PID=""
    fi
    if [ -n "$KEY_FIFO" ]; then
        rm -f "$KEY_FIFO"
        KEY_FIFO=""
    fi
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
            if kill -0 "$detection_pid" 2>/dev/null; then
                kill "$detection_pid" 2>/dev/null
                echo "2" > "$detection_result_file"
            fi
        ) &
        local timeout_pid=$!
        
        wait "$detection_pid" 2>/dev/null
        kill "$timeout_pid" 2>/dev/null
        wait "$timeout_pid" 2>/dev/null
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

# ---------- 交互选择 ----------
ui_print "==========================================="
ui_print "          FCM-Fixer 模块安装程序"
ui_print "==========================================="

if handle_choice "请选择要安装的 Hosts 类型：" "双栈 hosts (IPv4+IPv6，推荐)" "仅 IPv4 hosts"; then
    HOSTS_TYPE="dual"
else
    HOSTS_TYPE="ipv4"
fi

echo "$HOSTS_TYPE" > /data/adb/box/run/hosts_choice
ui_print "✅ 已选择: $HOSTS_TYPE"

# ---------- 尝试下载 hosts ----------
ui_print "📥 正在下载 hosts 文件..."
if install_hosts_to_module "$HOSTS_TYPE" "$MODPATH"; then
    touch "$MODPATH/.hosts_installed"
    ui_print "✅ Hosts 下载成功"
else
    ui_print "⚠️ Hosts 下载失败（网络问题或curl不可用）"
    ui_print "   您可以在开机后执行以下命令手动重试："
    ui_print "   su -c /data/adb/modules/fcm-fixer/action.sh --hosts"
fi

# ---------- 设置权限 ----------
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/etc/hosts 0 0 0644 2>/dev/null

ui_print "✅ 安装完成，请重启手机"
ui_print "📁 日志位置: /data/adb/box/run/"

# 确保安装成功退出
exit 0
