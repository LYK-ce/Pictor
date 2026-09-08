# Task 28: Command Channel（命令通道）

> 创建日期：2026-09-08
> 状态：方案已定（待实现）
> 关联文档：`/Workspace/Orion/Task/task_26_godot_command_channel.md`（Orion 侧 D1–D7）

## 一、目标

让 Pictor（Godot 地面站）能向 `pleiades-terminal`（GDExtension 内核）下发命令字符串（如 `session create xxx` / `api 1` / `webui`），由内核解析后经 `user_cmd_tx` 送入 Core 主循环执行，从而在 Godot 侧启动大模型推理服务（OpenAI 兼容 API）。

Rust 侧 `#[func] send_user_command(command_line: GString) -> GString` **已实现**（Orion 仓库 `pleiades-terminal/src/lib.rs`，未提交）。本任务只做 Godot 侧转发 + UI 接线。

## 二、设计决策（已定稿）

| # | 决策 |
|---|------|
| D1 | UI 用 `LineEdit`（单行），**回车提交**（`text_submitted`），无发送按钮 |
| D2 | 通信走 EventBus：新增信号 `user_command_requested(command_line: String)`，command_channel 与 kernel_bridge 经此解耦 |
| D3 | ACK 回显复用现有 log panel（`EventBus.log_message`），不新做回显区，不改 `log_panel.gd` |
| D4 | 不做预设命令按钮，纯手动输入命令字符串 |
| D5 | llm 切本地不在本任务范围（人类手动改 `.config/pictor_config.cfg`） |
| D6 | Godot 侧只做"转发"，不做解析 / 结构化参数（复用 Rust 侧 `parse_user_command`） |

## 三、数据流

```
LineEdit 回车 (text_submitted)
  → command_channel.gd._on_text_submitted(cmd)
      1. EventBus.log_message.emit("> " + cmd, "info")   # 回显命令
      2. EventBus.user_command_requested.emit(cmd)
  → kernel_bridge.gd._on_user_command_requested(cmd)
      → kernel.send_user_command(cmd)                    # Rust #[func]，同步返回
      → 返回 "OK" / "OK (本地命令)" / "ERR: ..."
      → EventBus.log_message.emit(ack, "info"/"error")   # ACK 进 log panel
```

## 四、涉及文件

| # | 文件 | 改动 |
|---|------|------|
| 1 | `src/event_bus/event_bus.gd` | +1 信号 |
| 2 | `src/kernel/kernel_bridge.gd` | +转发方法 + 订阅信号 |
| 3 | `src/ui/command_channel/command_channel.gd` | 新建 |
| 4 | `src/ui/command_channel/command_channel.tscn` | TextEdit → LineEdit |

## 五、具体改动点

### 5.1 `event_bus.gd`

```gdscript
## 命令通道：用户下发内核命令字符串（如 "session create xxx" / "api 1"）
signal user_command_requested(command_line: String)
```

### 5.2 `kernel_bridge.gd`

- `_ready()` 里：`EventBus.user_command_requested.connect(_on_user_command_requested)`
- 新增方法：

```gdscript
## 命令通道：转发内核命令字符串，ACK 经 log_message 回显到 log panel
func _on_user_command_requested(command_line: String) -> void:
	if not kernel:
		EventBus.log_message.emit("ERR: kernel 未就绪", "error")
		return
	var ack: String = kernel.send_user_command(command_line)
	var level := "error" if ack.begins_with("ERR") else "info"
	EventBus.log_message.emit(ack, level)
```

### 5.3 `command_channel.gd`（新建）

```gdscript
extends PanelContainer

@onready var _input := $LineEdit as LineEdit

func _ready() -> void:
	_input.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(text: String) -> void:
	var cmd := text.strip_edges()
	if cmd.is_empty():
		return
	_input.clear()
	EventBus.log_message.emit("> " + cmd, "info")
	EventBus.user_command_requested.emit(cmd)
```

### 5.4 `command_channel.tscn`

- 把 `TextEdit` 节点换成 `LineEdit`（节点名 `LineEdit`），保留 PanelContainer 布局。

## 六、备注 / 风险

- 🔴 先决条件：`.gdextension` 库名不匹配（`libpleiades_terminal.so` vs 磁盘 `libpictor_kernel.so`）→ 内核加载不起来，需先解决才能实测（Orion task_26 D7 已声明"由人类另行处理"）。
- 🟡 Rust 侧 `send_user_command` 未提交、未编译进 `.so`，实测前需在 Orion 侧提交并重编译。
- 命令是 fire-and-forget：`try_send` 成功只代表"已入队"，不代表执行成功；`quit`/`exit`/`clear` 解析为本地命令，返回 `"OK (本地命令)"`。
