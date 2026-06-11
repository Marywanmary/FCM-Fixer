#!/system/bin/sh

# ============================================================
# FCM-Fixer 安装脚本
# 在 Magisk/KernelSU/APatch 安装时执行
# 功能：
#   1. 提示用户按音量键选择 hosts 类型（双栈/IPv4）
#   2. 下载对应的 hosts 文件到模块目录
#   3. 记录安装日志到 /data/adb/box/run/fcm_fixer_install.log
# ============================================================

# 模块目录（安装时脚本所在目录）
MODDIR=${0%/*}

# 加载核心函数库（注意：此时 common.sh 尚未被复制到模块目录？）
# 在 customize.sh 中，当前目录就是模块的临时目录，可以直接引用
. ${MODDIR}/common.sh

# 重定向所有输出到安装日志（同时显示在 UI 上）
init_log_dir
exec > "$INSTALL_LOG" 2>&1

echo "[$(date)] ========== FCM-Fixer 开始安装 =========="

# 1. 等待音量键选择 hosts 类型
wait_for_volume_key
choice=$?

# 2. 根据选择下载 hosts 并写入模块目录
case $choice in
    1)
        echo "[$(date)] 用户选择：双栈 hosts（IPv4+IPv6）"
        install_hosts_to_module "dual" "$MODDIR"
        ;;
    2)
        echo "[$(date)] 用户选择：IPv4 hosts"
        install_hosts_to_module "ipv4" "$MODDIR"
        ;;
    *)
        echo "[$(date)] 默认选择：双栈 hosts"
        install_hosts_to_module "dual" "$MODDIR"
        ;;
esac

if [ $? -eq 0 ]; then
    echo "[$(date)] ✅ Hosts 安装成功"
else
    echo "[$(date)] ❌ Hosts 安装失败，请检查网络后重试"
    # 失败时不中止安装，仅提示
fi

# 3. 设置模块文件权限（Magisk 标准）
set_perm_recursive $MODPATH/system/bin 0 0 0755 0755 2>/dev/null
set_perm $MODPATH/system/etc/hosts 0 0 0644 2>/dev/null

# 4. 安装完成提示（会显示在刷机界面）
ui_print ""
ui_print "✅ FCM-Fixer 安装完成"
ui_print "📁 日志位置: /data/adb/box/run/"
ui_print "   - 安装日志: fcm_fixer_install.log"
ui_print "   - 清理日志: fcm_fixer_clean.log"
ui_print "   - 监控日志: fcm_fixer.log"
ui_print ""
ui_print "🔄 请重启手机使模块生效"

echo "[$(date)] ========== 安装结束 =========="
