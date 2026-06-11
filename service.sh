#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# 轮转所有日志
[ -f "$LOGFILE" ] && mv -f "$LOGFILE" "$LOGFILE_OLD"
[ -f "$HOSTS_LOG" ] && mv -f "$HOSTS_LOG" "$HOSTS_LOG_OLD"

echo "[$(date)] 等待系统启动完成..." > "$LOGFILE"

# 等待系统 UI / 核心服务完全加载完毕
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

echo "[$(date)] 系统已启动，FCM Fixer 开始执行..." >> "$LOGFILE"

wait_for_network
update_hosts

chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"

# 首次清理
echo "[$(date)] 开始全面清理网络层阻断规则..." >> "$LOGFILE"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

log_fcm_info

# 防火墙补充监听机制 (防止系统在网络连通后延迟下发规则)
# 后台等待 30 秒后进行一次复查
(
    sleep 30
    echo "[$(date)] 开机 30 秒后复查防火墙规则..." >> "$LOGFILE"
    for chain in $chains; do
        remove_block_rules "filter" "$chain" "ipv4"
        remove_block_rules "filter" "$chain" "ipv6"
    done
) &

echo "[$(date)] 开机修复与挂载流程初步完成，后台复查进程已启动" >> "$LOGFILE"
