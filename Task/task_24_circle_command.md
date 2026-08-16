# Task 24: Circle 命令（环形散布，Pictor 端下发）

> 创建日期：2026-08-16
> 状态：✅ 已实施（代码 + 单测通过，2026-08-16）
> 范围：Pictor 新增 Circle 命令下发——**Z 键进入待命，左键点圆心**，对选中车群发 `type=1`（圆心为世界坐标），复用 Goto 全链路。

---

## 一、背景

- 车端（Orion）`task_18_circle_command` 已实施（`Mission::Circle` + `MISSION_CIRCLE: u8 = 1`，2026-08-16 代码 + 单测通过）。
- 协议：`Workspace/Orion/docs/design_doc/orion_protocol.md` §3.5 —— `ORION_TASK_SET` mission `type=1` = Circle，`x/y` = 圆心（世界坐标，米）；**半径写死 0.5m，不进协议**。
- 散布：`Workspace/Orion/docs/design_doc/multi_robot_control.md` §4.3 —— 环 `ring_cells(2)` 共 16 格，车按 peer_id 字节升序排序后均匀铺开 `idx·len/N`，零通信、零协商。
- Pictor 现状：仅有 `MISSION_TYPE_GOTO := 0`（右键触发），无 Circle 下发能力。

## 二、命令语义（车端文档摘要）

| 项 | 值 |
|---|---|
| mission type | `1`（`MISSION_TYPE_CIRCLE`），`x/y` = 圆心（米） |
| 半径 | 0.5m，车端写死（`ring_cells(2)`），**不进帧** |
| 单车（member_count=1） | 落环第一个位置（正北） |
| 群发（>1） | 车按 peer_id 字节升序排序，环上均匀铺开 |
| 第一版 | 到达即停、不朝圆心 |
| 与 Goto 关系 | **完全同构**，仅 type 值（0→1）与触发方式不同 |

## 三、路径梳理结论（与 Goto 同构，下游零改动）

```
Goto   ：右键 → AutoHandler._unhandled_input
           → CoordUtils.game_to_tile → tile_to_real
           → MessageBuilder.build_auto_push_goto(x, y)      # type=0
           → EventBus.cmd_send.emit(selected_ids, cmd)
           → KernelBridge 填 members → Build_Cmd → send_command

Circle ：Z 键 → _pending_action = CIRCLE
           → 左键点圆心 →（同上坐标转换）
           → MessageBuilder.build_auto_push_circle(x, y)    # type=1
           → EventBus.cmd_send.emit(selected_ids, cmd)
           → KernelBridge 填 members → Build_Cmd → send_command   ← 完全复用
```

**零改动**：`kernel_bridge.gd`、`orion_frame.gd`、`message_parser.gd`、`event_bus.gd`、地图/渲染/相机/面板全链路。

## 四、方案设计

### A. 触发方式（2026-08-16 用户定稿）

- **Z 键**进入 Circle 待命（弃用 A：`input_handler.gd` 的 `KEY_A: "spin_left"` 已被手动模式占用，二者互斥难处理）
- 待命期间：**左键点地面 = 圆心** → 下发；**右键 / Esc = 取消**
- 复用 `auto_handler.gd` 已有的 `PendingAction` 机制——`_execute_pending()` 空函数本就是为此留的扩展点（注释「PATROL 等瞬态命令的扩展点」）

### B. 高亮

- 复用 `EventBus.goto_issued(x, y)`（InputIndicator 高亮框），圆心处显示高亮。不新增信号，改动最小。
  - 备选：新增 `circle_issued` 信号（语义更清晰，但多改 `event_bus.gd` + `input_indicator.gd` 两处，首版不做）。

### C. 归一化集中

- 新增 `ProtocolDef.Mission_Type_From(t) -> int` 静态函数（"goto"→0 / "circle"→1 / 未知字符串→0），
  `message_builder._Normalize_Mission_Type` 与 `orion_messages.Encode_Task_Set` 的字符串归一化统一委托之，避免两处漂移。

