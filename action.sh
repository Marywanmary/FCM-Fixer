#!/system/bin/sh

# ============================================================
# FCM-Fixer 手动操作脚本
# 用法：
#   ./action.sh              - 仅清理防火墙规则
#   ./action.sh --hosts      - 清理规则后重新安装 hosts（会再次音量键选择）
# ============================================================

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

# 确保日志目录和清理日志存在
init_log_dir
touch "$CLEAN_LOG"

chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"

echo "[$(date)] ========== 手动执行开始 ==========" >> "$CLEAN_LOG"

# 清理防火墙规则
echo "[$(date)] 开始手动清理 IPv4 和 IPv6 中的 REJECT 规则..." >> "$CLEAN_LOG"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done
echo "[$(date)] 防火墙规则清理完成" >> "$CLEAN_LOG"

# 如果传入 --hosts 参数，重新安装 hosts
if [ "$1" = "--hosts" ]; then
    echo "[$(date)] 触发手动重装 hosts..." >> "$CLEAN_LOG"
    
    # 等待音量键选择
    wait_for_volume_key
    choice=$?
    
    case $choice in
        1)
            install_hosts_to_module "dual" "$SCRIPT_DIR"
            ;;
        2)
            install_hosts_to_module "ipv4" "$SCRIPT_DIR"
            ;;
        *)
            install_hosts_to_module "dual" "$SCRIPT_DIR"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] ✅ Hosts 重装成功" >> "$CLEAN_LOG"
        # 立即生效
        MODULE_HOSTS="${SCRIPT_DIR}/system/etc/hosts"
        mount -o bind "$MODULE_HOSTS" /system/etc/hosts 2>/dev/null && \
            echo "[$(date)] 已 bind mount 生效" >> "$CLEAN_LOG"
    else
        echo "[$(date)] ❌ Hosts 重装失败" >> "$CLEAN_LOG"
    fi
fi

echo "[$(date)] ========== 手动执行完成 ==========" >> "$CLEAN_LOG"
