#!/system/bin/sh

# ============================================================
# FCM-Fixer 安装脚本（Magisk / KernelSU / APatch）
# 所有逻辑内置，避免因 common.sh 缺失导致失败
# ============================================================

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# 检查安装环境
if [ "$BOOTMODE" != true ]; then
  abort "❌ 请在 Magisk/KernelSU/APatch Manager 中安装"
fi

# 创建日志目录并记录
mkdir -p /data/adb/box/run
LOG_FILE="/data/adb/box/run/fcm_fixer_install.log"
echo "[$(date)] ========== 安装开始 ==========" > "$LOG_FILE"
exec >> "$LOG_FILE" 2>&1

# 解压模块文件
ui_print "- 解压模块文件"
unzip -o "$ZIPFILE" -d "$MODPATH" >&2

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
        echo "curl 命令不存在，无法下载"
        return 1
    fi

    for i in 1 2; do
        if curl -s -o "$output" -L "$url" 2>/dev/null && [ -s "$output" ]; then
            echo "下载成功: $url"
            return 0
        fi
        sleep 1
    done

    for i in 1 2; do
        if curl -s -o "$output" -L "$fallback" 2>/dev/null && [ -s "$output" ]; then
            echo "备用地址下载成功: $fallback"
            return 0
        fi
        sleep 1
    done
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

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ 音量加(+) ]: ${choice_yes}"
    ui_print "- [ 音量减(-) ]: ${choice_no}"
    ui_print "- [ ${timeout_seconds}秒内未选择将默认选择: ${choice_yes} ]"

    # 预热 getevent
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

# ---------- 主安装流程 ----------
ui_print "==========================================="
ui_print "          FCM-Fixer 模块安装程序"
ui_print "==========================================="
ui_print "  • 清理防火墙拦截规则"
ui_print "  • 安装优选 FCM Hosts"
ui_print "  • 实时监控连接状态"
ui_print "==========================================="

# 选择 hosts 类型
if handle_choice "请选择要安装的 Hosts 类型：" "双栈 hosts (IPv4+IPv6，推荐)" "仅 IPv4 hosts"; then
    HOSTS_TYPE="dual"
else
    HOSTS_TYPE="ipv4"
fi

echo "$HOSTS_TYPE" > /data/adb/box/run/hosts_choice
ui_print "✅ 已选择: $HOSTS_TYPE"

# 下载 hosts 到模块目录
ui_print "📥 正在下载 hosts 文件..."
TEMP_HOSTS="/data/local/tmp/fcm_hosts_${HOSTS_TYPE}.tmp"
if download_hosts "$HOSTS_TYPE" "$TEMP_HOSTS"; then
    # 创建模块内 system/etc 目录
    mkdir -p "$MODPATH/system/etc"
    cp -f "$TEMP_HOSTS" "$MODPATH/system/etc/hosts"
    chmod 644 "$MODPATH/system/etc/hosts"
    rm -f "$TEMP_HOSTS"
    touch "$MODPATH/.hosts_installed"
    ui_print "✅ Hosts 下载成功"
    # 显示前5行预览
    ui_print "--- hosts 内容预览（前5行） ---"
    head -5 "$MODPATH/system/etc/hosts" | while read line; do
        ui_print "  $line"
    done
else
    ui_print "⚠️  Hosts 下载失败（网络问题或 curl 不可用）"
    ui_print "   您可以在开机后执行以下命令手动重试："
    ui_print "   su -c /data/adb/modules/fcm-fixer/action.sh --hosts"
fi

# 设置权限
ui_print "- 设置权限"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/etc/hosts 0 0 0644 2>/dev/null

# 完成
ui_print "==========================================="
ui_print "✅ FCM-Fixer 安装完成"
ui_print "📁 日志目录: /data/adb/box/run/"
ui_print "🔄 请重启手机以生效"
ui_print "==========================================="

# 确保安装成功退出
exit 0
