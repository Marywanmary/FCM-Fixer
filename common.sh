#!/system/bin/sh
MODDIR=${0%/*}

BOX_RUN_DIR="/data/adb/box/run"
mkdir -p "$BOX_RUN_DIR"

LOGFILE="$BOX_RUN_DIR/fcm_fixer.log"
LOGFILE_OLD="$BOX_RUN_DIR/fcm_fixer_old.log"
HOSTS_LOG="$BOX_RUN_DIR/hosts.log"
HOSTS_LOG_OLD="$BOX_RUN_DIR/hosts_old.log"

# === 全新日志输出系统 (时间 + 分级 + 颜色) ===
log_msg() {
    local level="$1"
    local msg="$2"
    local time_str=$(date "+%Y-%m-%d %H:%M:%S")
    
    # ANSI 颜色定义 (兼容 KernelSU/Box 等支持彩色输出的查看器)
    local C_RESET="\033[0m"
    local C_INFO="\033[36m"    # 青色
    local C_WARN="\033[33m"    # 黄色
    local C_ERROR="\033[31m"   # 红色
    local C_SUCC="\033[1;32m"  # 粗体绿色
    local C_HIGH="\033[1;35m"  # 粗体洋红色

    case "$level" in
        INFO)    printf "${C_INFO}[%s] [ℹ️ INFO] %s${C_RESET}\n" "$time_str" "$msg" >> "$LOGFILE" ;;
        WARN)    printf "${C_WARN}[%s] [⚠️ WARN] %s${C_RESET}\n" "$time_str" "$msg" >> "$LOGFILE" ;;
        ERROR)   printf "${C_ERROR}[%s] [❌ ERROR] %s${C_RESET}\n" "$time_str" "$msg" >> "$LOGFILE" ;;
        SUCCESS) printf "${C_SUCC}[%s] [✅ SUCC] %s${C_RESET}\n" "$time_str" "$msg" >> "$LOGFILE" ;;
        MATCH)   printf "${C_HIGH}[%s] [🎯 MATCH] %s${C_RESET}\n" "$time_str" "$msg" >> "$LOGFILE" ;;
        *)       printf "${C_RESET}[%s] [%s] %s${C_RESET}\n" "$time_str" "$level" "$msg" >> "$LOGFILE" ;;
    esac
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
        mv -f "${dest_hosts}.tmp" "$dest_hosts"
        chmod 644 "$dest_hosts"
        log_msg SUCCESS "Hosts 成功从远端更新 (当前模式: $hosts_mode)"
        
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] --- 当前生效的 Hosts 内容 (模式: $hosts_mode) ---" > "$HOSTS_LOG"
        cat "$dest_hosts" >> "$HOSTS_LOG"
    else
        log_msg ERROR "Hosts 下载失败或内容不合法，若存在旧配置则继续使用。"
        rm -f "${dest_hosts}.tmp"
        
        if [ -f "$dest_hosts" ]; then
            echo "[$(date "+%Y-%m-%d %H:%M:%S")] --- 使用模块内已存在的旧版 Hosts 内容 ---" > "$HOSTS_LOG"
            cat "$dest_hosts" >> "$HOSTS_LOG"
        fi
    fi
}

# === 新增：检查 FCM 连接 IP 是否命中 Hosts ===
check_fcm_hosts_hit() {
    local dest_hosts="$MODDIR/system/etc/hosts"
    if [ ! -f "$dest_hosts" ]; then
        log_msg WARN "尚未生成 Hosts 文件，跳过命中检测。"
        return
    fi

    # 抓取系统中目标端口为 5228/5229/5230 且状态为 ESTABLISHED（已连接）的会话
    local active_conns=$(netstat -an 2>/dev/null | grep -E "ESTABLISHED" | grep -E ":522[89]|:5230" | awk '{print $5}')
    
    if [ -z "$active_conns" ]; then
        log_msg WARN "当前未检测到活跃的 FCM (5228/5229/5230) TCP 连接。可能是刚开机或尚未重连。"
        return
    fi

    for item in $active_conns; do
        # 提取目标 IP：去掉最后一个冒号和端口号，并清理 IPv6 的中括号
        local clean_ip=${item%:*:-}
        clean_ip=$(echo "$clean_ip" | tr -d '[]')
        
        log_msg INFO "检测到当前活跃的 FCM 连接通道 IP: $clean_ip"
        
        # 将该 IP 与下载的 Hosts 进行强匹配
        if grep -q "$clean_ip" "$dest_hosts"; then
            local hit_line=$(grep "$clean_ip" "$dest_hosts" | head -n 1 | tr -s '\t ' ' ')
            log_msg MATCH "★★★ 验证成功！当前系统正使用优选节点，在 Hosts 中完美命中！ ★★★"
            log_msg MATCH "--> 命中规则: $hit_line"
        else
            log_msg WARN "未命中：当前通信 IP ($clean_ip) 不在你的优选 Hosts 列表中。"
            log_msg WARN "原因可能是：FCM 流量被网络代理(Clash/Box等)接管，或是系统走了其他的备用解析缓存。"
        fi
    done
}

log_fcm_info() {
    echo -e "\n\033[36m================= FCM 状态与诊断截取 =================\033[0m" >> "$LOGFILE"
    
    # 执行 Hosts 实际命中检测验证
    check_fcm_hosts_hit
    
    log_msg INFO "抓取 GcmService 核心状态:"
    dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -E -i "connection|endpoint|connected|status|error|network" -A 5 >> "$LOGFILE"
    echo -e "\033[36m========================================================\033[0m\n" >> "$LOGFILE"
}

# === 事件驱动的网络状态监视 ===
monitor_network_changes() {
    log_msg INFO "网络状态监视守护进程已启动 (内核事件驱动模式)..."
    
    local last_trigger=0
    
    ip monitor route | while read -r line; do
        if echo "$line" | grep -q "default via"; then
            local current_time=$(date +%s)
            
            if [ $((current_time - last_trigger)) -gt 10 ]; then
                last_trigger=$current_time
                sleep 3
                
                local active_iface=$(ip route get 8.8.8.8 2>/dev/null | grep -o "dev [^ ]*" | awk '{print $2}' | head -n 1)
                local net_type="未知网络"
                
                case "$active_iface" in
                    wlan*) net_type="Wi-Fi ($active_iface)" ;;
                    rmnet*|ccmni*|pdp*) net_type="移动数据 ($active_iface)" ;;
                    tun*|tap*) net_type="VPN/代理节点 ($active_iface)" ;;
                    *) [ -n "$active_iface" ] && net_type="$active_iface" ;;
                esac
                
                echo -e "\n\033[1;36m========================================================\033[0m" >> "$LOGFILE"
                log_msg INFO "🌐 监测到网络环境物理切换！主网出口变更为: $net_type"
                
                local chains="fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"
                for chain in $chains; do
                    remove_block_rules "filter" "$chain" "ipv4"
                    remove_block_rules "filter" "$chain" "ipv6"
                done
                
                update_hosts &
                
                # 延迟10秒后，网络稳定下来，检查一次 FCM 是否成功按照新 Hosts 连接
                ( sleep 10; log_fcm_info ) &
            fi
        fi
    done
}
