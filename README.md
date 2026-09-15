## 项目说明
##### 本项目基于https://github.com/CHIZI-0618/ColorOS-Google-Firewall-Fixer 和 https://github.com/cagedbird043/fcm-hosts-next
##### 清除国产魔改OS对Google系服务联网的 iptables 拦截规则，使系统正常访问 Google 系服务。
##### 并使用自动维护 FCM 优选 Hosts，给 Android / microG / Google Play services 提供更稳定的 FCM 长连接入口。


###### 至v15，运行基本良好，如无问题暂时不再更新。

请作为高级 Android 系统与 KernelSU 模块开发专家，为我编写一个专门用于解禁国内手机厂商对 GMS/FCM 限制的 KernelSU 模块代码及目录结构。

模块需满足以下核心要求：

系统环境改造：使用 /system/etc/sysconfig 注入 XML 白名单，将 GMS/GSF 设为免休眠、免流量限制。

深度厂商定制解封：在 service.sh 中加入针对 MyOS、HyperOS、ColorOS、OriginOS 的定制解封代码（如修改 system settings 或执行特定 dumpsys 命令）。

网络路由剥离：不使用 iptables 干预流量，网络路由纯净，并在说明中提供配套的 Mihomo/Clash YAML 分流规则模板（处理 5228-5230 端口及 FCM 直连/优选节点）。

心跳保活机制：在 service.sh 中使用轻量级的 Shell 广播循环（定时发送 MCS_HEARTBEAT），废弃 SQLite 修改方案，确保抗云端覆盖且稳定。

SELinux 策略：必须包含完整的 sepolicy.rule，确保在 Android 13/14+ 环境下，service.sh 有足够权限执行 am、pm、dumpsys 和修改系统属性。

请直接输出包含 module.prop、service.sh、sepolicy.rule 以及 sysconfig.xml 的完整代码，并简要说明打包与安装注意事项。

***************************************************************************
终极提示词 (直接复制使用)
为了让 AI 或开发人员直接输出符合上述所有设想的“生产级”代码，请使用以下整理好的终极提示词：

请作为高级 Android 系统底层与 KernelSU 模块开发专家，为我编写一个解决国内手机厂商对 GMS/FCM 限制的“事件驱动型” KernelSU 模块代码及目录结构。

背景要求：必须解决夜间深度休眠断流、公共 Wi-Fi (Captive Portal) 误触惩罚、多用户(炼妖壶)分身漏网、代理软件被杀，以及息屏断网等日常高频痛点。

模块代码需严格包含以下架构逻辑：

1. post-fs-data.sh (系统底层篡改):

挂载包含 GMS、GSF，以及常用代理软件（如 Clash, NekoBox, v2rayNG）的系统电池/流量白名单 (sysconfig.xml)。

首次执行 SQLite3 注入，修改 /data/data/com.google.android.gsf/databases/gservices.db，将 mtalk 相关的 Wi-Fi 和移动网络心跳间隔键值强制设定为 240000 毫秒。

2. service.sh (低功耗事件守卫):

反息屏断网：通过 settings put 强行关闭各大厂商（如小米、OPPO、vivo）的息屏待机优化和智能省电全局开关。

云控防覆盖守卫：使用 inotifyd 监听 gservices.db 文件的变化（w 或 m 事件），一旦被 Google 云控覆盖，立即触发 SQLite3 重新注入，禁止使用 sleep 死循环。

多用户防火墙清理与安全心跳：编写一个函数，当网络状态变为 VALIDATED (通过 dumpsys connectivity 判断) 时：

遍历所有活跃 User (User 0, 10 等)，获取所有 GMS 的 UID。

清理底层 iptables / nftables 中针对这些 UID 的 DROP/REJECT 规则。

向所有 User Space 发送 MCS_HEARTBEAT 广播 (am broadcast --user ALL)。

3. sepolicy.rule (SELinux 合规):

必须赋予 su 域读写 GMS 内部 data 目录、执行 SQLite、修改 settings_global、执行 dumpsys，以及操作 iptables 的必要 SELinux 权限。

请直接输出 module.prop、post-fs-data.sh、service.sh、sepolicy.rule、system/etc/sysconfig/gms_proxy_whitelist.xml 的完整代码。并请在末尾附上一段建议配合使用的 Clash / sing-box 分流规则（处理 5228-5230 FCM 端口直连与代理的回退逻辑）。

