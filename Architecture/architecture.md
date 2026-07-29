# Pictor Architecture

## 概述

Pictor 是 Pleiades 系统的 Godot 可视化与控制终端。通过 WebSocket 与小车端 Pleiades 双向通信，支持多车同时连接。

## 场景结构

主场景 `src/main/main.tscn` 组件树：

```
Main (Node, main.gd)
├── MapData2D (Node, %MapData2D)     ← 地图数据层，unique_name 全局访问
├── Renderer2D (Node2D)              ← 2D 渲染器
│   ├── MapContainer2D (Node2D)      ← 地图渲染
│   │   ├── GroundLayer (TileMapLayer)
│   │   └── WallLayer (TileMapLayer)
│   ├── VehicleContainer (Node2D)    ← 车辆 Sprite 动态挂载点
│   ├── InputIndicator (Node2D)      ← Goto 高亮框
│   └── PathLine2D (Node2D)           ← 路径线条
├── WebSocketManager (Node)          ← 多连接总管
│   └── WebSocketClient × N          ← 动态实例化，每车一个
├── ControlMaster (Node2D)           ← 控制总管 (Goto + Manual)
│   └── InputHandler (Node)          ← 键盘 WASD 输入
├── Camera (Camera2D)                ← 2D 相机（IDLE/FOLLOW 状态机）
├── WebSocketMenu (Control)          ← 连接 UI
│   └── VehiclePanelManager          ← 车辆信息面板总管
│       └── VehiclePanel × N         ← 动态实例化，每车一个
├── ButtonList (PanelContainer)      ← Lock Camera / Goto 按钮
└── ZoomSlider (Control)             ← 缩放滑块
```

EventBus 通过 Autoload 注入，所有组件通过信号通信，无需场景挂载。

## 目录结构

```
src/
├── event_bus/
│   └── event_bus.gd                 ← Autoload 单例
├── app_state/
│   └── app_state.gd                 ← AppStateResource (Mode 枚举 + selected_id)
├── main/
│   ├── main.gd                      ← 入口脚本
│   ├── main.tscn                    ← 入口场景
│   ├── menu.gd                      ← 渲染模式选择菜单
│   └── menu.tscn
├── websocket/
│   ├── protocol/
│   │   ├── protocol_def.gd          ← 协议枚举/常量
│   │   ├── message_builder.gd       ← 下行消息构造
│   │   └── message_parser.gd        ← 上行消息解析
│   ├── websocket_client.gd          ← WS 连接组件
│   ├── websocket_client.tscn
│   ├── websocket_manager.gd         ← 多连接管理
│   └── websocket_manager.tscn
├── control/
│   ├── control_master.gd            ← 控制总管 (Goto + Manual)
│   ├── control_master.tscn
│   ├── input_handler.gd             ← 键盘 WASD 输入
│   └── input_handler.tscn
├── camera/
│   ├── camera_2d.gd                 ← 2D 相机 (IDLE/FOLLOW 状态机)
│   └── camera_2d.tscn
├── renderer_2d/
│   ├── renderer_2d.gd               ← 2D 渲染总管
│   ├── renderer_2d.tscn
│   ├── map_data_2d.gd               ← 地图数据（Chunk 存储）
│   ├── map_data_2d.tscn
│   ├── chunk_data_2d.gd             ← Chunk Resource 类型
│   ├── map_container_2d.gd          ← TileMapLayer 渲染
│   ├── map_container_2d.tscn
│   ├── input_indicator.gd           ← Goto 高亮框
│   ├── input_indicator.tscn
│   ├── path_line_2d.gd              ← 路径线条（Line2D）
│   ├── path_line_2d.tscn
│   └── Vehicle/
│       └── vehicle_2d.tscn          ← 车辆场景（AnimatedSprite2D + Camera2D）
├── renderer_3d/
│   ├── renderer_3d.gd               ← 3D 渲染总管（🔴 信号缺失，不可用）
│   ├── renderer_3d.tscn
│   ├── map_container_3d.gd          ← MultiMeshInstance3D 体素渲染
│   ├── map_container_3d.tscn
│   ├── vehicle_marker_3d.gd         ← 3D 车辆标记
│   ├── vehicle_marker_3d.tscn
│   ├── path_line_3d.gd              ← 3D 路径线条（ImmediateMesh）
│   └── path_line_3d.tscn
├── ui/
│   ├── ui.gd                        ← UI 父容器 CanvasLayer
│   ├── ui.tscn
│   ├── button_list.gd               ← Lock Camera / Goto 按钮
│   ├── button_list.tscn
│   ├── help_label.gd                ← 操作说明标签
│   ├── help_label.tscn
│   ├── zoom_slider/
│   │   ├── zoom_slider.gd           ← 缩放滑块（🔴 zoom_changed 信号缺失）
│   │   └── zoom_slider.tscn
│   └── WebSocket/
│       ├── websocket_menu.gd        ← Connect 按钮入口
│       ├── websocket_menu.tscn
│       ├── web_socket_creation_menu.gd  ← 地址/端口输入弹窗
│       ├── web_socket_creation_menu.tscn
│       ├── vehicle_panel.gd         ← 单车信息面板
│       ├── vehicle_panel.tscn
│       ├── vehicle_panel_manager.gd ← 多面板总管
│       └── vehicle_panel_manager.tscn
├── test/
│   └── test_ws_server.gd            ← 多车测试用 WS Server
└── utils/
    └── coords.gd                    ← CoordUtils：真实世界 ↔ 游戏世界坐标转换
```

