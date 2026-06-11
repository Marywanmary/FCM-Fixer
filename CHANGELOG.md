# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.4] - 2026-06-12
### Added
- **全新彩色分级日志系统**：将日志规范化拆分为 `INFO`, `WARN`, `ERROR`, `SUCCESS`, 和 `MATCH` 级别，引入标准时间戳、Emoji 状态标识和终端 ANSI 颜色高亮代码，使查看日志和排错更加直观。
- **FCM 流量真实性命中校验（核心特性）**：新增 `check_fcm_hosts_hit` 机制。脚本在运行及检测网络时，会自动提取系统底层目标端口为 FCM 专属通道（5228/5229/5230）且处于 `ESTABLISHED` 状态的活跃 TCP 连接，抓取其物理对端 IP 并与模块挂载的 Hosts 规则进行强比对。若完美匹配，将高亮打印 `[🎯 MATCH]` 日志。可以彻底用来查验当前的 FCM 流量是否真正享受到了优选 Hosts 的红利，抑或是被其余代理软件接管。

### Changed
- 重构了 `service.sh` 和 `action.sh` 的代码框架，使其完全融入全新的彩色日志框架中，使模块从开机引导到手动触发拥有完全一致的日志表现。

## [v1.0.3] - 2026-06-12
### Added
- **网络切换深度解析日志**：当设备在 Wi-Fi、移动数据（4G/5G）之间发生物理切换或遭遇断网重连时，日志（`fcm_fixer.log`）将精准打印出当前主网络出口的具体类型，并标注当前的物理网卡接口（例如 `wlan0`, `rmnet_data0`, `tun0`）。

### Changed
- **彻底重构网络监视器守护进程**：废弃了传统的传统 `sleep` 轮询查询方式，改用 Linux 底层的 `ip monitor route` 内核级路由表变动事件驱动机制。当无网络波动时，进程处于内核级挂起休眠状态，**实现零耗电、零 CPU 占用**，且能完美规避国产系统对后台高频轮询脚本的激进查杀。
- **新增防抖动（Debounce）冷却机制**：设置 10 秒缓冲，避免设备在信号极差、网络频繁闪断时高频重复清理防火墙及疯狂下载 Hosts。

## [v1.0.2] - 2026-06-11
### Added
- **刷入过程可视化**：在 Magisk / KernelSU / APatch 管理器内本地刷入该模块时，安装界面将实时回显网络连通状态以及 FCM 优选 Hosts 的实时下载、配置进度反馈，使用户能够明确知道安装时 Hosts 是否成功落地。
- **独立的 Hosts 日志系统**：将原本与状态混写的日志剥离，新增 `hosts.log` 和 `hosts_old.log` 专属于记录当前生效的完整 Hosts 文本内容。
- **防延迟下发机制**：在 `service.sh` 开机引导中增加了对 `sys.boot_completed=1` 的前置等待，并在初始化清理完成后，在后台常驻一个 30 秒后的复查小进程，完美防止 ColorOS 等系统在开机后期延迟补发 `REJECT` 防火墙规则。

## [v1.0.1] - 2026-06-11
### Added
- 初始版本发布，由原项目 `ColorOS-Google-Firewall-Fixer` 架构 Fork 并全面重构。
- **Systemless 无系统修改挂载**：通过在模块目录动态建立 `system/etc/hosts`，借助各大 Root 管理器的底层挂挂载特性，完美绕过现代 Android 系统 `system` 分区只读的限制。
- **双栈按键交互安装**：支持在刷入时通过音量键捕捉用户意图。按下 [音量+] 安装双栈 (IPv4/v6) Hosts，按下 [音量-] 安装仅 IPv4 Hosts，无操作 10 秒自动超时回退至双栈。
- **日志路径与 Box 共享对齐**：为了方便统一化管理，默认日志存储路径设置为与 Box 共享的 `/data/adb/box/run/fcm_fixer.log`。每次重启后自动将上一届日志更名为 `_old`。
- 集成了开机自动截取 Google 核心 `GcmService` 连接端点、状态、网络报错等诊断数据（FCM Diagnostics）的功能。
