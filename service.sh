#!/system/bin/sh

# ============================================================
# FCM-Fixer 开机服务脚本
# 顺序：等待启动 → 读取用户选择 → 下载 hosts → 清理防火墙 → 启动监控
# ============================================================

until [ $(getprop sys.boot_completed) -eq 1 ]; do
    sleep 2
done
sleep 60   # 确保系统 iptables 规则加载完毕

SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

rotate_clean_log
rotate_fcm_log

# ---------- 1. 根据用户选择下载 hosts ----------
HOSTS_CHOICE_FILE="/data/adb/box/run/hosts_choice"
HOSTS_INSTALLED_FLAG="${SCRIPT_DIR}/.hosts_installed"

if [ ! -f "$HOSTS_INSTALLED_FLAG" ]; then
    if [ -f "$HOSTS_CHOICE_FILE" ]; then
        HOSTS_TYPE=$(cat "$HOSTS_CHOICE_FILE")
    else
        HOSTS_TYPE="dual"   # 默认双栈
        echo "[$(date)] 未找到选择文件，使用默认双栈" >> "$CLEAN_LOG"
    fi

    echo "[$(date)] 开始下载 $HOSTS_TYPE hosts..." >> "$CLEAN_LOG"
    if install_hosts_to_module "$HOSTS_TYPE" "$SCRIPT_DIR"; then
        touch "$HOSTS_INSTALLED_FLAG"
        echo "[$(date)] hosts 安装成功" >> "$CLEAN_LOG"
        # 立即生效
        apply_hosts_bind_mount
    else
        echo "[$(date)] hosts 下载失败，请检查网络后重启" >> "$CLEAN_LOG"
    fi
else
    echo "[$(date)] hosts 已安装过，跳过下载" >> "$CLEAN_LOG"
    # 确保每次开机都尝试 bind mount（防止被覆盖）
    apply_hosts_bind_mount
fi

# ---------- 2. 清理防火墙规则 ----------
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
echo "[$(date)] 开始清理防火墙 REJECT/DROP 规则..." >> "$CLEAN_LOG"

for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done
echo "[$(date)] 防火墙清理完成" >> "$CLEAN_LOG"

# ---------- 3. 启动 FCM 监控 ----------
start_fcm_monitor

echo "[$(date)] service.sh 执行完毕" >> "$CLEAN_LOG"
