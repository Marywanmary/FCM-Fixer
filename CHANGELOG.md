# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.6] - 2026-06-12
### Fixed
- **修复 Systemless 挂载在开机后期偶发性失效的底层 Bug**：
  1. 废除了 `common.sh` 内部更新文件时传统的 `mv -f` 指令，完全重构为 `cat >` 覆盖写入流。确保模块内 `hosts` 文件的物理 Inode 节点在运行时绝不发生改变，完美维护了 Magisk/APatch/KernelSU 早期开机时建立的 Systemless 软映射通道。
  2. 修复了刷入模块时因处于离线状态而无法创建占位符的问题。现在 `customize.sh` 会在安装结束时强制生成一个包含标准回环的 hosts 基础镜像。确保 Root 框架在早起引导阶段能无条件为本模块锁定系统级挂载点。
  3. 为 `update_hosts` 加入了主动式动态 `bind mount` 注入器，针对系统级挂载异常提供运行期强制兜底。

## [v1.0.5] - 2026-06-12
### Added
- **真·Hosts 视图反射日志机制**：重构 `hosts.log` 生成逻辑。该文件不再单纯输出模块内部生成的 Hosts 文本，而是跳过所有中间环节，直接对 Android 系统全局运行态的 `/system/etc/hosts` 执行 `cat` 抓取并反射写入日志。同时新增了系统级的 `[挂载检查]` 高亮报警器。当管理器（KernelSU / Magisk / APatch）挂载因系统分区策略失效时，日志会立即打出红色的 `[❌ ERROR]` 警报，成为判定本地挂载状态的绝对事实来源。
- **443 端口降级容灾连接追踪**：增加了对 443 端口 GMS 通信流的捕获能力。当底层专属的 5228-5230 端口遭到运营商、严格防火墙等物理环境阻断，且 FCM 自动降级激活本地 HTTPS 备用通道时，模块仍能完美追踪会话。
- **全机双向套接字穿透追踪（Fake-IP 完美克星）**：针对透明代理中因开启 Fake-IP 导致 GMS 本地连接特征变为 `198.18.x.x` 导致永远“无法匹配”的终极痛点，重构了比对树架构。新增套接字双向穿透：当盲测法判定当前处于 Fake-IP 全局接管状态时，脚本会自动从系统底层反向追踪由 Clash / Mihomo 内核二次向公网发出的直连（DIRECT）真物理 TCP 连接，并将其剥离出进行 Hosts 核对。成功实现了在 Fake-IP 严酷环境下高亮检测 Hosts 优选命中的能力。
- **分流越权智能诊断**：当在 Fake-IP 模式下发现系统触发了 FCM 请求，但代理内核并未向外直连发包时，日志会输出智能诊断提示，指导用户去检查 Clash 规则是否将 `mtalk.google.com` 误分流进了代理节点组。

### Changed
- 规范化升级了 `service.sh` 和 `action.sh` 的全线业务流，使其全部完美融入 `common.sh` 的彩色级日志框架中，全面实现开机引导、手动触发、网络切换日志体验的三元合一。
