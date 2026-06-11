#!/system/bin/sh

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

init_log_dir
rotate_clean_log

# 清理防火墙
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# 如果传入 --hosts，强制重装
if [ "$1" = "--hosts" ]; then
    echo "[$(date)] 手动触发 hosts 重装" >> "$CLEAN_LOG"
    # 删除旧标志和 hosts 文件
    rm -f "${SCRIPT_DIR}/.hosts_installed"
    rm -f "${SCRIPT_DIR}/system/etc/hosts"
    # 读取用户之前的选择（或默认双栈）
    if [ -f "$HOSTS_CHOICE_FILE" ]; then
        HOSTS_TYPE=$(cat "$HOSTS_CHOICE_FILE")
    else
        HOSTS_TYPE="dual"
    fi
    if install_hosts_to_module "$HOSTS_TYPE" "$SCRIPT_DIR"; then
        touch "${SCRIPT_DIR}/.hosts_installed"
        echo "[$(date)] 手动重装 hosts 成功" >> "$CLEAN_LOG"
        # 立即生效
        mount -o bind "${SCRIPT_DIR}/system/etc/hosts" /system/etc/hosts 2>/dev/null
        echo "✅ Hosts 重装成功并已生效"
    else
        echo "[$(date)] 手动重装 hosts 失败" >> "$CLEAN_LOG"
        echo "❌ 下载失败，请检查网络后重试"
    fi
else
    echo "[$(date)] 仅执行防火墙清理" >> "$CLEAN_LOG"
fi
