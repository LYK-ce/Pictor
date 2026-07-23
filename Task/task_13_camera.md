# Task 13: Camera

## 目标

将 Camera2D 从 Vehicle2D 上分离，作为独立组件开发。

## 设计决策

- Camera2D 挂载在 Main 节点下作为子组件，不再跟随 Vehicle2D
- Camera 提供控制方式用于移动/缩放/跟踪等操作

### 移动：鼠标中键拖拽

- 中键按下 → 记录起始鼠标位置 + Camera 当前位置
- 拖拽中 → `camera.position = 起始位置 - 鼠标偏移 / zoom`
- 除以 zoom 保证放大缩小时拖拽手感一致（抓住拖动）
- 中键释放 → 停止拖拽
- 使用 `_unhandled_input`，避免 UI 拦截

### 移动：边缘滚动

- 屏幕四边各留 20px 触发区，鼠标贴边即滚动
- `_process` 中每帧检测，4 行浮点比较，开销极低
- `position += dir * speed * delta / zoom`，除以 zoom 保证速度恒定

### 跟踪车辆

**方案：Shared Resource（外挂 Resource）**

- `selected_id` 不放在 EventBus 中，不新增 Autoload
- 创建 `AppStateResource` 作为共享 Resource（`.tres`）
- 放在 `src/app_state/` 独立子目录下
- 只存 `selected_id: String`
- 消费者通过 `@export var app_state: AppStateResource` 显式声明依赖
- 所有消费者拖同一个 `.tres` 文件，读写同一份数据

**涉及文件：**

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/app_state/app_state.gd` | 新建 | `class_name AppStateResource extends Resource`，只含 `var selected_id := ""` |
| `src/app_state/app_state.tres` | 新建 | Resource 实例文件 |
| `src/event_bus/event_bus.gd` | 修改 | 新增 `signal camera_follow_requested` |
| `src/ui/button_list.gd` | 修改 | 按钮 pressed → `EventBus.camera_follow_requested.emit()` |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 修改 | 选中/取消时写入 `app_state.selected_id` |
| `src/control/control_master.gd` | 修改 | `_selected_id` 改为从 `app_state` 读取 |
| `src/camera/camera_2d.gd` | 修改 | 新增跟车模式：监听 `camera_follow_requested` + `pose_received` + `vehicle_unregistered` |

**信号流（全程 EventBus，不直接通信）：**

```
button_list 按下
  → EventBus.camera_follow_requested.emit()
    → Camera 收到 → _following = !_following（自切自管）

pose_received(vehicle_id, pose) 到达
  → Camera：_following && vehicle_id == app_state.selected_id？
    → 更新 _target_position = CoordUtils.real_to_game(pose.x, pose.y)

vehicle_unregistered(selected_id)
  → Camera：_following = false（自动退出，不通知 button_list）
```

**按钮设计：普通按钮（非 Toggle）**
- 按钮永远是"未按下"外观，只发事件不持有状态
- `_following` 由 Camera 自己管理，不反向同步按钮
- 避免 toggle 模式的双向同步问题

**Camera 跟车逻辑：**

进入跟车时 `_target_position = position`（即当前 Camera 位置），避免第一帧跳回原点。之后 `pose_received` 逐步更新，`_process` 中 lerp 平滑跟随。

```
首次进入跟车时:
  _target_position = position  ← 避免跳回原点

_process:
  if _following:
      position = position.lerp(_target_position, 0.3)
```

**跟车模式下的行为：**
- 中键拖拽：暂停（`_Middle_Drag` 中检查 `_following` 跳过）
- 边缘滚动：暂停（`_Edge_Scroll` 中检查 `_following` 跳过）
- 滚轮缩放：保持可用
- 退出方式：再次按下 Lock Camera 按钮 / 车辆断开连接

### 边界限制

- Camera2D 内置 `limit_left/right/top/bottom`，需要时 `@export` 配置即可
- 当前地图不大，暂不限制

### 缩放
- 滚轮缩放：在 Camera 脚本中实现
- zoom_slider UI 组件：后续由人工添加到 UI，agent 暂不处理

## 实施步骤

### 1. 移除 Vehicle2D 上的 Camera2D
- [x] 从 `vehicle_2d.tscn` 中删除 Camera2D 子节点

### 2. 创建 Camera 组件
- [x] 新建 `src/camera/` 目录
- [x] 创建 `camera_2d.gd` 脚本 + `camera_2d.tscn` 场景
- [x] Camera 挂载在 Main 下，作为独立子组件
- [x] 实现移动：中键拖拽 + 边缘滚动
- [x] 实现滚轮缩放（以鼠标为中心）
- [x] 实现跟车模式（点击 Lock Camera 按钮触发）
- [ ] zoom_slider UI（人工处理）

## 依赖

- EventBus (task_2)

## 状态

- [x] 1. 移除 Camera2D
- [x] 2. 创建 Camera 组件
- [x] 3. 中键拖拽
- [x] 4. 边缘滚动
- [x] 5. 滚轮缩放
- [x] 6. 共享状态 Resource（app_state.gd + .tres）
- [x] 7. VehiclePanelManager / ControlMaster 适配 AppStateResource
- [x] 8. Camera 跟车模式实现
- [x] 9. button_list 信号 → Camera 触发跟车
- [ ] 10. zoom_slider UI（人工）