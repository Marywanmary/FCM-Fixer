SKIPUNZIP=0

ui_print "- 正在安装 FCM Fixer & Hosts Optimizer"
ui_print "- 作者: ssll"
ui_print "- 已适配 KernelSU / APatch / Magisk"

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
    
    # 后台抓取输入事件
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

# 提前创建挂载所需的底层目录，解决system只读问题
mkdir -p "$MODPATH/system/etc"
ui_print "- 配置保存完毕，模块生效后将自动更新规则和诊断日志。"
