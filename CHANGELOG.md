# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.2] - 2026-06-11
### Added
- 刷入过程可视化：在 KernelSU / Magisk / APatch 内安装时，界面会直接显示 Hosts 的下载与配置状态。
- 独立的 Hosts 日志系统：新增 `hosts.log` 和 `hosts_old.log`，不再与 FCM 状态日志混写，方便直接查看当前生效的节点 IP。
- 防火墙动态防护机制：增加 `sys.boot_completed` 监听，确保系统启动完毕后再执行清理，并新增 30 秒后的后台二次复查，防止 ColorOS/ZTE 系统在连网后延迟下发 REJECT 规则。

### Changed
- 升级底层逻辑，全面兼容只读 System 分区（Systemless 挂载机制）。
- 优化 `common.sh` 中的文件下载回退逻辑 (cURL 超时后自动回退至 wget)。

## [v1.0.1] - 2026-06-11
### Added
- 初始版本发布。
- 支持通过音量键选择安装 IPv4 优选或双栈 (IPv4/v6) Hosts 模式（默认无操作 10 秒后安装双栈）。
- 统一日志输出路径至 Box 共享目录 `/data/adb/box/run/fcm_fixer.log`。
- 添加对开机自动记录 FCM Diagnostic 和 GcmService 连接状态的支持。
