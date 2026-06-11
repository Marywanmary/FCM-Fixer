#!/system/bin/sh

LOGFILE="/data/local/tmp/fcm_fixer.log"
OLDLOG="/data/local/tmp/fcm_fixer_old.log"

# ==========================================
# 日志轮替 (Log Rotation)
# 每次开机将旧日志重命名备份，再创建新日志
# ==========================================
if [ -f "$LOGFILE" ]; then
    mv -f "$LOGFILE" "$OLDLOG"
fi
echo "=== FCM-Fixer Service v1.0.1 启动于 $(date '+%Y-%m-%d %H:%M:%S') ===" > $LOGFILE

# 等待系统启动挂载
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done
echo "[INFO] 系统启动完成，守护进程已就绪。" >> $LOGFILE

# 鲁棒性 UID 获取 (直接读文件)
get_uid() {
  cat /data/system/packages.list 2>/dev/null | grep "^$1 " | awk '{print $2}'
}

# 循环等待 GMS 初始化
GMS_UID=""
while [ -z "$GMS_UID" ]; do
  GMS_UID=$(get_uid "com.google.android.gms")
  [ -z "$GMS_UID" ] && sleep 3
done

VENDING_UID=$(get_uid "com.android.vending")
GSF_UID=$(get_uid "com.google.android.gsf")

echo "[INFO] 获取目标 UID 成功:" >> $LOGFILE
echo " - GMS UID: $GMS_UID" >> $LOGFILE
echo " - Play商店 UID: $VENDING_UID" >> $LOGFILE
echo " - GSF UID: $GSF_UID" >> $LOGFILE

# 核心清理逻辑：成功删除了规则才写入日志
clean_firewall() {
  local uid=$1
  local app_name=$2
  
  if [ -n "$uid" ]; then
    iptables -t filter -D OUTPUT -m owner --uid-owner $uid -j REJECT >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] 解除: 删除了 $app_name 的 IPv4 REJECT" >> $LOGFILE
    
    iptables -t filter -D OUTPUT -m owner --uid-owner $uid -j DROP >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] 解除: 删除了 $app_name 的 IPv4 DROP" >> $LOGFILE
    
    ip6tables -t filter -D OUTPUT -m owner --uid-owner $uid -j REJECT >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] 解除: 删除了 $app_name 的 IPv6 REJECT" >> $LOGFILE
    
    ip6tables -t filter -D OUTPUT -m owner --uid-owner $uid -j DROP >/dev/null 2>&1
    [ $? -eq 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] 解除: 删除了 $app_name 的 IPv6 DROP" >> $LOGFILE
  fi
}

echo "[INFO] 进入底层防火墙监控循环 (5秒间隔)..." >> $LOGFILE

# 5秒心跳无条件防反弹监控
while true; do
  clean_firewall "$GMS_UID" "GMS"
  clean_firewall "$VENDING_UID" "Play商店"
  clean_firewall "$GSF_UID" "GSF"
  
  sleep 5
done
