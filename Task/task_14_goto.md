# Task 14: Goto

## 目标

通过鼠标点击地图 Tile，向选中车辆下发 goto 导航命令。

## 设计决策

### AppState 全局模式状态机

`AppStateResource` 新增 `Mode` 枚举 + `mode` 属性，值变化时通过 EventBus 广播：

```gdscript
# app_state.gd
enum Mode { NONE, FOLLOW, GOTO }

var selected_id := "":
    set(value):
        if selected_id != value:
            selected_id = value
            EventBus.selection_changed.emit(value)

var mode := Mode.NONE:
    set(value):
        if mode != value:
            mode = value
            EventBus.mode_transited.emit(mode)
```

EventBus 新增两个信号，移除 `vehicle_control_changed`：

```gdscript
signal selection_changed(id: String)
signal mode_transited(mode: int)
```

### 两层状态机架构

**全局层**（AppState.mode）：当前哪个交互模式激活。

**组件层**：各组件内部状态机，监听 `mode_transited` 自行切换：

```
EventBus.mode_transited(mode) → 各组件响应
  Camera:
    FOLLOW → _state = FOLLOW
    _      → _state = IDLE

  InputIndicator:
    GOTO → _state = ACTIVE（高亮 + 拦截点击）
    _    → _state = IDLE
```

**模式切换规则：**

```
NONE ──[ Lock Camera ]──→ FOLLOW ──[ Lock Camera ]──→ NONE
  │                           │
  └──[ Goto ]────────→ GOTO ──[ Goto ]────────→ NONE
                          │
                   [点击 tile 下发]
                          │
                          └──→ NONE
```

- 同一按钮再次按下 → 退回 NONE
- 新命令覆盖旧命令
- Goto 下发完成后自动退回 NONE

### Camera 状态机

Camera 内部用 `_state` 枚举替代 `_following` bool，监听 `mode_transited` 切换：

```gdscript
enum State { IDLE, FOLLOW }

func _on_mode_transited(mode: int):
    match mode:
        AppStateResource.Mode.FOLLOW:
            _state = State.FOLLOW
        _:
            _state = State.IDLE
```

内部行为：

```
IDLE   → _Edge_Scroll + _Middle_Drag + _Zoom（全功能）
FOLLOW → lerp 跟车 + _Zoom（禁拖禁边）

额外退出：vehicle_unregistered → _state = IDLE
```

### Goto 交互流程

```
1. 用户选中车辆（app_state.selected_id 非空）
2. 用户按 Goto 按钮 → app_state.mode = GOTO
   → EventBus.mode_transited(GOTO)
     → InputIndicator 激活
     → Camera 保持 IDLE
3. 鼠标移到 TileMap 上 → InputIndicator 显示高亮框，吸附最近 tile
4. 用户点击 tile → InputIndicator:
     a. 取 tile 网格坐标 (gx, gy)
     b. 转为真实世界坐标 (x, y) 米（取 tile 中心点）
     c. EventBus.cmd_send.emit(selected_id, {"cmd": "goto", "x": ..., "y": ...})
     d. app_state.mode = NONE（自动退出）
```

### 坐标转换（CoordUtils 扩展）

`CoordUtils` 新增 tile 网格转换方法，均为静态纯函数：

```gdscript
static func game_to_tile(world_pos: Vector2) -> Vector2i  # px → 网格
static func tile_to_game(gx: int, gy: int) -> Vector2      # 网格 → tile 中心 (px)
static func tile_to_real(gx: int, gy: int) -> Vector2      # 网格 → 真实世界 米
```

转换链：

```
get_global_mouse_position()
  → game_to_tile()   → (gx, gy)
  → tile_to_game()   → 高亮框位置
  → tile_to_real()   → cmd_send
```

### 协议

下行新增 `goto` 命令（已更新 `docs/websocket_protocol.md`）：

```json
{"cmd": "goto", "x": 10.5, "y": 3.2}
```

### 待讨论

- 高亮框实现方案（TileMap highlight layer / Sprite2D / ColorRect 等）
- Goto 模式下 Camera 是否仍可手动移动？
- 是否需要校验 cell 状态（点墙拒绝）？
- 是否需要目标标记（旗帜图标留在点击位置）？

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/app_state/app_state.gd` | 修改 | 新增 Mode 枚举 + mode 属性(setter emit) |
| `src/event_bus/event_bus.gd` | 修改 | 新增 `signal mode_transited`，移除 `camera_follow_requested` |
| `src/camera/camera_2d.gd` | 修改 | 内部重构 IDLE/FOLLOW 状态机，监听 `mode_transited` |
| `src/ui/button_list.gd` | 修改 | Lock Camera / Goto 按钮改为写 `app_state.mode` |
| `src/utils/coords.gd` | 修改 | 新增 game_to_tile / tile_to_game / tile_to_real |
| `src/renderer_2d/input_indicator.gd` | 新建 | 监听 `mode_transited`，Goto 时高亮 + 点击下发 |
| `docs/websocket_protocol.md` | 已改 | 新增 goto 命令 |

## 依赖

- AppStateResource (task_13)
- EventBus cmd_send 链路 (task_12)
- WebSocketManager (task_10)
- [ ] 1. AppState: selected_id setter + Mode setter
- [ ] 2. EventBus: +selection_changed, +mode_transited, -vehicle_control_changed, -camera_follow_requested
- [ ] 3. Camera 重构 IDLE/FOLLOW 状态机，监听 mode_transited
- [ ] 4. button_list 改为写 app_state.mode
- [ ] 5. VehiclePanelManager/ControlMaster 统一用 app_state.selected_id
- [ ] 6. CoordUtils 新增 tile 坐标转换
- [ ] 7. InputIndicator 组件