## 连接流程

多车连接采用 **hello 握手** 机制：

```
1. 用户在 WebSocketMenu 输入地址 → EventBus.ws_connect_requested
2. WebSocketManager.create_connection(url) → 实例化 WebSocketClient，以 url 为临时 key
3. WebSocket 握手完成 → WebSocketClient 等待 hello 包
4. 小车发送 hello → MessageParser.parse_json() 识别 ProtocolDef.MSG_HELLO
5. WebSocketClient 设 _identified=true → EventBus.vehicle_registered(vehicle_id, url)
6. WebSocketManager 收到 → 将 _vehicles[url] 替换为 _vehicles[vehicle_id]
7. Renderer2D 收到 → 创建 Vehicle2D Sprite
8. VehiclePanelManager 收到 → 创建 VehiclePanel
9. hello 之后的数据（pose / map_full / map_delta）正常流转
```

## Protocol 层

协议定义/构造/解析统一在 `src/websocket/protocol/`：

| 文件 | 职责 |
|------|------|
| `ProtocolDef` | 所有魔法字符串/数字常量（MSG_HELLO, CMD_MANUAL, CELL_FREE, BIN_CELLS_OFFSET 等） |
| `MessageBuilder` | 下行消息构造，静态方法返回 Dictionary |
| `MessageParser` | 上行消息解析（JSON + 二进制帧），静态方法返回结构化结果 |

调用方使用 `MessageBuilder.build_xxx()` 构造命令，`MessageParser.parse_xxx()` 解析消息，不再手写 JSON 或硬编码字节偏移。

## 地图存储架构

```
MapData2D (Node, %MapData2D)
├── Chunk 大小: 256×256 cells
├── Cell 编码: 0=可通行, 1=不可通行, 2=未知
├── 存储: Dictionary{Vector2i(chunk_x, chunk_y) → ChunkData2D}
├── 持久化: user://map_data_2d/map_chunk_{x}_{y}.tres（暂时关闭）
└── API:
    ├── set_full(chunk_x, chunk_y, cells: PackedByteArray)
    ├── set_delta(voxels: Array)
    ├── get_cell(gx, gy) → int
    ├── get_chunk_cells(cx, cy) → PackedByteArray
    └── load_chunk(cx, cy) → PackedByteArray
```

地图更新触发链：

- **全量更新**：`set_full` → 写入 ChunkData2D → `EventBus.chunk_updated.emit(cx, cy)` → Renderer2D._on_chunk_updated() → MapContainer2D.render_chunk()（全量重绘）
- **增量更新**：`set_delta` → 逐 cell 写入 → `EventBus.cells_changed.emit(updates)` → Renderer2D._on_cells_changed() → MapContainer2D.update_cells()（仅更新变动的 tile）

## EventBus 信号

