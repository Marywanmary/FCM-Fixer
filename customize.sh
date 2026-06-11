SKIPUNZIP=0

ui_print "- 正在安装 FCM Fixer & Hosts Optimizer"
ui_print "- 版本: v1.0.4 | 作者: ssll"

ui_print " "
ui_print "======================================="
ui_print "- 请选择要优先使用的 FCM Hosts 类型："
ui_print "  [音量 +] : 安装 双栈 (IPv4/v6) (推荐)"
ui_print "  [音量 -] : 安装 仅 IPv4"
ui_print "- (无操作 10s 后默认选择双栈)"
ui_print "======================================="

capture_key() {
    local start=$(date +%s)
    local max_wait=10
    
    getevent -ql 2>/dev/null > /dev/.key_events &
    local pid=$!
    
    local result="timeout"
    while [ $(( $(date +%s) - start )) -lt $max_wait ]; do
        if grep -E -q "KEY_VOLUMEUP|VOLUMEUP" /dev/.key_events 2>/dev/null; then
            result="dual"
            break
        elif grep -E -q "KEY_VOLUMEDOWN|VOLUMEDOWN" /dev/.key_events 2>/dev/null; then
            result="ipv4"
            break
        fi
        sleep 0.2
    done
    
    kill -9 $pid 2>/dev/null
    rm -f /dev/.key_events 2>/dev/null
    echo "$result"
}

mode=$(capture_key)
if [ "$mode" = "ipv4" ]; then
    ui_print "-> 已选择：仅 IPv4"
    echo "ipv4" > "$MODPATH/hosts_mode.conf"
elif [ "$mode" = "dual" ]; then
    ui_print "-> 已选择：双栈 (IPv4/v6)"
    echo "dual" > "$MODPATH/hosts_mode.conf"
else
    ui_print "-> 等待超时，默认选择：双栈 (IPv4/v6)"
    echo "dual" > "$MODPATH/hosts_mode.conf"
fi

mkdir -p "$MODPATH/system/etc"
dest_hosts="$MODPATH/system/etc/hosts"

ui_print "- 正在尝试预下载最新 Hosts..."
if [ "$mode" = "ipv4" ]; then
    url="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
    fallback="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"
else
    url="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
    fallback="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
fi

if curl -sL --connect-timeout 5 -o "${dest_hosts}.tmp" "$url" || curl -sL --connect-timeout 8 -o "${dest_hosts}.tmp" "$fallback"; then
    if grep -q -i "google" "${dest_hosts}.tmp" 2>/dev/null; then
        mv -f "${dest_hosts}.tmp" "$dest_hosts"
        chmod 644 "$dest_hosts"
        ui_print "- ✅ Hosts 下载并配置成功！"
    else
        rm -f "${dest_hosts}.tmp"
        ui_print "- ⚠️ Hosts 内容异常，将在开机后重试下载。"
    fi
else
    ui_print "- ⚠️ 网络超时，将在开机后由后台服务自动下载。"
fi

ui_print "- 安装完成，请重启设备！"
