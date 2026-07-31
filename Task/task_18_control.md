# Task 18: Control 重构

## 目标

之前：单车主状态机，`selected_id` + `mode` 全局切换。
之后：多车独立模式，无全局状态机。

```
之前                               之后
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━
AppState                           AppState
├── selected_id: "A"               ├── selected_ids: [A,B,C]
├── mode: NONE|FOLLOW|GOTO         ├── manual_target: "" | 至多 1 辆
└── 全局状态机                      └── follow_enabled: true|false

操作方式                           操作方式
Goto: 按按钮→进模式→左键点地图      Goto: 右键直接点地图
Follow: 按 Lock Camera→跟车         Follow: 按 Lock Camera→跟 manual_target
多选: 不支持                        多选: Ctrl+点面板
```

## 核心原则

- **Manual 至多 1 辆**：WASD 操控 + Camera 可跟随
- **Auto 命令广播**：Goto / LLM / Voice 发给 `selected_ids` 中所有车
- **两集合互斥**：一辆车不能同时在 Manual（manual_target）和 Auto（selected_ids）中
- **无模式操作**：右键即 Goto，不需要"进入/退出 Goto 模式"

## AppState 最终形态

```gdscript
# src/app_state/app_state.gd
# AppStateResource (Resource) — Autoload 可通过 @export 注入

var selected_ids: Array[String] = []   # Goto/LLM/Voice 广播目标
var manual_target: String = ""          # WASD 操控对象，至多 1 辆
var follow_enabled: bool = false        # Camera 是否跟随 manual_target
```

三个字段的含义和互斥关系：

```
selected_ids           manual_target
    [A, C, D]                ""
         ↑                    ↑
    这些车收到 Goto       WASD 不发任何车

    [A, C]                  "B"
         ↑                    ↑
    这些车收到 Goto       WASD 发给 B，Camera 跟 B

    B 不在 selected_ids 中 —— 互斥
```

移除的字段：`selected_id: String`、`mode: Mode` 枚举、mode setter。

## EventBus 信号变更

### 新增

```gdscript
signal selection_changed(ids: Array[String])
# emit: VehiclePanelManager 处理完多选后
# connect: 暂无（预留，未来 LLM/Voice UI 可能需要）

signal manual_target_changed(id: String)
# emit: VehiclePanelManager 切换 Manual/Auto 后
# connect: Camera（切换跟随目标）、ButtonList（控制 Lock Camera 可用性）、ControlMaster
```

### 移除

```gdscript
# 以下两个信号从 EventBus 中删除：
signal mode_transited(mode: int)           # 无模式架构，不再需要
signal vehicle_control_changed(id: String)  # 被 manual_target_changed 替代
```

### 保留不变

`pose_received`、`map_full_received`、`map_delta_received`、`chunk_updated`、`cells_changed`、`ws_connected`、`ws_connect_requested`、`ws_disconnect_requested`、`vehicle_registered`、`vehicle_unregistered`、`cmd_send`。

## UI 交互

### VehiclePanel 布局

```
┌───────────────────────────────────┐
│  ■ A 车  [x:10.5,y:3.2]  [Auto]   │  ← 蓝色边框 = selected
│  □ B 车  [x:2.1,y:8.7]   [Manual] │  ← 灰色 = unselected；橙色标签 = manual_target
│  □ C 车  [x:5.0,y:1.2]   [Auto]   │  ← 未选中，Auto 模式
└───────────────────────────────────┘
```

### 点击行为

| 操作 | 结果 |
|------|------|
| **普通点击** 面板 | 清空 `selected_ids`，设为 `[此车]` |
| **Ctrl + 点击** 面板 | 切换：已选中→移除，未选中→加入 |
| **点 Manual 按钮** | 设为手动模式（见下方流程） |
| **点 Auto 按钮** | 设为自动模式（见下方流程） |

Manual/Auto 按钮的视觉：
- `[Auto]` 灰色底 → 当前 Auto 模式，点击 = 切换为 Manual
- `[Manual]` 橙色底 → 当前 Manual 模式，点击 = 切换为 Auto
- 同一时刻至多一个面板显示 `[Manual]`

### Lock Camera 按钮（ButtonList）

