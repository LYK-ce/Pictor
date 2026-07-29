# Task 15: Protocol 提取

## 目标

将 WebSocket 协议收发集中到 `src/websocket/protocol/protocol.gd`，各组件通过 Protocol 静态方法操作，不再裸拼 JSON。

## 设计决策

### 目录

```
src/websocket/protocol/
└── protocol.gd       ← 收发编码，静态方法
```

### 编码方法（PC → 小车）

```gdscript
class_name Protocol
extends RefCounted

static func mode_switch_to_auto()   → {"cmd":"mode","action":"switch_to_auto"}
static func mode_switch_to_manual() → {"cmd":"mode","action":"switch_to_manual"}
static func manual(action, speed)   → {"cmd":"manual","action":...,"speed":...}
static func auto_goto(x, y)         → {"cmd":"auto","action":"push","missions":[...]}
static func auto_cancel()           → {"cmd":"auto","action":"cancel"}
```

### 解码方法（小车 → PC）

```gdscript
static func parse(text: String) → Dictionary  # {type, data}
```

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/websocket/protocol/protocol.gd` | 新建 | 集中编码/解码 |
| `src/control/input_handler.gd` | 修改 | 改用 `Protocol.manual(action, speed)` |
| `src/control/control_master.gd` | 修改 | 改用 `Protocol.auto_goto(x, y)` |
| `src/ui/WebSocket/vehicle_panel.gd` | 修改 | 改用 `Protocol.mode_switch_to_manual/auto()` |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 修改 | 改用 `Protocol.mode_switch_to_manual()` |
| `src/websocket/websocket_client.gd` | 修改 | 改用 `Protocol.parse()` 解码 |
| `src/renderer_2d/input_indicator.gd` | 检查 | 已无发送逻辑，无需改动 |
| `src/test/test_ws_server.gd` | 修改 | 收发改用 Protocol |

## 实施步骤

### 1. 创建 Protocol 静态类
- [ ] 新建 `src/websocket/protocol/` 目录
- [ ] 创建 `protocol.gd`，含所有编码/解码静态方法

### 2. 组件接入
- [ ] `input_handler.gd`：`{"cmd":"manual"...}` → `Protocol.manual(action, 50)`
- [ ] `control_master.gd`：Goto 点击 JSON → `Protocol.auto_goto(x, y)`
- [ ] `vehicle_panel.gd`：mode 切换 → `Protocol.mode_switch_to_manual/auto()`
- [ ] `vehicle_panel_manager.gd`：释放时 mode 命令 → `Protocol.mode_switch_to_manual()`
- [ ] `websocket_client.gd`：`_on_message` 解码 → `Protocol.parse(text)`

### 3. 验证
- [ ] 手动/自动指令格式正确
- [ ] test_ws_server 收发正常

## 依赖

- Task 14 (Goto)
- Task 12 (Control)

## 状态

- [ ] 1. 创建 Protocol 静态类
- [ ] 2. 各组件接入 Protocol
- [ ] 3. 验证测试
