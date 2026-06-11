#!/system/bin/sh

# ==========================================
# 1. 标题头
# ==========================================
ui_print "*****************************************"
ui_print "* 本项目基于ColorOS-Google-Firewall-Fixer/CHIZI-0618 *"
ui_print "* 和fcm-hosts-next/cagedbird043 *"
ui_print "* 修复国产魔改OS中拦截 Google Play 商店和 Google Play 服务联网的 iptables 规则 *"
ui_print "* 提供更稳定的 FCM 长连接入口 *"
ui_print "*****************************************"
ui_print ""

# ==========================================
# 2. 交互式菜单 (仅音量键切换，10秒无操作自动确认)
# ==========================================
ui_print "========================================="
ui_print "请选择 FCM 网络模式："
ui_print "[ 1 ] 双栈模式 (Dual-Stack) - 默认"
ui_print "[ 2 ] 仅 IPv4 (IPv4 Only)"
ui_print "========================================="
ui_print "* [音量 + / -] : 切换模式"
ui_print "* 停止按键 10 秒后将自动确认当前选项"
ui_print ""

rm -f $TMPDIR/events.log
getevent -ql > $TMPDIR/events.log 2>/dev/null &
EVENT_PID=$!

CHOICE=1
END_TIME=$(( $(date +%s) + 10 ))

ui_print "-> 当前选择: 模式 $CHOICE (10秒后自动确认)"

while [ $(date +%s) -lt $END_TIME ]; do
    if [ -s $TMPDIR/events.log ]; then
        KEY=$(tail -n 1 $TMPDIR/events.log | awk '{print $4}')
        
        if [ "$KEY" = "KEY_VOLUMEDOWN" ] || [ "$KEY" = "KEY_VOLUMEUP" ]; then
            if [ "$KEY" = "KEY_VOLUMEDOWN" ]; then
                CHOICE=$((CHOICE + 1))
                [ $CHOICE -gt 2 ] && CHOICE=1
            else
                CHOICE=$((CHOICE - 1))
                [ $CHOICE -lt 1 ] && CHOICE=2
            fi
            ui_print "-> 切换至: 模式 $CHOICE (10秒后自动确认)"
            > $TMPDIR/events.log
            END_TIME=$(( $(date +%s) + 10 ))
            sleep 0.3
        fi
    fi
    sleep 0.2
done

kill $EVENT_PID 2>/dev/null
rm -f $TMPDIR/events.log

ui_print "- 已自动确认选择！"

# ==========================================
# 3. 选择对应的 hosts 文件名及下载源 (仅双栈/IPv4)
# ==========================================
if [ $CHOICE -eq 1 ]; then
  MODE="双栈模式"
  FILE="fcm_dual.hosts"
else
  MODE="仅 IPv4"
  FILE="fcm_ipv4.hosts"
fi

ui_print ""
ui_print "- 最终配置: [$MODE]"

# 两个可靠源：官网 + github.boki.moe 反代
MIRRORS="
https://fcm-hosts.cagedbird.cn/$FILE
https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/$FILE
"

# ==========================================
# 4. 构建 Systemless Hosts（自动重试）
# ==========================================
mkdir -p $MODPATH/system/etc
echo "127.0.0.1 localhost" > $MODPATH/system/etc/hosts
echo "::1 ip6-localhost" >> $MODPATH/system/etc/hosts
echo "" >> $MODPATH/system/etc/hosts

SUCCESS=0

for URL in $MIRRORS; do
    ui_print "- 尝试源: $(echo $URL | awk -F/ '{print $3}')"
    
    # 清除上一次可能失败的残留
    sed -i '/google/d' $MODPATH/system/etc/hosts 2>/dev/null
    
    curl -s -L --connect-timeout 5 --max-time 10 "$URL" >> $MODPATH/system/etc/hosts
    
    if grep -q "google" "$MODPATH/system/etc/hosts"; then
        SUCCESS=1
        ui_print "- Hosts 规则下载并合并成功！"
        break
    else
        ui_print "  x 下载失败或内容无效，切换下一节点..."
    fi
done

if [ $SUCCESS -eq 0 ]; then
    ui_print "! 所有镜像源均访问失败，请检查网络后重试。"
    abort "! 刷入中止"
fi

# ==========================================
# 5. 权限与收尾
# ==========================================
ui_print "- 配置系统防火墙清道夫 (service.sh)..."
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/system/etc/hosts 0 0 0644

ui_print "- 模块 v1.0.2 安装完成！重启后生效。"
