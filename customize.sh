#!/system/bin/sh

ui_print "*****************************************"
ui_print "* 本项目基于ColorOS-Google-Firewall-Fixer *"
ui_print "* 和 fcm-hosts-next/cagedbird043 *"
ui_print "* 修复魔改OS拦截，提供稳定的 FCM 长连接 *"
ui_print "*****************************************"
ui_print ""

# ==========================================
# 音量键精确直控逻辑 (10 秒自动默认)
# ==========================================
ui_print "========================================="
ui_print "请选择 FCM 网络模式："
ui_print "[音量 +] : 双栈模式 (Dual-Stack) -> 默认"
ui_print "[音量 -] : 仅 IPv4 (IPv4 Only)"
ui_print "========================================="
ui_print "* (10 秒无操作将自动安装默认 双栈模式)"
ui_print ""

rm -f $TMPDIR/events.log
getevent -ql > $TMPDIR/events.log 2>/dev/null &
EVENT_PID=$!

CHOICE=1 # 默认 1=双栈
END_TIME=$(( $(date +%s) + 10 ))

while [ $(date +%s) -lt $END_TIME ]; do
    if [ -s $TMPDIR/events.log ]; then
        KEY=$(tail -n 1 $TMPDIR/events.log | awk '{print $4}')
        
        if [ "$KEY" = "KEY_VOLUMEUP" ]; then
            CHOICE=1
            ui_print "-> 您按下了 [音量 +]，已确认：双栈模式！"
            break
        elif [ "$KEY" = "KEY_VOLUMEDOWN" ]; then
            CHOICE=2
            ui_print "-> 您按下了 [音量 -]，已确认：仅 IPv4 模式！"
            break
        fi
    fi
    sleep 0.2
done

kill $EVENT_PID 2>/dev/null
rm -f $TMPDIR/events.log

if [ $(date +%s) -ge $END_TIME ]; then
    ui_print "-> 10秒倒计时结束，已自动确认默认选项：双栈模式！"
fi

# ==========================================
# 配置文件名及下载源
# ==========================================
if [ $CHOICE -eq 1 ]; then
  FILE="fcm_dual.hosts"
else
  FILE="fcm_ipv4.hosts"
fi

MIRRORS="
https://fcm-hosts.cagedbird.cn/$FILE
https://github.boki.moe/https://raw.githubusercontent.com/cagedbird043/fcm-hosts-next/main/$FILE
"

# ==========================================
# 构建 Systemless Hosts
# ==========================================
mkdir -p $MODPATH/system/etc
echo "127.0.0.1 localhost" > $MODPATH/system/etc/hosts
echo "::1 ip6-localhost" >> $MODPATH/system/etc/hosts
echo "" >> $MODPATH/system/etc/hosts

SUCCESS=0
for URL in $MIRRORS; do
    ui_print "- 尝试源: $(echo $URL | awk -F/ '{print $3}')"
    sed -i '/google/d' $MODPATH/system/etc/hosts 2>/dev/null
    curl -s -L --connect-timeout 5 --max-time 10 "$URL" >> $MODPATH/system/etc/hosts
    
    if grep -q "google" "$MODPATH/system/etc/hosts"; then
        SUCCESS=1
        ui_print "- Hosts 规则合并成功！"
        break
    else
        ui_print "  x 下载超时或无效，切换节点..."
    fi
done

if [ $SUCCESS -eq 0 ]; then
    ui_print "! 所有镜像源访问失败，请检查网络。"
    abort "! 刷入中止"
fi

# ==========================================
# 权限与收尾
# ==========================================
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/system/etc/hosts 0 0 0644

ui_print "- 模块安装完成！重启后生效。"
