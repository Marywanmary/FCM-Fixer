#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# 轮转旧日志
[ -f "$LOGFILE" ] && mv -f "$LOGFILE" "$LOGFILE_OLD"
[ -f "$HOSTS_LOG" ] && mv -f "$HOSTS_LOG" "$HOSTS_LOG_OLD"

# 初始化新日志
echo -e "\033[1;36m==================== FCM Fixer 服务启动 ====================\033[0m" > "$LOGFILE"
log_msg INFO "等待系统完全启动 (sys.boot_completed)..."

# 等待系统 UI / 核心服务完全加载完毕
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

log_msg SUCCESS "系统核心已就绪，FCM 修复流程正式开始..."

# 检查网络并更新 Hosts
wait_for_network
update_hosts

# 首次开机清理防火墙
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
log_msg INFO "开始执行首次开机网络层阻断规则清理..."
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# 抓取开机初期的 FCM 连接诊断
log_fcm_info

# 延迟 30 秒补充复查防火墙（应对某些系统开机后期动态补发规则）
(
    sleep 30
    log_msg INFO "触发开机 30 秒后期防火墙规则复查..."
    for chain in $chains; do
        remove_block_rules "filter" "$chain" "ipv4"
        remove_block_rules "filter" "$chain" "ipv6"
    done
) &

# 启动事件驱动的后台网络状态监视器
monitor_network_changes &

log_msg SUCCESS "开机初始化流程全部完成，常驻网络监视器已挂载后台。"
echo -e "\033[1;36m============================================================\033[0m" >> "$LOGFILE"
