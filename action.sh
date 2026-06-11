#!/system/bin/sh
SCRIPT_DIR=${0%/*}
. "${SCRIPT_DIR}/common.sh"

echo -e "\n\033[1;35m==================== 手动触发 FCM 修复 ====================\033[0m" >> "$MASTER_LOG"
sync_to_box
log_msg INFO "接收到用户手动触发指令，正在重新检查..."

update_hosts

chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
log_msg INFO "正在重新清理防火墙阻断规则..."
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

log_fcm_info

log_msg SUCCESS "手动触发的清理与挂载刷新全部完成！"
echo -e "\033[1;35m============================================================\033[0m" >> "$MASTER_LOG"
sync_to_box