| 信号 | 发送者 | 接收者 | 说明 |
|------|------|------|------|
| `pose_received(vehicle_id: String, pose: Dictionary)` | WebSocketClient | Renderer2D, VehiclePanelManager, Camera | 车辆位姿，含 x/y/z/yaw/vx/vy |
| `map_full_received(chunk_x: int, chunk_y: int, cells: PackedByteArray)` | WebSocketClient | MapData2D | 全量 Chunk（二进制帧） |
| `map_delta_received(voxels: Array)` | WebSocketClient | MapData2D | 增量地图（JSON） |
| `chunk_updated(chunk_x: int, chunk_y: int)` | MapData2D | Renderer2D | Chunk 全量变更 → 触发全量重绘 |
| `cells_changed(updates: Array)` | MapData2D | Renderer2D | 增量 cell 变更 → 触发增量更新 |
| `ws_connected` | WebSocketClient | （暂无接收者） | WebSocket 握手完成 |
| `ws_connect_requested(url: String)` | WebSocketCreationMenu | WebSocketManager | 用户请求连接 |
| `ws_disconnect_requested(vehicle_id: String)` | VehiclePanel | WebSocketManager | 用户请求断开 |
| `vehicle_registered(vehicle_id: String, url: String)` | WebSocketClient | WebSocketManager, Renderer2D, VehiclePanelManager | hello 包收到，身份确认 |
| `vehicle_unregistered(vehicle_id: String)` | WebSocketManager | Renderer2D, VehiclePanelManager, Camera | 连接断开，清理资源 |
| `selection_changed(id: String)` | AppStateResource (setter) | （暂无接收者） | 选中车辆变更 |
| `mode_transited(mode: int)` | AppStateResource (setter) | Camera, ControlMaster, InputIndicator | Mode 切换（NONE/FOLLOW/GOTO） |
| `cmd_send(vehicle_id: String, cmd: Dictionary)` | ControlMaster, VehiclePanel, VehiclePanelManager | WebSocketManager | PC → 小车控制指令 |
| ⚠️ `zoom_changed(zoom: float)` | ❌ 未定义 | ZoomSlider emit/connect 但信号不存在 | 🔴 待修复 |
| ⚠️ `voxel_received(voxels: Array)` | ❌ 未定义 | Renderer3D connect 但信号不存在 | 🔴 待修复 |
| ⚠️ `path_received(path: Array)` | ❌ 未定义 | Renderer3D connect 但信号不存在 | 🔴 待修复 |

## 数据流

### map_full（二进制帧）

```
小车 ──WS Binary──→ WebSocketClient._read_packets()
                      └── MessageParser.parse_binary(pkt)
                            └── EventBus.map_full_received.emit(chunk_x, chunk_y, cells)
                                  └── MapData2D.set_full(chunk_x, chunk_y, cells)
                                        ├── 写入 ChunkData2D.cells
                                        └── EventBus.chunk_updated.emit(chunk_x, chunk_y)
                                              └── Renderer2D._on_chunk_updated()
                                                    ├── %MapData2D.get_chunk_cells(chunk_x, chunk_y)
                                                    └── MapContainer2D.render_chunk(chunk_x, chunk_y, cells)
                                                          ├── GroundLayer.set_cells_terrain_connect()  ← state=0
                                                          └── WallLayer.set_cells_terrain_connect()    ← state=1
```

### map_delta（JSON 增量）

```
小车 ──WS Text──→ WebSocketClient._on_message()
                    └── MessageParser.parse_json() → type="map_delta"
                          └── EventBus.map_delta_received.emit(voxels)
                                └── MapData2D.set_delta(voxels)
                                      ├── _group_by_chunk() → 按 Chunk 分组
                                      ├── set_chunk_delta(cx, cy, updates)
                                      └── EventBus.cells_changed.emit(updates)
                                            └── Renderer2D._on_cells_changed()
                                                  └── MapContainer2D.update_cells(updates)
```

### pose（车辆位姿）

