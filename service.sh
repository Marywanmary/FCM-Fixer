#!/system/bin/sh

# ==========================================
# 日志目录：优先 /data/adb/box/run，否则创建
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

# ==========================================
# 等待系统就绪 + 额外延迟确保防火墙规则完全加载
# ==========================================
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
# 工具函数：获取当前网络类型描述
# ==========================================
get_network_type() {
    # 获取默认接口名
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
# 核心清理：全量 Google 相关 REJECT/DROP 规则
# ==========================================
clean_all_google_rules() {
    local count=0
    for table in filter nat; do
        # IPv4
        iptables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm|android.clients.google.com' | grep -E 'REJECT|DROP' | while read -r rule; do
            del_rule=$(echo "$rule" | sed 's/-A/-D/')
            eval "iptables -t $table $del_rule" 2>/dev/null && count=$((count+1))
        done
        
        # IPv6
        ip6tables -t $table -S OUTPUT 2>/dev/null | grep -iE 'google|gstatic|mtalk|firebase|fcm' | grep -E 'REJECT|DROP' | while read -r rule; do
            del_rule=$(echo "$rule" | sed 's/-A/-D/')
            eval "ip6tables -t $table $del_rule" 2>/dev/null && count=$((count+1))
        done
    done
    # 由于管道子shell，计数无法直接传出，改用文件记录
    # 这里简单输出即可，我们不要求精确计数，只记录有删除行为
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
# Hosts 检查与强制挂载
# ==========================================
check_and_fix_hosts() {
    if grep -q "mtalk.google.com" /system/etc/hosts; then
        echo "[$(date '+%m-%d %H:%M:%S')] Hosts 已生效" >> $LOGFILE
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] Hosts 丢失，尝试从模块挂载..." >> $LOGFILE
        mount --bind $MODDIR/system/etc/hosts /system/etc/hosts 2>/dev/null
        if grep -q "mtalk.google.com" /system/etc/hosts; then
            echo "[$(date '+%m-%d %H:%M:%S')] 强制挂载成功" >> $LOGFILE
            return 0
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 强制挂载失败，请检查模块状态！" >> $LOGFILE
            return 1
        fi
    fi
}

# ==========================================
# FCM 连通性深度测试 + 诊断信息
# ==========================================
fcm_diag() {
    local result="失败"
    # 尝试解析
    local resolved_ip=$(ping -c 1 -W 2 mtalk.google.com 2>/dev/null | grep 'PING' | awk -F'[()]' '{print $2}')
    if [ -n "$resolved_ip" ]; then
        # 如果能解析，尝试 ping 一次
        ping -c 1 -W 2 mtalk.google.com >/dev/null 2>&1 && result="成功"
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: $result (解析IP: $resolved_ip)" >> $LOGFILE
        return 0
    else
        echo "[$(date '+%m-%d %H:%M:%S')] 连通性测试: $result (无法解析 mtalk.google.com)" >> $LOGFILE
        return 1
    fi
}

# ==========================================
# 获取网络指纹
# ==========================================
get_network_fingerprint() {
    local gw=$(ip route get 1.1.1.1 2>/dev/null | head -1 | awk '{print $3}')
    local dns1=$(getprop net.dns1)
    local dns2=$(getprop net.dns2)
    echo "${gw}_${dns1}_${dns2}"
}

# ==========================================
# 执行一次完整修复流程
# ==========================================
full_clean_and_verify() {
    echo "[$(date '+%m-%d %H:%M:%S')] 执行完整清理..." >> $LOGFILE
    clean_all_google_rules
    clean_uid_rules "$GMS_UID" "GMS"
    clean_uid_rules "$VENDING_UID" "Play商店"
    clean_uid_rules "$GSF_UID" "GSF"
    check_and_fix_hosts
    fcm_diag
}

# ==========================================
# 初次清理
# ==========================================
echo "[INFO] 开始初次防火墙清理，当前网络: $(get_network_type)" >> $LOGFILE
full_clean_and_verify

LAST_FINGERPRINT=$(get_network_fingerprint)
LAST_CONN_CHECK=$(date +%s)

echo "[INFO] 进入守护循环 (网络变化即时清理 + 10分钟断网修复)" >> $LOGFILE

# ==========================================
# 主循环
# ==========================================
while true; do
    # 1. 网络变化检测
    CURRENT_FP=$(get_network_fingerprint)
    if [ "$CURRENT_FP" != "$LAST_FINGERPRINT" ] && [ -n "$CURRENT_FP" ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 网络指纹变化: $LAST_FINGERPRINT -> $CURRENT_FP" >> $LOGFILE
        echo "[$(date '+%m-%d %H:%M:%S')] 切换至 $(get_network_type)，等待 5 秒稳定..." >> $LOGFILE
        sleep 5
        full_clean_and_verify
        LAST_FINGERPRINT="$CURRENT_FP"
        LAST_CONN_CHECK=$(date +%s)
    fi

    # 2. 10 分钟定时健康检查
    NOW=$(date +%s)
    if [ $((NOW - LAST_CONN_CHECK)) -ge 600 ]; then
        echo "[$(date '+%m-%d %H:%M:%S')] 10分钟定时健康检查 (当前网络: $(get_network_type))" >> $LOGFILE
        if ! fcm_diag; then
            echo "[$(date '+%m-%d %H:%M:%S')] FCM 不可达，启动修复流程..." >> $LOGFILE
            full_clean_and_verify
        else
            echo "[$(date '+%m-%d %H:%M:%S')] 连通性正常，无需清理。" >> $LOGFILE
        fi
        LAST_CONN_CHECK=$NOW
    fi

    sleep 10
done
