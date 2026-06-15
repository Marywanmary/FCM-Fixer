#!/system/bin/sh
MODDIR=${0%/*}

SAFE_DIR="/data/adb/fcm_fixer"
mkdir -p "$SAFE_DIR"

MASTER_LOG="$SAFE_DIR/fcm_fixer.log"
MASTER_LOG_OLD="$SAFE_DIR/fcm_fixer_old.log"
MASTER_HOSTS="$SAFE_DIR/hosts.log"
MASTER_HOSTS_OLD="$SAFE_DIR/hosts_old.log"

BOX_RUN_DIR="/data/adb/box/run"

sync_to_box() {
    if [ -d "$BOX_RUN_DIR" ] || mkdir -p "$BOX_RUN_DIR" 2>/dev/null; then
        cp -f "$MASTER_LOG" "$BOX_RUN_DIR/fcm_fixer.log" 2>/dev/null
        [ -f "$MASTER_LOG_OLD" ] && cp -f "$MASTER_LOG_OLD" "$BOX_RUN_DIR/fcm_fixer_old.log" 2>/dev/null
        [ -f "$MASTER_HOSTS" ] && cp -f "$MASTER_HOSTS" "$BOX_RUN_DIR/hosts.log" 2>/dev/null
        [ -f "$MASTER_HOSTS_OLD" ] && cp -f "$MASTER_HOSTS_OLD" "$BOX_RUN_DIR/hosts_old.log" 2>/dev/null
    fi
}

log_msg() {
    local level="$1"
    local msg="$2"
    local time_str=$(date "+%Y-%m-%d %H:%M:%S")
    
    local C_RESET="\033[0m"
    local C_INFO="\033[36m"
    local C_WARN="\033[33m"
    local C_ERROR="\033[31m"
    local C_SUCC="\033[1;32m"
    local C_HIGH="\033[1;35m"

    case "$level" in
        INFO)    printf "${C_INFO}[%s] [ℹ️ INFO] %s${C_RESET}\n" "$time_str" "$msg" >> "$MASTER_LOG" ;;
        WARN)    printf "${C_WARN}[%s] [⚠️ WARN] %s${C_RESET}\n" "$time_str" "$msg" >> "$MASTER_LOG" ;;
        ERROR)   printf "${C_ERROR}[%s] [❌ ERROR] %s${C_RESET}\n" "$time_str" "$msg" >> "$MASTER_LOG" ;;
        SUCCESS) printf "${C_SUCC}[%s] [✅ SUCC] %s${C_RESET}\n" "$time_str" "$msg" >> "$MASTER_LOG" ;;
        MATCH)   printf "${C_HIGH}[%s] [🎯 MATCH] %s${C_RESET}\n" "$time_str" "$msg" >> "$MASTER_LOG" ;;
        *)       printf "${C_RESET}[%s] [%s] %s${C_RESET}\n" "$time_str" "$level" "$msg" >> "$MASTER_LOG" ;;
    esac
    sync_to_box
}

remove_block_rules() {
    local table="${1:-filter}"
    local chain="$2"
    local proto="${3:-ipv4}"
    local cmd=""

    case "$proto" in
        ipv4) cmd="iptables" ;;
        ipv6) cmd="ip6tables" ;;
        *) log_msg ERROR "不支持的协议 $proto"; return 1 ;;
    esac

    if ! command -v "$cmd" > /dev/null 2>&1; then return 0; fi

    local line_numbers=$( $cmd -t "$table" -nvL "$chain" --line-numbers 2> /dev/null | awk '/REJECT|DROP/ {print $1}' | sort -rn )
    if [ -z "$line_numbers" ]; then return 0; fi

    local deleted_count=0
    for line_num in $line_numbers; do
        if $cmd -t "$table" -D "$chain" "$line_num" 2> /dev/null; then
            deleted_count=$((deleted_count + 1))
        fi
    done
    log_msg SUCCESS "$proto: $chain 链成功清理了 ${deleted_count} 条阻断规则"
}

wait_for_network() {
    local i=0
    while [ $i -lt 30 ]; do
        if ping -c 1 -W 1 223.5.5.5 > /dev/null 2>&1; then
            log_msg INFO "网络就绪，准备拉取/检查 Hosts..."
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    log_msg WARN "等待网络超时，将继续执行后续逻辑。"
    return 1
}

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
        echo -e "127.0.0.1       localhost\n::1             localhost\n\n# === FCM Hosts Optimizer Start ===" > "$dest_hosts"
        cat "${dest_hosts}.tmp" >> "$dest_hosts"
        echo -e "\n# === FCM Hosts Optimizer End ===" >> "$dest_hosts"
        chmod 644 "$dest_hosts"
        rm -f "${dest_hosts}.tmp"
        log_msg SUCCESS "Hosts 成功从远端下载，并完美合并系统 Localhost 回环机制"
        mount -o bind "$dest_hosts" /system/etc/hosts 2>/dev/null
    else
        log_msg ERROR "Hosts 下载失败或内容不合法，保持使用现有配置。"
        rm -f "${dest_hosts}.tmp"
    fi

    echo "[$(date "+%Y-%m-%d %H:%M:%S")] --- 当前 Android 系统真实生效的 /system/etc/hosts 视图 ---" > "$MASTER_HOSTS"
    if grep -q "google" /system/etc/hosts 2>/dev/null; then
        log_msg SUCCESS "[挂载检查] 恭喜！检测到系统全局 /system/etc/hosts 已成功并入优选规则！"
    else
        log_msg ERROR "[挂载检查] 警报！系统全局 /system/etc/hosts 未发现优选规则，模块 Systemless 挂载可能失效！"
        mount -o bind "$dest_hosts" /system/etc/hosts 2>/dev/null
        if grep -q "google" /system/etc/hosts 2>/dev/null; then
            log_msg SUCCESS "[挂载检查] 后期运行时动态 bind 注入成功，系统 Hosts 已强制生效！"
        fi
    fi
    cat /system/etc/hosts >> "$MASTER_HOSTS"
    echo "========================================================" >> "$MASTER_HOSTS"
    sync_to_box
}

check_fcm_hosts_hit() {
    local dest_hosts="$MODDIR/system/etc/hosts"
    if [ ! -f "$dest_hosts" ]; then
        return
    fi

    local dns_test=""
    if command -v nslookup > /dev/null 2>&1; then
        dns_test=$(timeout 2 nslookup a.fake.ip.test.fcm.fixer 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | tail -n 1)
    fi
    [ -z "$dns_test" ] && dns_test=$(timeout 2 ping -c 1 -W 1 a.fake.ip.test.fcm.fixer 2>/dev/null | grep -oE "\([0-9.]+\)" | tr -d '()')
    
    local is_fake_ip_global=0
    if echo "$dns_test" | grep -q -E "^198\.18\."; then
        is_fake_ip_global=1
    fi

    local fcm_exclusive_conns=$(ss -ant 2>/dev/null | grep "ESTAB" | grep -E ":522[89]|:5230")

    if [ "$is_fake_ip_global" -eq 1 ]; then
        if [ -z "$fcm_exclusive_conns" ]; then return; fi
        local real_outbound=$(echo "$fcm_exclusive_conns" | awk '{print $5}' | grep -v -E "^127\.|^10\.|^192\.168\.|^198\.1[89]\.")
        if [ -n "$real_outbound" ]; then
            echo "$real_outbound" | sort -u | while read -r remote_peer; do
                local clean_ip=$(echo "$remote_peer" | sed -E 's/\[?([0-9a-fA-F:.]+)\]?:[0-9]+/\1/')
                clean_ip=$(echo "$clean_ip" | sed -E 's/^::ffff://i')
                local clean_port=$(echo "$remote_peer" | sed -E 's/.*:([0-9]+)$/\1/')
                
                log_msg INFO "🎯 [穿透追踪] 成功抓取到代理内核外发的 FCM 真实物理公网 IP: $clean_ip (端口: $clean_port)"
                if grep -q "$clean_ip" "$dest_hosts"; then
                    log_msg MATCH "★★★ 命中成功！代理内核已成功将流量桥接至你的优选 Hosts 节点！ ★★★"
                    log_msg MATCH "--> 命中规则: $(grep "$clean_ip" "$dest_hosts" | head -n 1 | tr -s '\t ' ' ')"
                else
                    log_msg WARN "⚠️ 代理外发连接未命中优选 Hosts。原因：Clash 内核拥有独立 DNS 缓存或使用了远程公网 DNS 解析。"
                fi
            done
        fi
        return
    fi

    local gms_conns=$(ss -antp 2>/dev/null | grep "ESTAB" | grep -E "com.google.android.gms|GmsCore" | grep -E ":522[89]|:5230|:443")
    [ -z "$gms_conns" ] && gms_conns="$fcm_exclusive_conns"

    if [ -z "$gms_conns" ]; then return; fi

    echo "$gms_conns" | awk '{print $5}' | sort -u | while read -r remote_peer; do
        [ -z "$remote_peer" ] && continue
        local clean_ip=$(echo "$remote_peer" | sed -E 's/\[?([0-9a-fA-F:.]+)\]?:[0-9]+/\1/')
        clean_ip=$(echo "$clean_ip" | sed -E 's/^::ffff://i')
        local clean_port=$(echo "$remote_peer" | sed -E 's/.*:([0-9]+)$/\1/')
        
        log_msg INFO "发现活跃直连 FCM 通道 -> 远程 IP: $clean_ip | 目标端口: $clean_port"
        if grep -q "$clean_ip" "$dest_hosts"; then
            log_msg MATCH "★★★ 命中成功！当前连接正通过端口 [$clean_port] 直连优选 Hosts 节点！ ★★★"
            log_msg MATCH "--> 命中规则: $(grep "$clean_ip" "$dest_hosts" | head -n 1 | tr -s '\t ' ' ')"
        else
            log_msg WARN "⚠️ 未命中：当前通信 IP ($clean_ip) 不在你的优选 Hosts 列表中。"
        fi
    done
}

track_fcm_hits_loop() {
    log_msg INFO "🚀 启动连环命中追踪探测链 (每3秒检测一次，连续检测5次)..."
    local count=1
    while [ $count -le 5 ]; do
        sleep 3
        log_msg INFO "--- [第 ${count}/5 次命中轮询核对] ---"
        check_fcm_hosts_hit
        count=$((count + 1))
    done
    log_msg INFO "探测链本轮轮询结束。"
}

log_fcm_info() {
    echo -e "\n\033[36m================= FCM 状态与诊断截取 =================\033[0m" >> "$MASTER_LOG"
    check_fcm_hosts_hit
    log_msg INFO "抓取 GcmService 核心状态:"
    dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -E -i "connection|endpoint|connected|status|error|network" -A 5 >> "$MASTER_LOG"
    echo -e "\033[36m========================================================\033[0m\n" >> "$MASTER_LOG"
    sync_to_box
}

# ========================================================
# 🌟 核心终极重构：业界标准「指数退避 (Exponential Backoff)」弹性状态轮询
# ========================================================
monitor_network_changes() {
    log_msg INFO "网络状态监视守护进程已启动 (弹性指数退避轮询模式)..."
    
    local last_iface=""
    local MIN_SLEEP=3
    local MAX_SLEEP=30
    local current_sleep=$MIN_SLEEP
    
    while true; do
        local current_iface=$(ip route get 223.5.5.5 2>/dev/null | grep -o "dev [^ ]*" | awk '{print $2}' | head -n 1)
        [ -z "$current_iface" ] && current_iface="OFFLINE"
        
        if [ "$current_iface" != "$last_iface" ]; then
            if [ -n "$last_iface" ] && [ "$current_iface" != "OFFLINE" ]; then
                local net_type="未知网络"
                case "$current_iface" in
                    wlan*) net_type="Wi-Fi ($current_iface)" ;;
                    rmnet*|ccmni*|pdp*) net_type="移动数据/蜂窝网络 ($current_iface)" ;;
                    tun*|tap*) net_type="VPN/透明代理节点 ($current_iface)" ;;
                    *) net_type="$current_iface" ;;
                esac
                
                echo -e "\n\033[1;36m========================================================\033[0m" >> "$MASTER_LOG"
                log_msg INFO "🌐 监测到网络发生实质性切换！( $last_iface -> $current_iface ) | 出口: $net_type"
                
                local chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
                for chain in $chains; do
                    remove_block_rules "filter" "$chain" "ipv4"
                    remove_block_rules "filter" "$chain" "ipv6"
                done
                
                update_hosts &
                
                log_msg INFO "强制重置 GmsCore 网络通道，切断缓存连接，迫使其重新读取新环境的 Hosts..."
                killall -9 com.google.android.gms.persistent 2>/dev/null
                
                track_fcm_hits_loop &
            fi
            
            last_iface="$current_iface"
            current_sleep=$MIN_SLEEP
        else
            current_sleep=$((current_sleep * 2))
            if [ $current_sleep -gt $MAX_SLEEP ]; then
                current_sleep=$MAX_SLEEP
            fi
        fi
        sleep $current_sleep
    done
}

# ========================================================
# 🌟 核心新增特性：无感静默热更新守护进程 (带有日期防抖印记)
# ========================================================
auto_update_daemon() {
    log_msg INFO "⏰ 每日自动热更新守护进程已挂载后台 (目标规则: 每日 07:00 后触发一次)..."
    
    local last_run_file="$SAFE_DIR/last_update_date"
    
    while true; do
        # 获取当前小时 (去除前导0以防八进制错误，如 08 报错)
        local current_hour=$(date "+%H" | sed 's/^0//')
        [ -z "$current_hour" ] && current_hour=0
        
        # 获取今天完整的日期 (例如 20260612)
        local current_date=$(date "+%Y%m%d")
        
        # 读取小纸条上的上次执行日期
        local last_run=""
        [ -f "$last_run_file" ] && last_run=$(cat "$last_run_file")
        
        # 核心逻辑：只要过了 7 点 (包含 7 点)，且今天还没有执行过！
        if [ "$current_hour" -ge 7 ] && [ "$current_date" != "$last_run" ]; then
            
            echo -e "\n\033[1;35m========================================================\033[0m" >> "$MASTER_LOG"
            log_msg INFO "🌅 触发每日例行维护：时间已超过 07:00，开始自动拉取最新 FCM 优选 Hosts..."
            
            # 1. 静默下载并热更新 Hosts
            update_hosts
            
            # 2. 斩断旧连接，迫使 GMS 热重载应用新规则 (全程无须重启手机)
            log_msg INFO "热更新完毕！强制重置 GmsCore 网络通道，静默应用今日最新节点..."
            killall -9 com.google.android.gms.persistent 2>/dev/null
            
            # 3. 追踪重连命中情况
            track_fcm_hits_loop &
            
            # 4. 留下防抖印记：记录今天的日期到小纸条，保证今天绝不重复执行
            echo "$current_date" > "$last_run_file"
            
            # 执行完毕后，深度休眠 12 个小时 (43200秒)。极大减少无谓的判断轮询。
            sleep 43200
        else
            # 未满足条件 (比如现在是凌晨 3 点，或者今天早上 7 点刚更新过)
            # 每 30 分钟 (1800秒) 醒来检查一次手表，耗电量趋近于 0
            sleep 1800
        fi
    done
}