```
小车 ──WS Text──→ WebSocketClient._on_message()
                    └── MessageParser.parse_json() → type="pose"
                          └── EventBus.pose_received.emit(vehicle_id, pose_data)
                                ├── Renderer2D._on_pose(vehicle_id, pose)
                                │     ├── CoordUtils.real_to_game(x, z) → position
                                │     └── rotation = yaw
                                ├── Camera._on_pose(vehicle_id, pose)  [仅 FOLLOW + 匹配时]
                                │     └── 更新 lerp 目标
                                └── VehiclePanelManager._on_pose(vehicle_id, pose)
                                      └── VehiclePanel.Update(id, pos, yaw, vel)
```

### Mode 状态机

```
                         button_list: Goto toggle            button_list: Lock Camera toggle
                    ┌──────────→  GOTO  ←─────────────────────────────┐
                    │     ↑        │  ↑                                │
                    │     │ 点击地图│  │ button_list: Goto toggle       │
                    │     │ 自动退出│  └──────→ NONE ←──────┘          │
                    │     │        │           ↑  │                    │
                    │     └────────┘           │  │ vehicle_unregistered│
                    │                          │  │ (仅 FOLLOW 时退出)  │
                    └──── FOLLOW ←─────────────┘  └────────────────────┘
                          ↑  │
                          │  │ button_list: Lock Camera toggle
                          └──┘

AppStateResource.mode setter → EventBus.mode_transited.emit(mode) → 各组件响应:
  Camera:       FOLLOW → State.FOLLOW, 其他 → State.IDLE
  InputIndicator: GOTO → State.ACTIVE, 其他 → State.IDLE
  ControlMaster:  GOTO → State.GOTO,   其他 → State.IDLE
```

### 选中 / 取消选中

```
用户点击 VehiclePanel.TakeControl 按钮
  └── VehiclePanel.take_control_toggled(vehicle_id, pressed)
        └── VehiclePanelManager._on_take_control_toggled()
              ├── pressed=true:  释放旧车(→switch_to_auto), app_state.selected_id = 新车
              ├── pressed=false: 释放当前(→switch_to_auto), app_state.selected_id = ""
              └── AppStateResource.selected_id setter → EventBus.selection_changed.emit(id)
```

### cmd（控制指令）

```
Manual 模式（键盘）:
  用户按 W/A/S/D/Space
    └── InputHandler._input() → MessageBuilder.build_manual_action/stop()
          └── ControlMaster._on_ctrl_input(cmd)
                ├── 若 app_state.selected_id 为空 → 忽略
                └── EventBus.cmd_send.emit(selected_id, cmd)

Goto 模式（鼠标点击）:
  用户点击 tile
    └── ControlMaster._input()
          ├── CoordUtils.game_to_tile() → CoordUtils.tile_to_real() → (x, y) 米
          ├── MessageBuilder.build_auto_push_goto(x, y)
          ├── EventBus.cmd_send.emit(selected_id, cmd)
          └── app_state.mode = NONE（自动退出）

下行:
  EventBus.cmd_send → WebSocketManager._on_cmd_send(vehicle_id, cmd)
        └── _vehicles[vehicle_id].send(JSON.stringify(cmd))
              └── 小车收到 cmd
```

### 车辆注册 / 注销

```
hello 包到达
  └── EventBus.vehicle_registered(vehicle_id, url)
        ├── WebSocketManager._on_vehicle_registered()
        │     └── _vehicles[url] → _vehicles[vehicle_id]（key 替换）
        ├── Renderer2D._on_vehicle_registered()
        │     └── vehicle_scene.instantiate() → VehicleContainer.add_child()
        └── VehiclePanelManager._on_vehicle_registered()
              └── vehicle_panel_scene.instantiate() → add_child()

连接断开
  └── EventBus.vehicle_unregistered(vehicle_id)
        ├── Renderer2D._on_vehicle_unregistered() → queue_free()
        ├── VehiclePanelManager._on_vehicle_unregistered() → queue_free()
        │     └── 若 vehicle_id == selected_id → selected_id = ""，FOLLOW → NONE
        └── Camera._on_vehicle_unregistered(vehicle_id)
              └── 若跟随后断开 → _state = IDLE
```

## WebSocket

### WebSocketClient

每个小车连接对应一个 WebSocketClient 实例。

