#!/system/bin/sh

# ============================================================
# FCM-Fixer 启动脚本
# 执行顺序：
#   1. 等待系统启动完成
#   2. 清理防火墙中的 REJECT/DROP 规则
#   3. 安装优选 Hosts（首次运行或手动触发）
#   4. 启动 FCM 诊断监控
# ============================================================

# 等待 Android 系统完全启动
until [ $(getprop sys.boot_completed) -eq 1 ]; do
    sleep 2
done

# 额外等待 60 秒，确保系统 iptables 规则加载完毕
sleep 60

# 加载核心函数库
SCRIPT_DIR=${0%/*}
. ${SCRIPT_DIR}/common.sh

# ---------- 日志初始化 ----------
if [ -f "$LOGFILE" ]; then
    cp -f "$LOGFILE" "$BAKLOG"
    echo "[$(date)] ========== 新会话开始 ==========" > "$LOGFILE"
else
    echo "[$(date)] ========== 首次运行 ==========" > "$LOGFILE"
fi

# 轮转 FCM 日志（与 Box 共享目录）
rotate_fcm_log

# ---------- 清理防火墙规则 ----------
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
echo "[$(date)] 开始清理防火墙中的 REJECT/DROP 规则..." >> "$LOGFILE"

for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

echo "[$(date)] 防火墙规则清理完成" >> "$LOGFILE"

# ---------- 安装 Hosts（仅首次执行）----------
# 通过标志文件 .hosts_installed 判断是否已安装
# 如需重新安装，删除该标志文件或执行 action.sh --hosts
HOSTS_INSTALLED_FLAG="${SCRIPT_DIR}/.hosts_installed"
HOSTS_TYPE_FLAG="${SCRIPT_DIR}/.hosts_type"

if [ ! -f "$HOSTS_INSTALLED_FLAG" ]; then
    echo "[$(date)] 首次运行，开始安装优选 Hosts..." >> "$LOGFILE"
    
    # 等待音量键选择
    wait_for_volume_key
    choice=$?
    
    case $choice in
        1)
            install_hosts "dual"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "dual" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ 双栈 hosts 安装成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ 双栈 hosts 安装失败" >> "$LOGFILE"
            fi
            ;;
        2)
            install_hosts "ipv4"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "ipv4" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ IPv4 hosts 安装成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ IPv4 hosts 安装失败" >> "$LOGFILE"
            fi
            ;;
        *)
            # 超时或出错，默认安装双栈
            install_hosts "dual"
            if [ $? -eq 0 ]; then
                touch "$HOSTS_INSTALLED_FLAG"
                echo "dual" > "$HOSTS_TYPE_FLAG"
                echo "[$(date)] ✓ 默认安装双栈 hosts 成功" >> "$LOGFILE"
            else
                echo "[$(date)] ✗ 默认安装双栈 hosts 失败" >> "$LOGFILE"
            fi
            ;;
    esac
else
    # 已安装过 hosts，显示当前使用的类型
    if [ -f "$HOSTS_TYPE_FLAG" ]; then
        current_type=$(cat "$HOSTS_TYPE_FLAG")
        echo "[$(date)] Hosts 已安装（类型: $current_type），跳过安装" >> "$LOGFILE"
    else
        echo "[$(date)] Hosts 已安装，跳过安装" >> "$LOGFILE"
    fi
fi

# ---------- 启动 FCM 监控 ----------
start_fcm_monitor

echo "[$(date)] ========== service.sh 执行完成 ==========" >> "$LOGFILE"
