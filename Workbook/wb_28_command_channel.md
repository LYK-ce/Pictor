# wb_28_command_channel

## meta
- task: task_28_command_channel
- start: 2026-09-08
- status: Godot 侧实现完成，待 Rust .so 编译 + 真机验证

## 目标
- Godot 侧命令通道：LineEdit 回车 → EventBus.user_command_requested → kernel_bridge 转发 kernel.send_user_command → ACK 走 log_message

## 方案（已定稿）
- D1 LineEdit 单行回车提交（text_submitted），无按钮
- D2 EventBus 新增 user_command_requested(command_line: String)
- D3 ACK 回显复用 log panel（log_message），不改 log_panel
- D4 无预设命令按钮，纯手动输入
- D5 llm 切本地不在本范围（人类手动改 .config/pictor_config.cfg）
- Rust 侧 send_user_command 已实现（Orion 仓库 pleiades-terminal/src/lib.rs，未提交）

## 涉及文件
- src/event_bus/event_bus.gd（+1 信号）
- src/kernel/kernel_bridge.gd（+转发方法 + 订阅）
- src/ui/command_channel/command_channel.gd（新建）
- src/ui/command_channel/command_channel.tscn（TextEdit→LineEdit + 挂脚本）

## 风险 / 先决
- 🔴 .gdextension 库名不匹配（libpleiades_terminal.so vs 磁盘 libpictor_kernel.so）→ 内核加载不起来，实测前需修
- 🟡 Rust send_user_command 未提交、未编译进 .so
