#!/system/bin/sh

# 获取当前模块绝对路径，防止开机自启时找不到目录
MODDIR=${0%/*}

# 动态获取版本号
VERSION=$(grep '^version=' $MODDIR/module.prop 2>/dev/null | cut -d'=' -f2)
[ -z "$VERSION" ] && VERSION="未知版本"

# 日志目录：与Box共享，如未安装Box
# 则创建 /data/adb/box/run 存放 fcm_fixer.log
LOGDIR=/data/adb/box/run
mkdir -p $LOGDIR 2>/dev/null
[ ! -d $LOGDIR ] && LOGDIR=/data/local/tmp

LOGFILE="$LOGDIR/fcm_fixer.log"
OLDLOG="$LOGDIR/fcm_fixer_old.log"

if [ -f "$LOGFILE" ]; then
    mv -f "$LOGFILE" "$OLDLOG"
fi
echo "=== FCM-Fixer Service $VERSION 启动于 $(date '+%Y-%m-%d %H:%M:%S') ===" > $LOGFILE

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
echo "[INFO] 系统启动完成，等待 60 秒让网络和防火墙就绪..." >> $LOGFILE
sleep 60

# ==========================================
# UID 获取
# ==========================================
get_uid() {
    cat /data/system/packages.list 2>/dev/null | grep "^$1 " | awk '{print $2}'
}

GMS_UID=""
while [ -z "$GMS_UID" ]; do
    GMS_UID=$(get_uid "com.google.android.gms")
    [ -z "$GMS_UID" ] && sleep 5
done

VENDING_UID=$(get_uid "com.android.vending")
GSF_UID=$(get_uid "com.google.android.gsf")

echo "[INFO] 目标 UID: GMS=$GMS_UID, Play=$VENDING_UID, GSF=$GSF_UID" >> $LOGFILE

# ==========================================
# 获取当前网络类型描述 (修复了 grep -oP 不兼容的问题)
# ==========================================
get_network_type() {
    local iface=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p')
    if echo "$iface" | grep -qE 'wlan|wifi'; then
        echo "WiFi"
    elif echo "$iface" | grep -qE 'rmnet|ccmni|wwan|cell'; then
        echo "Cell"
    elif [ -n "$iface" ]; then
        echo "Other($iface)"
    else
        echo "Disconnected"
    fi
}

clean_all_google_rules() {
    for table in filter nat; do
        iptables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm|android.clients.google.com' | grep -E 'REJECT|DROP' | while read -r rule; do
            eval "iptables -t $table $(echo "$rule" | sed 's/-A/-D/')" 2>/dev/null
        done
        ip6tables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm' | grep -E 'REJECT|DROP' | while read -r rule; do
            eval "ip6tables -t $table $(echo "$rule" | sed 's/-A/-D/')" 2>/dev/null
        done
    done
}

clean_uid_rules() {
    local uid=$1
    local name=$2
    [ -z "$uid" ] && return
    for action in REJECT DROP; do
        iptables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1 && \
            echo "[$(date '+%m-%d %H:%M:%S')] 删除 $name IPv4 $action" >> $LOGFILE
        ip6tables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1 && \
            echo "[$(date '+%m-%d %H:%M:%S')] 删除 $name IPv6 $action" >> $LOGFILE
    done
}

# ==========================================
# Hosts 检查与强制挂载 (修复丢失 MODDIR 的问题)
# ==========================================
check_and_fix_hosts() {
    if grep -q "mtalk.google.com" /system/etc/hosts; then
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] Hosts 丢失，尝试从 $MODDIR 重新挂载..." >> $LOGFILE
        mount --bind $MODDIR/system/etc/hosts /system/etc/hosts 2>/dev/null
        if grep -q "mtalk.google.com" /system/etc/hosts; then
            echo "[$(date '+%m-%d %H:%M:%S')] 强制挂载成功" >> $LOGFILE
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 强制挂载失败，底层挂载点可能被锁" >> $LOGFILE
        fi
    fi
}

# ==========================================
# 🌟 核心：FCM 内部状态诊断抓取 (GCM Service Dump)
# ==========================================
dump_fcm_diagnostics() {
    echo "[$(date '+%m-%d %H:%M:%S')] >>> 获取 GMS 内部 FCM 诊断日志 >>>" >> $LOGFILE
    # 调取 Android 核心 GCM 服务状态，截取连接状态和错误码
    dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -A 15 -iE 'GCM status|Current connection|Last connection|Message metrics|Heartbeat' >> $LOGFILE
    echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<" >> $LOGFILE
}

fcm_diag() {
    if nc -z -w 2 mtalk.google.com 5228 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 成功 (TCP 5228 直连)" >> $LOGFILE
        # 端口通了顺便抓取内部诊断，看 GMS 是不是在装死
        dump_fcm_diagnostics
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 失败 (TCP 5228 被阻断)" >> $LOGFILE
        return 1
    fi
}

get_network_fingerprint() {
    local gw=$(ip route get 1.1.1.1 2>/dev/null | head -1 | awk '{print $3}')
    local dns1=$(getprop net.dns1)
    local dns2=$(getprop net.dns2)
    echo "${gw}_${dns1}_${dns2}"
}

full_clean_and_verify() {
    echo "[$(date '+%m-%d %H:%M:%S')] 执行完整清理与诊断..." >> $LOGFILE
    clean_all_google_rules
    clean_uid_rules "$GMS_UID" "GMS"
    clean_uid_rules "$VENDING_UID" "Play商店"
    clean_uid_rules "$GSF_UID" "GSF"
    check_and_fix_hosts
    fcm_diag
}

echo "[INFO] 开始初次防火墙清理，当前网络: $(get_network_type)" >> $LOGFILE
full_clean_and_verify

LAST_FINGERPRINT=$(get_network_fingerprint)
LAST_CONN_CHECK=$(date +%s)

echo "[INFO] 进入守护循环 (网络变化清理 + 10分钟探测)" >> $LOGFILE

while true; do
    CURRENT_FP=$(get_network_fingerprint)
    if [ "$CURRENT_FP" != "$LAST_FINGERPRINT" ] && [ -n "$CURRENT_FP" ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 切换至 $(get_network_type)，等待 5 秒稳定..." >> $LOGFILE
        sleep 5
        full_clean_and_verify
        LAST_FINGERPRINT="$CURRENT_FP"
        LAST_CONN_CHECK=$(date +%s)
    fi

    NOW=$(date +%s)
    if [ $((NOW - LAST_CONN_CHECK)) -ge 600 ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 10分钟定时健康检查 (网络: $(get_network_type))" >> $LOGFILE
        if ! fcm_diag; then
            full_clean_and_verify
        fi
        LAST_CONN_CHECK=$NOW
    fi

    sleep 10
done
