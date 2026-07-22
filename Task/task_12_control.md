# Task 12: 控制终端

## 目标

将 Pictor 从可视化框架升级为完整的控制终端，实现 PC → 小车的 cmd 指令下发以及控制相关 UI。

## 设计决策

### 选中机制

三层职责：

| 层 | 角色 | 通信方式 |
|------|------|------|
| VehiclePanel | 仅提供 `Control_Area` 节点 + `set_selected(bool)` | 不加代码，不加信号 |
| VehiclePanelManager | 选中唯一真相源：连 `Control_Area.gui_input`，决策切换，管理所有 Panel 高亮 | EventBus → 通知 ControlMaster |
| ControlMaster | 消费选中状态，驱动 cmd 下发 | EventBus 接收 |

切换逻辑：
- 点击 Panel A（无选中）→ A 高亮，emit `vehicle_control_changed("A")`
- 点击 Panel A（A 已选中）→ A 取消高亮，emit `vehicle_control_changed("")`
- 点击 Panel B（A 选中中）→ A 取消高亮 + B 高亮，emit `vehicle_control_changed("B")`

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
- InputHandler 职责不变：键盘 → cmd 方向，不感知 vehicle_id

### 数据流

#### 选中/取消选中流程

```
用户点击 VehiclePanel.Control_Area
  → gui_input → VehiclePanelManager._on_panel_gui_input(event, vehicle_id)
      ├── 切换逻辑：判断是否同一辆车
      ├── 遍历 _panels，更新所有 Panel.set_selected()
      └── EventBus.vehicle_control_changed.emit(vehicle_id | "")
            └── ControlMaster._on_vehicle_control_changed(vehicle_id)
                  ├── 记录 _selected_id = vehicle_id（空 = 无选中）
                  └── InputHandler 启用/禁用
```

#### 控制流程

```
用户按 W/A/S/D/Space
  → InputHandler._input() → 内部 signal ctrl_input(cmd)
    → ControlMaster._on_ctrl_input(cmd)
      → 若 _selected_id 为空 → 忽略
      → EventBus.cmd_send.emit(_selected_id, cmd)
          → WebSocketManager._on_cmd_send(vehicle_id, cmd)
              → _vehicles[vehicle_id].send(JSON.stringify(cmd))
                  → 小车收到 cmd
```

#### 车辆注销时清理选中

```
vehicle_unregistered(vehicle_id)
  → VehiclePanelManager → 移除 panel
  → ControlMaster → 若 vehicle_id == _selected_id → 清空 _selected_id
```

## 实施步骤

### 1. 目录重构
- [ ] 将 `src/input_handler/` 重命名为 `src/control/`
- [ ] 新建 `src/control/control_master.gd`
- [ ] 新建 `src/control/control.tscn`

### 2. EventBus 新增信号

当前 EventBus 共 9 个信号：

```
pose_received(vehicle_id, pose)        map_full_received(chunk_x, chunk_y, cells)
map_delta_received(voxels)             chunk_updated(chunk_x, chunk_y)
ws_connected                           ws_connect_requested(url)
ws_disconnect_requested(vehicle_id)    vehicle_registered(vehicle_id, url)
vehicle_unregistered(vehicle_id)
```

本次新增 2 个：

| 信号 | 发送者 | 接收者 | 说明 |
|------|--------|--------|------|
| `vehicle_control_changed(vehicle_id: String)` | VehiclePanelManager | ControlMaster | 空字符串 = 取消选中 |
| `cmd_send(vehicle_id: String, cmd: Dictionary)` | ControlMaster | WebSocketManager | PC → 小车控制指令 |

### 3. VehiclePanel
- [ ] 删除 `_on_control_area_gui_input` 方法（空 `pass`，不需要）
- [ ] 添加 `set_selected(selected: bool)` — 切换 `StyleBoxFlat` 边框颜色

### 4. VehiclePanelManager 选中管理
- [ ] 创建 Panel 时连接 `Control_Area.gui_input`，绑定 `vehicle_id`
- [ ] `_on_panel_gui_input(event, vehicle_id)`：左键按下 → 切换逻辑
- [ ] 持有 `_selected_id: String`，遍历 `_panels` 更新 `set_selected()`
- [ ] 决策后 emit `vehicle_control_changed(selected_id)`

### 5. ControlMaster
- [ ] `_ready()` 监听 `vehicle_control_changed` / `vehicle_unregistered` / 内部 ctrl_input
- [ ] 持有 `_selected_id: String`，`vehicle_unregistered` 时若匹配则清空
- [ ] `_on_ctrl_input(cmd)` → 若 `_selected_id` 为空则忽略，否则 emit `cmd_send(_selected_id, cmd)`

### 6. InputHandler
- [ ] `_input()` 改为内部信号 `ctrl_input(cmd: Dictionary)`，不再 emit EventBus
- [ ] 保持现有按键映射不变

### 7. WebSocketManager
- [ ] 监听 `cmd_send` → `_vehicles[vehicle_id].send(JSON.stringify(cmd))`

### 8. main.tscn
- [ ] 挂载 ControlMaster 节点

## 依赖

- [x] EventBus (task_2)
- [x] WebSocketManager / WebSocketClient (task_4, task_10, task_11)
- [x] VehiclePanel / VehiclePanelManager (task_11)

## 状态

- [ ] 1. 目录重构
- [ ] 2. EventBus 新增信号
- [ ] 3. VehiclePanel
- [ ] 4. VehiclePanelManager 选中管理
- [ ] 5. ControlMaster
- [ ] 6. InputHandler
- [ ] 7. WebSocketManager
- [ ] 8. main.tscn 挂载
