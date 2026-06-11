#!/system/bin/sh

MODDIR=${0%/*}
VERSION=$(grep '^version=' $MODDIR/module.prop 2>/dev/null | cut -d'=' -f2)
[ -z "$VERSION" ] && VERSION="未知版本"

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
echo "[INFO] 系统启动完成，等待 30 秒让网络和防火墙就绪..." >> $LOGFILE
sleep 30

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

# ==========================================
# 严格还原：仅清理指定 UID 的 filter 表规则
# ==========================================
clean_uid_rules() {
    local uid=$1
    local name=$2
    [ -z "$uid" ] && return
    
    for action in REJECT DROP; do
        iptables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1 && \
            echo "[$(date '+%m-%d %H:%M:%S')] 放行: 移除 $name IPv4 $action" >> $LOGFILE
        ip6tables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1 && \
            echo "[$(date '+%m-%d %H:%M:%S')] 放行: 移除 $name IPv6 $action" >> $LOGFILE
    done
}

check_and_fix_hosts() {
    echo "[$(date '+%m-%d %H:%M:%S')] 执行 Hosts 挂载检查..." >> $LOGFILE
    if ! grep -q "mtalk.google.com" /system/etc/hosts; then
        mount --bind $MODDIR/system/etc/hosts /system/etc/hosts 2>/dev/null
    fi
    
    # 将实际生效的 Hosts 内容打印到日志供用户核对
    echo "--- ⬇️ 当前生效的 Hosts 规则 ⬇️ ---" >> $LOGFILE
    cat /system/etc/hosts | grep -v "^#" | grep -v "^$" >> $LOGFILE
    echo "-------------------------------------" >> $LOGFILE
}

dump_fcm_diagnostics() {
    echo "[$(date '+%m-%d %H:%M:%S')] >>> GMS 内部 FCM 诊断日志 (前30行) >>>" >> $LOGFILE
    # 去掉所有 grep 过滤，直接抓取前30行原生输出，确保不漏信息
    dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | head -n 30 >> $LOGFILE
    echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<" >> $LOGFILE
}

fcm_diag() {
    if nc -z -w 2 mtalk.google.com 5228 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 成功 (TCP 5228 直连)" >> $LOGFILE
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 失败 (TCP 5228 不可达)" >> $LOGFILE
        dump_fcm_diagnostics
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
    echo "[$(date '+%m-%d %H:%M:%S')] 执行清理流程..." >> $LOGFILE
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
        echo "[$(date '+%m-%d %H:%M:%S')] 切换至 $(get_network_type)，等待 5 秒..." >> $LOGFILE
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
