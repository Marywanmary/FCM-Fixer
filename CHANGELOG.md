# FCM-Fixer 更新日志

## v1.0.6
**🔥 重大架构升级：**
- **智能省电核心：** 放弃高耗电的 5 秒死循环，引入网络指纹 (Gateway + DNS) 探测，仅在网络切换时精准触发清理。
- **降维打击拦截：** 深度扫描 `filter` 与 `nat` 表，暴力清除魔改系统对 Google 及 FCM 的全量特征拦截与 5228-5230 全局端口阻断。
- **GMS 状态诊断：** 引入 `netcat` 真实 TCP 握手探测与原生 `dumpsys` GCM 内部转储，排错不再盲人摸象 (日志路径: `/data/adb/box/run/fcm_fixer.log`)。
- **兼容性重构：** 彻底修复 EROFS 分区挂载时序问题，增强 Android 底层精简环境下的命令鲁棒性。
- **全系支持：** 完美兼容 Magisk / KernelSU / APatch。

## v1.0.1
- 优化 Hosts 拉取逻辑，集成多重抗封锁镜像源轮询机制。
- 调整交互菜单，提升 IPv4 优先级，增加 10 秒无操作自动选择双栈的防呆功能。
- 增加日志轮替备份机制。

## v1.0.0
- 初版发布。基于 ColorOS-Google-Firewall-Fixer 融合 fcm-hosts-next 优选规则。