## 五、涉及文件（6 个）

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `src/websocket/protocol/protocol_def.gd` | 改 | 加 `MISSION_TYPE_CIRCLE := 1` + `Mission_Type_From()` |
| 2 | `src/websocket/protocol/message_builder.gd` | 改 | 加 `build_auto_push_circle()` + 归一化支持 "circle" |
| 3 | `src/websocket/protocol/orion_messages.gd` | 改 | `Encode_Task_Set` 字符串 type 归一化支持 "circle" |
| 4 | `src/control/auto_handler.gd` | 改 | Z 键 → CIRCLE 待命；`_execute_pending` 实现 circle 分支 |
| 5 | `src/util/llm.gd` | 改 | SYSTEM_PROMPT 加 circle 类型 |
| 6 | `src/test/test_orion_protocol.gd` | 改 | 新增 circle 单测（build + 编解码 roundtrip） |

## 六、详细实施步骤

### 步骤 1：`protocol_def.gd` — 常量 + 归一化 helper

改前（`ORION_TASK_SET mission type` 段）：

```gdscript
const MISSION_TYPE_GOTO := 0
```

改后：

```gdscript
const MISSION_TYPE_GOTO := 0
const MISSION_TYPE_CIRCLE := 1   # Task 24：环形散布（x/y = 圆心，半径 0.5m 车端写死）

## 字符串/数字 → mission type 整数（"goto"→0，"circle"→1；未知字符串→0）
static func Mission_Type_From(t) -> int:
	if t is String:
		match t.to_lower():
			"circle": return MISSION_TYPE_CIRCLE
			_: return MISSION_TYPE_GOTO
	return int(t)
```

### 步骤 2：`message_builder.gd` — 构造器 + 归一化

改前 `_Normalize_Mission_Type`：

```gdscript
static func _Normalize_Mission_Type(t) -> int:
	if t is String:
		return ProtocolDef.MISSION_TYPE_GOTO
	return int(t)
```

改后（委托集中）：

```gdscript
static func _Normalize_Mission_Type(t) -> int:
	return ProtocolDef.Mission_Type_From(t)
```

新增（放在 `build_auto_push_goto` 旁）：

```gdscript
## Circle 群发：x/y = 圆心（世界坐标，米）；半径车端写死 0.5m 不进协议
static func build_auto_push_circle(x: float, y: float) -> Dictionary:
	return {
		"msgid": ProtocolDef.MSGID_TASK_SET,
		"missions": [{"type": ProtocolDef.MISSION_TYPE_CIRCLE, "x": x, "y": y}],
	}
```

### 步骤 3：`orion_messages.gd` — Encode_Task_Set 字符串归一化

改前（`Encode_Task_Set` 内 mission type 归一化）：

```gdscript
var mt = mi.get("type", ProtocolDef.MISSION_TYPE_GOTO)
if mt is String:
	mt = ProtocolDef.MISSION_TYPE_GOTO
```

改后：

```gdscript
var mt = mi.get("type", ProtocolDef.MISSION_TYPE_GOTO)
if mt is String:
	mt = ProtocolDef.Mission_Type_From(mt)
```

### 步骤 4：`auto_handler.gd` — Z 键触发 + 执行

（a）枚举加 `CIRCLE`：

```gdscript
enum PendingAction { NONE, PATROL, CIRCLE }
```

（b）`_unhandled_input` 顶部加键盘分支（插在 `if not event is InputEventMouseButton: return` 之前）：

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	# Z 键进入 Circle 待命；Esc 取消待命
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_Z:
				_pending_action = PendingAction.CIRCLE
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ESCAPE and _pending_action != PendingAction.NONE:
				_pending_action = PendingAction.NONE
				get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton:
		return
	# ... 后续鼠标逻辑不变 ...
```

（c）实现 `_execute_pending`（当前为空 `pass`）：

```gdscript
func _execute_pending(_mb: InputEventMouseButton) -> void:
	if _pending_action != PendingAction.CIRCLE:
		return  # PATROL 等其它瞬态命令扩展点
	if app_state.selected_ids.is_empty():
		return
	var mouse_pos := get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_pos)
	var real := CoordUtils.tile_to_real(tile.x, tile.y)
	EventBus.cmd_send.emit(app_state.selected_ids, MessageBuilder.build_auto_push_circle(real.x, real.y))
	EventBus.goto_issued.emit(real.x, real.y)  # 圆心高亮（复用 Goto 高亮框）
