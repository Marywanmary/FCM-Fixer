#!/system/bin/sh

# ============================================================
# FCM-Fixer 安装脚本
# 在 Magisk/KernelSU/APatch 安装时执行
# ============================================================

ui_print "- FCM-Fixer 正在安装..."
ui_print "  功能："
ui_print "    • 清理防火墙中拦截 Google 服务的规则"
ui_print "    • 安装优选 FCM Hosts（首次开机时可选择双栈/IPv4）"
ui_print "    • 实时监控 FCM 连接状态并记录日志"
ui_print ""
ui_print "  兼容性："
ui_print "    • 支持 Magisk / KernelSU / APatch"
ui_print "    • 兼容 EROFS 只读分区（通过 bind mount）"
ui_print ""
ui_print "  首次开机时："
ui_print "    • 等待 10 秒按【音量+】安装双栈 Hosts（推荐）"
ui_print "    • 按【音量-】安装仅 IPv4 Hosts"
ui_print "    • 无操作默认安装双栈 Hosts"
ui_print ""
ui_print "  日志位置："
ui_print "    • 操作日志: /data/adb/modules/fcm-fixer/reject_rules.log"
ui_print "    • FCM 监控: /data/adb/box/run/fcm_fixer.log"
ui_print ""

# 确保 bin 目录权限
set_perm_recursive $MODPATH/system/bin 0 0 0755 0755

ui_print "- 安装完成，重启后生效"
