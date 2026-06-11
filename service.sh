#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# 处理旧日志
if [ -f "$LOGFILE" ]; then
    mv -f "$LOGFILE" "$LOGFILE_OLD"
fi
echo "[$(date)] FCM Fixer 服务已启动..." > "$LOGFILE"

# 等待网络连接以抓取 Hosts
wait_for_network
update_hosts

# 清理防火墙 (同时覆盖 v4 与 v6)
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
echo "[$(date)] 开始全面清理网络层阻断规则..." >> "$LOGFILE"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# 输出诊断信息备查
log_fcm_info

echo "[$(date)] 开机修复与挂载流程完成" >> "$LOGFILE"
