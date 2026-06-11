update_hosts() {
    local hosts_mode="dual"
    [ -f "$MODDIR/hosts_mode.conf" ] && hosts_mode=$(cat "$MODDIR/hosts_mode.conf")

    local primary_url=""
    local fallback_url=""

    if [ "$hosts_mode" = "ipv4" ]; then
        primary_url="https://fcm-hosts.cagedbird.cn/fcm_ipv4.hosts"
        fallback_url="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_ipv4.hosts"
    else
        primary_url="https://fcm-hosts.cagedbird.cn/fcm_dual.hosts"
        fallback_url="https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/fcm_dual.hosts"
    fi

    local dest_hosts="$MODDIR/system/etc/hosts"
    mkdir -p "$MODDIR/system/etc"
    
    local success=0
    if curl -sL --connect-timeout 5 -o "${dest_hosts}.tmp" "$primary_url" || curl -sL --connect-timeout 10 -o "${dest_hosts}.tmp" "$fallback_url"; then
        success=1
    elif wget -T 5 -qO "${dest_hosts}.tmp" "$primary_url" || wget -T 10 -qO "${dest_hosts}.tmp" "$fallback_url"; then
        success=1
    fi

    if [ $success -eq 1 ] && grep -q -i "google" "${dest_hosts}.tmp" 2>/dev/null; then
        # ========================================================
        # 核心修复 1：摒弃 mv -f，改用 cat 重写内容！
        # 保持文件 Inode 绝对不变，从而让开机早期的 Systemless 挂载映射关系依然完好生效
        # ========================================================
        cat "${dest_hosts}.tmp" > "$dest_hosts"
        chmod 644 "$dest_hosts"
        rm -f "${dest_hosts}.tmp"
        log_msg SUCCESS "Hosts 成功从远端下载并写入模块目录"
        
        # 核心修复 2：运行时强行追加物理 bind mount，防止某些极端的固件中途卸载挂载
        mount -o bind "$dest_hosts" /system/etc/hosts 2>/dev/null
    else
        log_msg ERROR "Hosts 下载失败或内容不合法，若存在旧配置则保持使用。"
        rm -f "${dest_hosts}.tmp"
    fi

    # 运行时直接镜像全局真实视图，作为挂载检验的唯一真理来源
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] --- 当前 Android 系统真实生效的 /system/etc/hosts 视图 ---" > "$HOSTS_LOG"
    if grep -q "google" /system/etc/hosts 2>/dev/null; then
        log_msg SUCCESS "[挂载检查] 恭喜！检测到系统全局 /system/etc/hosts 已成功并入优选规则！"
    else
        log_msg ERROR "[挂载检查] 警报！系统全局 /system/etc/hosts 未发现优选规则，模块 Systemless 挂载可能失效！"
        
        # 兜底尝试：如果系统层尚未挂载成功，在后期尝试强行进行运行时动态 bind 挂载注入
        mount -o bind "$dest_hosts" /system/etc/hosts 2>/dev/null
        if grep -q "google" /system/etc/hosts 2>/dev/null; then
            log_msg SUCCESS "[挂载检查] 后期运行时动态 bind 注入成功，系统 Hosts 已强制生效！"
        fi
    fi
    cat /system/etc/hosts >> "$HOSTS_LOG"
    echo "========================================================" >> "$HOSTS_LOG"
}
