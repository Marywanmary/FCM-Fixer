#!/system/bin/sh

# ============================================================
# FCM-Fixer 手动操作脚本
# 用法：
#   ./action.sh              - 仅清理防火墙规则
#   ./action.sh --hosts      - 清理规则后重新安装 hosts
# ============================================================

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"

echo "[$(date)] ========== 手动执行开始 ==========" >> "$LOGFILE"

# 清理防火墙规则
echo "[$(date)] 开始手动清理 IPv4 和 IPv6 中的 REJECT 规则..." >> "$LOGFILE"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done
echo "[$(date)] 防火墙规则清理完成" >> "$LOGFILE"

# 如果传入 --hosts 参数，重新安装 hosts
if [ "$1" = "--hosts" ]; then
    echo "[$(date)] 触发手动重装 hosts..." >> "$LOGFILE"
    
    # 删除标志文件以允许重新选择
    HOSTS_INSTALLED_FLAG="${SCRIPT_DIR}/.hosts_installed"
    HOSTS_TYPE_FLAG="${SCRIPT_DIR}/.hosts_type"
    rm -f "$HOSTS_INSTALLED_FLAG"
    rm -f "$HOSTS_TYPE_FLAG"
    
    # 等待音量键选择
    wait_for_volume_key
    choice=$?
    
    case $choice in
        1)
            install_hosts "dual"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "dual" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ 双栈 hosts 重装成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ 双栈 hosts 重装失败" >> "$LOGFILE"
            fi
            ;;
        2)
            install_hosts "ipv4"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "ipv4" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ IPv4 hosts 重装成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ IPv4 hosts 重装失败" >> "$LOGFILE"
            fi
            ;;
        *)
            install_hosts "dual"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "dual" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ 默认双栈 hosts 重装成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ 默认双栈 hosts 重装失败" >> "$LOGFILE"
            fi
            ;;
    esac
fi

echo "[$(date)] ========== 手动执行完成 ==========" >> "$LOGFILE"