```
manual_target 非空 → 按钮可点击
manual_target 为空 → 按钮灰掉

点击 → toggle follow_enabled
  按下状态 = Camera 正在跟车
```

### 移除的按钮

- **Goto 按钮** — 不再需要，右键地图直接触发

## 六个核心流程

### ① 多选 (Ctrl + 点)

```
用户 Ctrl + 点击 VehiclePanel (车辆 B)
  │
  ▼
VehiclePanel 发出 take_control_toggled(B, ctrl=true)
  ↓
VehiclePanelManager._on_panel_clicked(id, ctrl_held)
  ├── ctrl 未按住: app_state.selected_ids = [id]
  ├── ctrl 按住:   app_state.selected_ids.toggle(id)
  └── EventBus.selection_changed.emit(app_state.selected_ids)
        └── 各 VehiclePanel 刷新选中边框
```

### ② 切换 Manual/Auto

这是最复杂的交互，需要处理两车之间的切换：

```
切换到 Manual（以 B 车为例）:

  当前 manual_target = A（旧手动车）
  ↓
  VehiclePanelManager._on_mode_switch(B, "manual")
    │
    ├── ① 释放旧手动车 A：
    │      cmd_send(A, {"cmd":"mode","action":"switch_to_auto"})
    │      (A 回到 Auto 模式，但不加入 selected_ids)
    │
    ├── ② 设置新手动车 B：
    │      app_state.selected_ids.erase(B)
    │      app_state.manual_target = B
    │      cmd_send(B, {"cmd":"mode","action":"switch_to_manual"})
    │
    ├── ③ 更新 UI：
    │      面板 A: [Manual] → [Auto]（取消橙色）
    │      面板 B: [Auto] → [Manual]（显示橙色）
    │
    └── ④ 广播信号：
          EventBus.manual_target_changed.emit(B)
            ├── Camera: 更新跟车目标
            ├── ButtonList: Lock Camera 变为可用
            └── ControlMaster: 记录 manual_target


切换到 Auto（以 B 车为例）:

  VehiclePanelManager._on_mode_switch(B, "auto")
    │
    ├── ① 释放手动车 B：
    │      app_state.manual_target = ""
    │      cmd_send(B, {"cmd":"mode","action":"switch_to_auto"})
    │
    ├── ② 加入 Auto 列表：
    │      app_state.selected_ids.append(B)
    │
    ├── ③ 更新 UI：
    │      面板 B: [Manual] → [Auto]
    │
    └── ④ 广播信号：
          EventBus.manual_target_changed.emit("")
            ├── Camera: 退出跟随
            └── ButtonList: Lock Camera 灰掉
```

### ③ WASD 手动操控

```
用户按 W/A/S/D/Space
  │
  ▼
InputHandler._input()
  └── build_manual_action(key) / build_manual_stop()
        └── signal ctrl_input(cmd)
              │
              ▼
ControlMaster._on_ctrl_input(cmd)
  ├── app_state.manual_target 为空? → return（无人可操控）
  └── app_state.manual_target = "B"
        │
        ▼
      EventBus.cmd_send.emit("B", cmd)
        └── WebSocketManager._on_cmd_send("B", cmd)
              └── _vehicles["B"].send(JSON.stringify(cmd))
                    └── 小车 B 收到: {"cmd":"manual","action":"forward","speed":50}
```

### ④ Goto 右键地图

```
用户右键点击地图 tile
  │
  ▼
ControlMaster._unhandled_input(event)
  ├── 不是 MOUSE_BUTTON_RIGHT? → return
  ├── app_state.selected_ids 为空? → return  (无目标车辆)
  ├── 不是 pressed? → return  (忽略 release 事件)
  │
  ├── var pos = get_global_mouse_position()
  ├── var tile = CoordUtils.game_to_tile(pos)     # px → tile 网格
  ├── var real = CoordUtils.tile_to_real(tile.x, tile.y)  # tile → 米
  │
  ├── for id in app_state.selected_ids:  # 遍历所有选中车
  │      EventBus.cmd_send.emit(id,
  │          MessageBuilder.build_auto_push_goto(real.x, real.y))
  │
  └── get_viewport().set_input_as_handled()

  ↓ (每条 cmd_send)

WebSocketManager._on_cmd_send(vehicle_id, cmd)
  └── _vehicles[vehicle_id].send(JSON.stringify(cmd))
        └── 小车收到: {
              "cmd": "auto",
              "action": "push",
              "missions": [{"type": "goto", "x": 10.5, "y": 3.2}]
            }
```

