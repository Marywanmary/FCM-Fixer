#!/system/bin/sh
SCRIPT_DIR=${0%/*}
. "${SCRIPT_DIR}/common.sh"

echo "[$(date)] 收到手动触发更新与清理指令..." >> "$LOGFILE"

update_hosts

chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

log_fcm_info

echo "[$(date)] 手动清理与挂载刷新完成！" >> "$LOGFILE"
