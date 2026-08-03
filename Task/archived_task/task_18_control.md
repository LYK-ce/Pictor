# Task 18: Control 重构

## 状态：✅ 已完成（2026-08-02）

## 目标

之前：单车主状态机，`selected_id` + `mode` 全局切换。
之后：多车独立模式，无全局状态机。

```
之前                               之后
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━
AppState                           AppState
├── selected_id: "A"               ├── selected_ids: [A,B,C]
├── mode: NONE|FOLLOW|GOTO         ├── manual_target: "B"
└── 全局状态机                      └── follow_enabled: false

操作方式                           操作方式
Goto: 按按钮→进模式→左键点地图      Goto: 右键直接点地图
Follow: 按 Lock Camera→跟车         Follow: 按 Lock Camera→跟 manual_target
多选: 不支持                        多选: Ctrl+点面板
```

## 核心原则

- **Manual 至多 1 辆**：WASD 操控 + Camera 可跟随
- **Auto 命令广播**：Goto 发给 `selected_ids` 中所有车
- **两集合互斥**：一辆车不能同时在 Manual（manual_target）和 Auto（selected_ids）中
- **无模式操作**：右键即 Goto，不需要"进入/退出 Goto 模式"
- **手动/自动分离**：ManualHandler（键盘）与 AutoHandler（鼠标）独立节点

## AppState 最终形态

```gdscript
# src/app_state/app_state.gd
# AppStateResource (Resource)

var selected_ids: Array[String] = []   # Auto 队列，Goto 广播目标
var manual_target: String = ""          # Manual 车，WASD 操控对象
var follow_enabled: bool = false        # Camera 是否跟随 manual_target
var selected_id: String                 # 兼容 getter（取 selected_ids[0]）
```

三个字段互斥关系：

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

## 架构变化

```
改前：                                改后：
ControlMaster (手动+自动混)           ControlMaster (Node2D, 纯容器)
├── InputHandler (键盘→信号)           ├── InputHandler (ManualHandler)
└── AutoHandler (右键 Goto)           │    └── 键盘 WASD → cmd_send(manual_target)
                                      └── AutoHandler (Node2D)
                                           └── 右键 Goto 广播 + 瞬态状态机
```

- `control_master.gd` 删除
- `input_handler.gd` 改装为 ManualHandler：+app_state，删 ctrl_input 信号中转，直接 cmd_send
- `auto_handler.gd` 新建：右键 Goto 广播 + `PendingAction { NONE, PATROL }` 瞬态状态机

## UI 交互

### VehiclePanel 三种状态

```
┌──────────────────────────┐
│  ▢ A 车          [Manual] │  ← 橙色边框 = manual_target（WASD）
│  ▢ B 车          [Auto]   │  ← 绿色边框 = selected_ids 队列（Goto）
│  ▢ C 车                  │  ← 默认边框 = 未选中
└──────────────────────────┘
```

| 操作 | 结果 |
|------|------|
| **Ctrl + 点** 面板 | 切换：已选中→移除，未选中→加入 |
| **Ctrl + 点** 手动车 | 手动→自动，加入队列 |
| **勾选"手动"** 复选框 | 设 manual_target，发 switch_to_manual |
| **取消"手动"** 复选框 | 释放 manual_target，变未选中（不进队列） |

### 移除的按钮

- **TakeControl（接管控制）** — 逻辑移除，由"手动"复选框替代
- **Goto 按钮** — 无模式，右键地图直接触发

## 完整流程

### ① 多选 (Ctrl + 点)

```
用户 Ctrl + 点击 VehiclePanel (车辆 B)
  └── VehiclePanel._gui_input → panel_clicked(B, true)
        └── VehiclePanelManager._on_panel_clicked(B, true)
              ├── B == manual_target? → 切回 auto + 入队
              ├── B 在队列? → erase
              └── 否则 → append
              └── _update_selection()（刷新所有面板状态）
```

### ② 切换 Manual / Auto（手动复选框）

```
勾选 B 的"手动":
  └── VehiclePanel._on_manual_toggled(true) → mode_toggled(B, true)
        └── VehiclePanelManager._on_mode_toggled(B, true)
              ├── 旧手动车 A → switch_to_auto，变未选中
              ├── B 从 selected_ids 移除
              ├── B → switch_to_manual，manual_target = B
              └── _update_selection()

取消 B 的"手动":
  └── mode_toggled(B, false)
        └── _on_mode_toggled(B, false)
              ├── manual_target = ""
              ├── B → switch_to_auto
              └── 变未选中（不加入 selected_ids）
```

