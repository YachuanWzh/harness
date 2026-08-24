# Changelog

本文件记录 Superharness 的用户可见变化，版本号与 Claude Code、flavor-code 两侧插件清单保持一致。

## [2.2.0] - 2026-08-24

### 新增
- flavor-code 1.2.20+ 原生支持组合 Skill：`go` 可以通过宿主 `Skill` 工具加载 `writing-plans`、`test-driven-development`、`systematic-debugging` 等完整子 Skill
- flavor-code 侧支持 Claude 风格 `$ARGUMENTS` 参数展开，`/go <目标>` 与 `/light <目标>` 不再在 Skill 正文中保留未展开宏
- Flavor 插件清单与 Claude Code 插件版本统一为 2.2.0

### 修复
- SessionEnd 改为仅记录 checkpoint，保留 `.current-task`，使跨会话冷启动续跑成立
- SubagentStop 按 flavor-code 的 `status`/`error` 载荷记录真实失败、取消和错误详情
- Flavor trace 改为操作系统追加写，不再读取并整体覆盖历史流水；原子状态写入使用唯一临时文件并清理残留
- 修正 Hook 数量、Flavor 兼容要求和 Skill 组合语义的 README/安装器说明
- 修正 PowerShell 测试中“禁止派发子代理”规则的自相矛盾文本断言
- 脑图服务器默认交由操作系统分配空闲端口，消除随机高端口碰撞导致的间歇性启动超时

### 测试
- 新增 SessionEnd 续跑指针保留、SubagentStop 失败载荷和 Flavor Hook 常量更新测试

## [2.1.0] - 2026-08-10

- 引入 `light` 轻量工作流、Ralph 可续跑状态、双宿主安装和跨平台脚本。