- `init(url)` — 设置地址，`_ready()` 自动发起连接
- `send(msg)` — 发送 JSON 文本帧
- 消息处理：文本帧 → `MessageParser.parse_json(text)` 解析后按 type 分发；二进制帧 → `MessageParser.parse_binary(pkt)` 解析
- `hello` 包机制：收到 `hello` 前所有消息丢弃，收到后设 `_identified = true` 并 emit `vehicle_registered`
- 二进制帧支持：type=0 → map_full（emit `map_full_received`）

### WebSocketManager

总管所有连接，维护 `_vehicles: Dictionary`。

- `create_connection(url)` — 实例化 WebSocketClient，以 `url` 为临时 key 存入 `_vehicles`
- `close_connection(vehicle_id)` — `queue_free()` 对应 WebSocketClient，emit `vehicle_unregistered`
- `_on_vehicle_registered(vehicle_id, address)` — 将 `_vehicles[address]` 替换为 `_vehicles[vehicle_id]`
- `_on_client_disconnected(client)` — 自动清理断开连接

## WebSocket 协议

详见 `docs/websocket_protocol.md`。关键点：

| 项目 | 值 |
|------|------|
| 格式 | JSON 文本 + 二进制帧混用 |
| 连接确认 | `hello` 包（第一帧，必选） |
| map_full | 二进制帧，65545 bytes（1+4+4+65536） |
| map_delta | JSON 文本 |
| pose | JSON 文本 |
| cmd | JSON 文本，通过 MessageBuilder 构造 |

## 坐标系

| 项目 | 真实世界 | 游戏世界 (Godot 2D) |
|------|---------|---------------------|
| 单位 | 1 米 | 32 像素 |
| 1 tile | 0.5m × 0.5m | 16 像素 |
| Chunk | 256×256 tile = 128m×128m | — |

坐标转换由 `CoordUtils`（`src/utils/coords.gd`）统一处理：

```gdscript
const SCALE := 32.0
const TILE_SIZE := 16.0

# 真实世界 → Godot 2D
static func real_to_game(x: float, z: float) -> Vector2
static func game_to_real(pos: Vector2) -> Dictionary

# tile 网格转换
static func game_to_tile(world_pos: Vector2) -> Vector2i  # px → tile 网格
static func tile_to_game(gx: int, gy: int) -> Vector2      # tile → 中心 px
static func tile_to_real(gx: int, gy: int) -> Vector2      # tile → 米

# Godot 3D
static func real_to_game_3d(x: float, y: float, z: float) -> Vector3
```

⚠️ **已知问题**：3D 渲染器（`renderer_3d/`）中硬编码 `SCALE := 16.0`，与 CoordUtils 的 `32.0` 不一致，多车 3D 渲染暂不可用。

## 多车数据模型

三个总管统一用 `Dictionary{vehicle_id → ...}` 管理各自资源：

```
WebSocketManager    _vehicles:   {vehicle_id → WebSocketClient}
Renderer2D          _vehicles:   {vehicle_id → Node2D (Vehicle2D)}
VehiclePanelManager _panels:     {vehicle_id → VehiclePanel}
AppStateResource    selected_id: String  ← 当前选中的车辆
```

车辆生命周期：`ws_connect_requested` → 创建 WebSocketClient → `hello` → `vehicle_registered` → 创建 Sprite + Panel → `disconnect` → `vehicle_unregistered` → 清理全部资源。

## 已知问题

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🔴 | `zoom_changed` 信号未定义 | event_bus.gd / zoom_slider.gd |
| 🔴 | `voxel_received` 信号未定义 | event_bus.gd / renderer_3d.gd |
| 🔴 | `path_received` 信号未定义 | event_bus.gd / renderer_3d.gd |
| 🟡 | SCALE 不一致：3D 渲染器硬编码 16.0 vs CoordUtils 32.0 | renderer_3d/ |
| 🟡 | GOTO 模式下车辆断开未自动退出 GOTO | vehicle_panel_manager.gd |
| 🟡 | selection_changed / ws_connected 无人监听 | event_bus.gd |
| 🟡 | 地图持久化 `_save_chunk` 调用被注释 | map_data_2d.gd |
| 🟢 | 三处重复的 cell 统计 DEBUG 代码 | ws_client / map_data_2d / renderer_2d |
| 🟢 | help_label 文本过时，未提及 Lock Camera / Goto | help_label.gd |