### ③ WASD 手动操控

```
用户按 W/A/S/D/Space
  └── ManualHandler._input()
        ├── 按键映射 → build_manual_action/stop()
        ├── manual_target 为空? → return
        └── EventBus.cmd_send.emit(manual_target, cmd)
              └── WebSocketManager → ws.send()
```

### ④ Goto（右键地图）

```
用户右键点击地图 tile
  └── AutoHandler._unhandled_input(event)
        ├── 瞬态态（_pending_action != NONE）?
        │     ├── 左键 → _execute_pending()（扩展点）
        │     └── 右键/其他 → 取消
        ├── 不是右键 pressed? → return
        ├── selected_ids 为空? → return
        │
        ├── game_to_tile(pos) → tile_to_real(tile) → (x, y)
        ├── for id in selected_ids: cmd_send(id, build_auto_push_goto(x,y))
        ├── EventBus.goto_issued.emit(x, y)   ← 高亮
        └── set_input_as_handled()
```

### ⑤ Goto 高亮（InputIndicator）

```
EventBus.goto_issued(x, y)
  └── InputIndicator._on_goto_issued(x, y)
        ├── real_to_game → game_to_tile → tile_to_game（吸附 tile 中心）
        ├── 高亮框显示
        └── Tween: 保持 0.2s → 淡出 0.4s → 隐藏
```

### ⑥ 车辆断开

```
vehicle_unregistered(id)
  ├── selected_ids.erase(id)
  ├── id == manual_target? → manual_target = ""
  └── 面板 queue_free
```

## 子任务完成情况

- [x] 1. `AppState`: selected_ids 数组 + manual_target + selected_id 兼容 getter
- [x] 2. `EventBus`: +goto_issued，保留 mode_transited（Camera 仍依赖）
- [x] 3. `VehiclePanel`: 三态边框（NORMAL/MANUAL/AUTO）+ Mode 标签，移除 TakeControl
- [x] 4. `VehiclePanelManager`: Ctrl+点多选 + Manual 复选框互斥切换
- [x] 5. `ManualHandler`（原 ControlMaster 手动部分 + InputHandler 合并）
- [x] 6. `AutoHandler`: 右键 Goto 广播 + PendingAction 瞬态状态机
- [x] 7. `InputIndicator`: 重写为 goto 点击闪烁（0.2s + 0.4s 淡出）
- [x] 8. 全局清理：删除 control_master.gd

## 涉及文件（实际变更）

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/app_state/app_state.gd` | 修改 | selected_ids + manual_target + 兼容 getter |
| `src/event_bus/event_bus.gd` | 修改 | +goto_issued |
| `src/ui/WebSocket/vehicle_panel.gd` | 重写 | 三态边框 + mode_toggled 信号 |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 重写 | 多选 + 模式互斥 |
| `src/ui/WebSocket/vehicle_panel.tscn` | 修改 | 移除 TakeControl 按钮，+Mode Label |
| `src/control/input_handler.gd` | 改装 | ManualHandler（键盘→cmd_send） |
| `src/control/auto_handler.gd` | 新建 | 右键 Goto + 瞬态状态机 |
| `src/control/control_master.gd` | 删除 | 逻辑拆分 |
| `src/control/control.tscn` | 修改 | 容器 + 两 handler |
| `src/control/input_handler.tscn` | 修改 | +app_state |
| `src/renderer_2d/input_indicator.gd` | 重写 | goto 点击闪烁 |

## 待办（后续任务）

- [ ] Goto 散布：多车同时到达同一点时的偏移算法（车端自行决定，暂缓）
- [ ] Patrol / Stop 等瞬态命令（AutoHandler `_pending_action` 扩展点已预留）
- [ ] Camera 切换 manual_target_changed 信号（当前仍依赖 mode_transited）
- [ ] Lock Camera 按钮适配（follow_enabled 尚未接入 UI）

## 依赖

- task_14 (Goto 基础实现)
- task_15 (Protocol 层，MessageBuilder)
