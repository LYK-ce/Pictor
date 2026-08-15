# Task 12: 控制终端

## 目标

将 Pictor 从可视化框架升级为完整的控制终端，实现 PC → 小车的 cmd 指令下发以及控制相关 UI。

## 设计决策

### 选中机制

三层职责：

| 层 | 角色 | 通信方式 |
|------|------|------|
| VehiclePanel | Take Control 按钮 (toggle_mode) + `set_selected(bool)` + `set_pressed(bool)` | 内部 signal → PanelManager |
| VehiclePanelManager | 选中唯一真相源：连 `take_control_toggled`，决策切换，管理所有 Panel 高亮 | EventBus → 通知 ControlMaster |
| ControlMaster | 消费选中状态，驱动 cmd 下发 | EventBus 接收 |

切换逻辑：
- 按下 Take Control → PanelManager 接管，新车上旧车自动弹起，emit `vehicle_control_changed("A")`
- 再次按下弹起 → PanelManager 释放，emit `vehicle_control_changed("")`

### cmd 下发链路

```
InputHandler → ControlMaster → EventBus.cmd_send(vehicle_id, cmd) → WebSocketManager → WebSocketClient.send()
```

- `cmd_send` 接收者只有一个：WebSocketManager
- 格式：`cmd_send(vehicle_id: String, cmd: Dictionary)`
- cmd 字典格式：`{"cmd": "forward"|"backward"|"spin_left"|"spin_right"|"stop"}`
- ControlMaster 持有 `_selected_id`，若为空则忽略 cmd

### 目录重构

- `src/input_handler/` → `src/control/`
- 新建 `control_master.gd` + `control.tscn`，挂 `InputHandler` 为子节点
- ControlMaster 持有 `_selected_id`，监听 `vehicle_control_changed` / `vehicle_unregistered`

### 地图性能优化

- 注释 `_save_chunk()`：去掉同步磁盘 IO
- 新增 `cells_changed(updates: Array)` 信号：delta 增量渲染，仅更新变化的 cell，不再全 chunk 扫描 65536 格
- `map_full` 仍走 `chunk_updated` → `render_chunk` 全量渲染

### 数据流

#### 选中/取消选中流程

```
用户按 Toggle 按钮
  → VehiclePanel._on_take_control_toggled(pressed)
      → signal take_control_toggled(vehicle_id, pressed)
          → VehiclePanelManager._on_take_control_toggled(vehicle_id, pressed)
              ├── 接管：弹起旧按钮，记录新 _selected_id
              ├── 释放：清空 _selected_id
              ├── _update_selection() → 所有 Panel.set_selected()
              └── EventBus.vehicle_control_changed.emit(_selected_id)
```

#### 控制流程

```
用户按 W/A/S/D/Space
  → InputHandler._input() → signal ctrl_input(cmd)
    → ControlMaster._on_ctrl_input(cmd)
      → 若 _selected_id 为空 → 忽略
      → EventBus.cmd_send.emit(_selected_id, cmd)
          → WebSocketManager._on_cmd_send(vehicle_id, cmd)
              → _vehicles[vehicle_id].send(JSON.stringify(cmd))
```

#### 地图增量更新

```
map_delta 到达
  → MapData2D.set_chunk_delta()
      → 更新 cells 数组 + 收集 changed [{gx,gy,state}, ...]
      → EventBus.cells_changed.emit(changed)
          → Renderer2D._on_cells_changed()
              → MapContainer2D.update_cells(updates)
                  → 逐个 set_cells_terrain_connect / erase_cell
```

## 实施步骤

### 1. 目录重构
- [x] 将 `src/input_handler/` 重命名为 `src/control/`
- [x] 新建 `src/control/control_master.gd`
- [x] 新建 `src/control/control.tscn`

### 2. EventBus 新增信号

当前 EventBus 共 12 个信号。本次新增 3 个：

| 信号 | 发送者 | 接收者 | 说明 |
|------|--------|--------|------|
| `vehicle_control_changed(vehicle_id: String)` | VehiclePanelManager | ControlMaster | 空字符串 = 取消选中 |
| `cmd_send(vehicle_id: String, cmd: Dictionary)` | ControlMaster | WebSocketManager | PC → 小车控制指令 |
| `cells_changed(updates: Array)` | MapData2D | Renderer2D | 增量地图更新 |

### 3. VehiclePanel
- [x] Toggle 按钮 `take_control_toggled` 信号
- [x] `set_selected(bool)` StyleBoxFlat 高亮
- [x] `set_pressed(bool)` 供 Manager 弹起按钮

### 4. VehiclePanelManager 选中管理
- [x] 连接 Panel 的 `take_control_toggled` 信号
- [x] 接管时弹起旧按钮，释放时清空
- [x] 持有 `_selected_id`，遍历更新 `set_selected()`
- [x] emit `vehicle_control_changed`

### 5. ControlMaster
- [x] 监听 `vehicle_control_changed` / `vehicle_unregistered`
- [x] 持有 `_selected_id`，断开时自动清空
- [x] `_on_ctrl_input(cmd)` → emit `cmd_send(_selected_id, cmd)`

### 6. InputHandler
- [x] 改为内部 signal `ctrl_input(cmd)`，不再 emit EventBus

### 7. WebSocketManager
- [x] 监听 `cmd_send` → `_vehicles[vehicle_id].send(JSON.stringify(cmd))`

### 8. main.tscn
- [x] 挂载 ControlMaster 节点
- [x] WebSocketMenu 包入 CanvasLayer

### 9. 附带修复
- [x] pose 读取 `pose.y` 而非 `pose.z`（车被钉在上沿的 bug）
- [x] 未知区域 (state>=2) 不渲染，双清 GroundLayer/WallLayer
- [x] 注释 `_save_chunk` 去磁盘 IO
- [x] 删除废弃的 `vehicle_marker_2d.gd/.tscn`
- [x] vehicle_2d.tscn 加 Camera2D

## 依赖

- [x] EventBus (task_2)
- [x] WebSocketManager / WebSocketClient (task_4, task_10, task_11)
- [x] VehiclePanel / VehiclePanelManager (task_11)

## 状态

- [x] 1. 目录重构
- [x] 2. EventBus 新增信号
- [x] 3. VehiclePanel
- [x] 4. VehiclePanelManager 选中管理
- [x] 5. ControlMaster
- [x] 6. InputHandler
- [x] 7. WebSocketManager
- [x] 8. main.tscn 挂载
- [x] 9. 附带修复 & 性能优化
