#!/system/bin/sh

# ============================================================
# FCM-Fixer 开机启动脚本
# 执行顺序：
#   1. 等待系统启动完成
#   2. 清理防火墙中的 REJECT/DROP 规则
#   3. 检查模块内的 hosts 文件是否存在，若不存在则重新下载（保底）
#   4. 启动 FCM 诊断监控
# ============================================================

until [ $(getprop sys.boot_completed) -eq 1 ]; do
    sleep 2
done

# 额外等待 60 秒，确保系统 iptables 规则加载完毕
sleep 60

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

# 初始化日志（轮转）
rotate_clean_log
rotate_fcm_log

# ---------- 1. 清理防火墙规则 ----------
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
echo "[$(date)] 开始清理防火墙中的 REJECT/DROP 规则..." >> "$CLEAN_LOG"

for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

echo "[$(date)] 防火墙规则清理完成" >> "$CLEAN_LOG"

# ---------- 2. 检查 hosts 文件是否存在（保底）----------
# 如果模块内的 hosts 文件丢失（例如被误删），则重新下载默认双栈 hosts
MODULE_HOSTS="${SCRIPT_DIR}/system/etc/hosts"
if [ ! -f "$MODULE_HOSTS" ]; then
    echo "[$(date)] 警告：模块 hosts 文件不存在，正在重新下载..." >> "$CLEAN_LOG"
    # 重新下载双栈 hosts（默认）
    if install_hosts_to_module "dual" "$SCRIPT_DIR"; then
        echo "[$(date)] ✅ 重新下载 hosts 成功" >> "$CLEAN_LOG"
        # 尝试立即生效
        mount -o bind "$MODULE_HOSTS" /system/etc/hosts 2>/dev/null && \
            echo "[$(date)] 已 bind mount 生效" >> "$CLEAN_LOG"
    else
        echo "[$(date)] ❌ 重新下载 hosts 失败" >> "$CLEAN_LOG"
    fi
fi

# ---------- 3. 启动 FCM 监控 ----------
start_fcm_monitor

echo "[$(date)] service.sh 执行完毕" >> "$CLEAN_LOG"