⚠️ `_unhandled_input` 而非 `_input`：
只有未被 GUI 控件消费的点击才到达这里。点击 Button、Panel、菜单等不会误触发 Goto。

### ⑤ Lock Camera

```
用户点 Lock Camera 按钮
  │
  ▼
ButtonList._on_lock_camera_pressed()
  └── app_state.follow_enabled = !app_state.follow_enabled
        │
        ▼
Camera._process(delta)
  ├── app_state.follow_enabled == false
  │     → 全功能：边缘滚动 + 中键拖拽 + 滚轮缩放
  │
  └── app_state.follow_enabled == true
        → lerp 跟车(manual_target)
        → 仅缩放可用，禁止拖拽和边缘滚动

特殊情况:
  manual_target 为空 → Lock Camera 按钮灰掉，无法点击
  vehicle_unregistered(manual_target) → follow_enabled 自动设 false
```

### ⑥ 车辆断开

```
WebSocket 断开 / 用户点 Disconnect
  │
  ▼
WebSocketManager._on_client_disconnected(client)
  └── queue_free(client)
  └── EventBus.vehicle_unregistered.emit(vehicle_id)
        │
        ├── VehiclePanelManager._on_vehicle_unregistered(id)
        │     ├── app_state.selected_ids.erase(id)
        │     ├── if id == app_state.manual_target:
        │     │     app_state.manual_target = ""
        │     │     app_state.follow_enabled = false
        │     │     EventBus.manual_target_changed.emit("")
        │     └── 面板 queue_free
        │
        ├── Renderer2D._on_vehicle_unregistered(id)
        │     └── Vehicle2D queue_free
        │
        └── Camera._on_vehicle_unregistered(id)
              └── 重置 _state = IDLE（如果正在跟随该车）
```

## Goto 散布

多辆车收到同一个 (x, y) 点，车端各自计算偏移避免重叠。PC 侧只发中心点，延后实现。

## 子任务（按实现顺序）

- [ ] 1. `AppState`: selected_ids 数组 + manual_target + follow_enabled，移除 mode 枚举和 setter
- [ ] 2. `EventBus`: +selection_changed +manual_target_changed，-mode_transited -vehicle_control_changed
- [ ] 3. `VehiclePanel`: 新增 Manual/Auto 按钮 + 当前模式标签
- [ ] 4. `VehiclePanelManager`: 多选（Ctrl+点）+ 模式切换（互斥 + cmd_send）
- [ ] 5. `ControlMaster`: 移除 _state 状态机 + _input 改 _unhandled_input + 右键 Goto 广播
- [ ] 6. `Camera`: 监听 manual_target_changed + follow_enabled，移除 mode_transited 相关代码
- [ ] 7. `ButtonList`: 移除 Goto 按钮，Lock Camera 改为依赖 manual_target
- [ ] 8. `InputIndicator`: 简化（selected_ids 非空 + 鼠标在地图 = 显示高亮）
- [ ] 9. 全局清理：移除旧 `mode` / `vehicle_control_changed` 相关代码

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/app_state/app_state.gd` | 修改 | 数据结构重构 |
| `src/event_bus/event_bus.gd` | 修改 | 信号增删 |
| `src/ui/WebSocket/vehicle_panel.gd` | 修改 | 新增 mode 按钮和标签 |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 重写 | 多选 + 模式切换互斥 |
| `src/control/control_master.gd` | 修改 | _unhandled_input + 广播 Goto + 移除状态机 |
| `src/camera/camera_2d.gd` | 修改 | 监听 manual_target_changed，移除 mode 逻辑 |
| `src/ui/button_list.gd` | 修改 | 移除 Goto，改 Lock Camera |
| `src/renderer_2d/input_indicator.gd` | 修改 | 简化状态机 |

## 依赖

- task_14 (Goto 基础实现)
- task_15 (Protocol 层，MessageBuilder)
