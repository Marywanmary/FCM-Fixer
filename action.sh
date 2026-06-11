#!/system/bin/sh

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

init_log_dir
rotate_clean_log   # 追加到清理日志

# 清理防火墙规则
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# 如果传入 --hosts 参数，强制重装 hosts（删除标志，下次开机重新下载）
if [ "$1" = "--hosts" ]; then
    rm -f "${SCRIPT_DIR}/.hosts_installed"
    echo "[$(date)] 已删除 hosts 安装标志，下次重启将重新下载" >> "$CLEAN_LOG"
    ui_print "✅ 已重置 hosts 状态，请重启手机使新 hosts 生效"
fi
