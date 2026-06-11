#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# 轮转旧日志（基于规范后的持久化目录操作）
[ -f "$MASTER_LOG" ] && mv -f "$MASTER_LOG" "$MASTER_LOG_OLD"
[ -f "$MASTER_HOSTS" ] && mv -f "$MASTER_HOSTS" "$MASTER_HOSTS_OLD"

# 初始化全新日志
echo -e "\033[1;36m==================== FCM Fixer 服务启动 ====================\033[0m" > "$MASTER_LOG"
sync_to_box

# 【第一阶段：紧急早期清理】
log_msg INFO "执行【第一阶段】开机极早期防火墙紧急盲删清理..."
chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
for chain in $chains; do
    remove_block_rules "filter" "$chain" "ipv4"
    remove_block_rules "filter" "$chain" "ipv6"
done

# 【第二阶段：常驻引导服务后台拉起】
(
    log_msg INFO "常驻引导进线程已进入后台，等待系统完全就绪 (sys.boot_completed)..."
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done

    log_msg SUCCESS "系统核心已完全就绪，启动【第二阶段】托管流程..."

    wait_for_network
    update_hosts

    log_msg INFO "执行开机后期防火墙规则二次复查清理..."
    for chain in $chains; do
        remove_block_rules "filter" "$chain" "ipv4"
        remove_block_rules "filter" "$chain" "ipv6"
    done

    log_fcm_info
    track_fcm_hits_loop &

    (
        sleep 30
        log_msg INFO "触发开机 30 秒整终极防补发规则复查..."
        for chain in $chains; do
            remove_block_rules "filter" "$chain" "ipv4"
            remove_block_rules "filter" "$chain" "ipv6"
        done
    ) &

    monitor_network_changes &

    log_msg SUCCESS "开机初始化引导全部安全交割，后台常驻进程正常工作。"
    echo -e "\033[1;32m============================================================\033[0m" >> "$MASTER_LOG"
    sync_to_box
) &
