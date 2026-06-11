#!/system/bin/sh

# ==========================================
# 日志目录：与Box共享，如未安装Box
# 则创建 /data/adb/box/run/fcm_fixer.log
# ==========================================
LOGDIR=/data/adb/box/run
mkdir -p $LOGDIR 2>/dev/null
[ ! -d $LOGDIR ] && LOGDIR=/data/local/tmp

LOGFILE="$LOGDIR/fcm_fixer.log"
OLDLOG="$LOGDIR/fcm_fixer_old.log"

if [ -f "$LOGFILE" ]; then
    mv -f "$LOGFILE" "$OLDLOG"
fi
echo "=== FCM-Fixer Service v1.0.5 启动于 $(date '+%Y-%m-%d %H:%M:%S') ===" > $LOGFILE

# 等待系统就绪
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

get_network_type() {
    local iface=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')
    if echo "$iface" | grep -qE 'wlan|wifi'; then
        echo "WiFi"
    elif echo "$iface" | grep -qE 'rmnet|ccmni|wwan|cell'; then
        echo "Cell"
    else
        echo "Other($iface)"
    fi
}

# ==========================================
# 核心清理 1：基于关键字的全量清理
# ==========================================
clean_all_google_rules() {
    for table in filter nat; do
        # IPv4
        iptables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm|android.clients.google.com' | grep -E 'REJECT|DROP' | while read -r rule; do
            del_rule=$(echo "$rule" | sed 's/-A/-D/')
            eval "iptables -t $table $del_rule" 2>/dev/null
        done
        # IPv6
        ip6tables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm' | grep -E 'REJECT|DROP' | while read -r rule; do
            del_rule=$(echo "$rule" | sed 's/-A/-D/')
            eval "ip6tables -t $table $del_rule" 2>/dev/null
        done
    done
}

# ==========================================
# 核心清理 2：基于 UID 的放行
# ==========================================
clean_uid_rules() {
    local uid=$1
    local name=$2
    [ -z "$uid" ] && return
    
    for action in REJECT DROP; do
        iptables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1 && \
            echo "[$(date '+%m-%d %H:%M:%S')] 删除了 $name 的 UID 全局 $action 拦截" >> $LOGFILE
        ip6tables -t filter -D OUTPUT -m owner --uid-owner $uid -j $action >/dev/null 2>&1
    done
}

# ==========================================
# 🌟 核心清理 3：暴力解除 FCM 专属端口的全局封锁
# ==========================================
clean_port_rules() {
    for port in 5228 5229 5230 443; do
        for action in REJECT DROP; do
            iptables -t filter -D OUTPUT -p tcp --dport $port -j $action >/dev/null 2>&1 && \
                echo "[$(date '+%m-%d %H:%M:%S')] 解除了全局 TCP $port 端口的 $action 拦截" >> $LOGFILE
            ip6tables -t filter -D OUTPUT -p tcp --dport $port -j $action >/dev/null 2>&1
        done
    done
}

# ==========================================
# Hosts 检查与强制挂载
# ==========================================
check_and_fix_hosts() {
    if grep -q "mtalk.google.com" /system/etc/hosts; then
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] Hosts 丢失，尝试从模块重新挂载..." >> $LOGFILE
        mount --bind $MODDIR/system/etc/hosts /system/etc/hosts 2>/dev/null
        if grep -q "mtalk.google.com" /system/etc/hosts; then
            echo "[$(date '+%m-%d %H:%M:%S')] 强制挂载成功" >> $LOGFILE
            return 0
        else
            return 1
        fi
    fi
}

# ==========================================
# 🌟 FCM 连通性深度测试 (废弃 Ping，改用真实的 TCP 端口探测)
# ==========================================
fcm_diag() {
    local host="mtalk.google.com"
    
    # 优先测试首选 FCM 端口 5228 (-z 扫描模式, -w 2 超时 2 秒)
    if nc -z -w 2 $host 5228 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 成功 (TCP 5228 直连)" >> $LOGFILE
        return 0
    # 如果 5228 不通，测试备用回退端口 443
    elif nc -z -w 2 $host 443 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 降级成功 (TCP 443 回退)" >> $LOGFILE
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: 失败 (TCP 5228/443 均被阻断)" >> $LOGFILE
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
    echo "[$(date '+%m-%d %H:%M:%S')] 执行完整清理流程..." >> $LOGFILE
    clean_all_google_rules
    clean_uid_rules "$GMS_UID" "GMS"
    clean_uid_rules "$VENDING_UID" "Play商店"
    clean_uid_rules "$GSF_UID" "GSF"
    clean_port_rules
    check_and_fix_hosts
    fcm_diag
}

# 初次清理
echo "[INFO] 开始初次防火墙清理，当前网络: $(get_network_type)" >> $LOGFILE
full_clean_and_verify

LAST_FINGERPRINT=$(get_network_fingerprint)
LAST_CONN_CHECK=$(date +%s)

echo "[INFO] 进入守护循环 (网络变化即时清理 + 10分钟断网修复)" >> $LOGFILE

while true; do
    # 1. 网络变化检测
    CURRENT_FP=$(get_network_fingerprint)
    if [ "$CURRENT_FP" != "$LAST_FINGERPRINT" ] && [ -n "$CURRENT_FP" ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 网络发生切换至 $(get_network_type)，等待 5 秒稳定..." >> $LOGFILE
        sleep 5
        full_clean_and_verify
        LAST_FINGERPRINT="$CURRENT_FP"
        LAST_CONN_CHECK=$(date +%s)
    fi

    # 2. 10 分钟定时健康检查 (真实 TCP 端口探测)
    NOW=$(date +%s)
    if [ $((NOW - LAST_CONN_CHECK)) -ge 600 ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 10分钟定时健康检查启动..." >> $LOGFILE
        if ! fcm_diag; then
            echo "[$(date '+%m-%d %H:%M:%S')] 检测到端口阻断，启动应急修复流程..." >> $LOGFILE
            full_clean_and_verify
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 端口连通正常，静默休眠。" >> $LOGFILE
        fi
        LAST_CONN_CHECK=$NOW
    fi

    sleep 10
done
