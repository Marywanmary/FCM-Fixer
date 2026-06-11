#!/system/bin/sh

until [ $(getprop sys.boot_completed) -eq 1 ]; do
    sleep 2
done
sleep 60

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

rotate_clean_log
rotate_fcm_log

# ---------- 1. 检查并确保 hosts 存在（保底）----------
HOSTS_INSTALLED_FLAG="${SCRIPT_DIR}/.hosts_installed"
MODULE_HOSTS="${SCRIPT_DIR}/system/etc/hosts"

if [ ! -f "$MODULE_HOSTS" ]; then
    echo "[$(date)] 检测到 hosts 文件缺失，尝试重新下载..." >> "$CLEAN_LOG"
    # 读取用户之前的选择（如果存在）
    if [ -f "$HOSTS_CHOICE_FILE" ]; then
        HOSTS_TYPE=$(cat "$HOSTS_CHOICE_FILE")
    else
        HOSTS_TYPE="dual"
    fi
    if install_hosts_to_module "$HOSTS_TYPE" "$SCRIPT_DIR"; then
        touch "$HOSTS_INSTALLED_FLAG"
        echo "[$(date)] 重新下载 hosts 成功" >> "$CLEAN_LOG"
    else
        echo "[$(date)] 重新下载 hosts 失败，请检查网络或手动执行 action.sh --hosts" >> "$CLEAN_LOG"
    fi
fi

# 每次开机尝试 bind mount 生效
apply_hosts_bind_mount

# ---------- 2. 清理防火墙规则 ----------
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# ---------- 3. 启动 FCM 监控 ----------
start_fcm_monitor

echo "[$(date)] service.sh 执行完毕" >> "$CLEAN_LOG"