```

> 说明：现有 `_unhandled_input` 的待命分支已经实现「左键 → `_execute_pending` → 复位 NONE；右键/其它 → 取消」，Z 键只需置位 `_pending_action = CIRCLE` 即可，鼠标分支零改动。

### 步骤 5：`llm.gd` — SYSTEM_PROMPT 加 circle

改前说明段：`type 目前仅支持 "goto"（前往目标点）`。

改后（任务协议 + 说明）：

```
{"type": "goto", "x": 米, "y": 米}
{"type": "circle", "x": 圆心x米, "y": 圆心y米}

说明：
- type 支持 "goto"（前往目标点）与 "circle"（围绕圆心环形散布）
- x / y 为全局世界坐标，单位米
- 支持一次输出多条任务（JSON 数组，按顺序执行：先去第一个目标点，再去下一个）
- 无法映射的输入输出空数组 []
```

### 步骤 6：`test_orion_protocol.gd` — 单测

新增 `_test_circle_task_set`（纳入测试入口）：

- `ProtocolDef.Mission_Type_From("circle") == 1`、`("goto") == 0`、`("CIRCLE") == 1`（大小写不敏感）、`("xx") == 0`
- `MessageBuilder.build_auto_push_circle(1.5, 2.5)` → `missions[0].type == 1`、`x == 1.5`、`y == 2.5`
- `Encode_Task_Set` roundtrip：type=1 的 mission 编解码后 type/x/y 保持（9 字节布局不变）

## 七、设计决策记录

| 项 | 决定 |
|---|---|
| 触发键 | ✅ **Z**（A 被手动 `spin_left` 占用，弃用） |
| 待命状态 | ✅ 复用 `PendingAction`（新增 `CIRCLE`），左键执行 / 右键或 Esc 取消 |
| 高亮 | ✅ 复用 `goto_issued`（圆心高亮），不新增信号 |
| 群发 | ✅ 复用 `cmd_send(selected_ids)`，KernelBridge 自动填 members（零改动） |
| 半径 | ✅ 不进协议（车端写死 0.5m） |
| 归一化 | ✅ 集中到 `ProtocolDef.Mission_Type_From()` |
| LLM | ✅ 顺手支持 "circle"（成本极低） |

## 八、测试

| 用例 | 输入 | 期望 |
|---|---|---|
| 构造 | `build_auto_push_circle(1.5, 2.5)` | type=1, x=1.5, y=2.5 |
| 归一化 | "circle"/"CIRCLE"/"goto"/未知 | 1/1/0/0 |
| 编解码 | Encode→Decode type=1 | type/x/y 保持 |
| 群发 | 选中 2 车 + Z→左键 | 单条 TASK_SET，members 含 2 车，车端各自围圈 |
| 取消 | Z→右键 / Esc | 不下发 |

**实车联调（后续）**：4 车围圈，验证落点、无碰撞、到达即停不转车头。

## 九、依赖

- 车端 Orion `task_18_circle_command`（已实施，`MISSION_CIRCLE=1` 车端已识别）
- **无同批升级压力**：type=1 为纯新增，旧 Pictor 只发 type=0，不影响既有 Goto / 群发

## 十、验证方法

- 单测：`godot --headless --path . -s src/test/test_orion_protocol.gd`（**17 项 ALL PASS**，含 `PASS circle_task_set`）
- 主场景冒烟：`godot --headless --path . --quit-after 90 src/main/main.tscn`（`[Main] ready: 7 children`，无脚本错误）
- 联调：连车端，Z→左键围圈，观察落点

## 十一、实施状态（2026-08-16）

- [x] `protocol_def.gd`：`MISSION_TYPE_CIRCLE := 1` + `Mission_Type_From()`
- [x] `message_builder.gd`：`build_auto_push_circle()` + 归一化委托
- [x] `orion_messages.gd`：`Encode_Task_Set` 字符串归一化
- [x] `auto_handler.gd`：Z 键待命 + `_execute_pending` circle 分支
- [x] `llm.gd`：SYSTEM_PROMPT 加 circle
- [x] `test_orion_protocol.gd`：`_test_circle_task_set`
- [x] 单测 + 冒烟验证通过
- [x] `docs/orion_protocol.md` §3.5 同步 Circle
- [x] `Architecture/architecture.md` 重写对齐 KernelBridge + Orion + Circle
- [ ] 实车联调（4 车围圈，待真车可用）
