# Pictor Architecture

## 概述

Pictor 是 Pleiades 系统的 Godot 可视化与控制终端。通过 WebSocket 与小车端 Pleiades 双向通信，支持多车同时连接。

## 场景结构

主场景 `src/main/main.tscn` 预挂 4 个子节点：

```
Main (Node, main.gd)
├── MapData2D (Node, %MapData2D)     ← 地图数据层，unique_name 全局访问
├── Renderer2D (Node2D)              ← 2D 渲染器
│   ├── MapContainer2D (Node2D)      ← 地图渲染
│   │   ├── GroundLayer (TileMapLayer)
│   │   └── WallLayer (TileMapLayer)
│   └── VehicleContainer (Node2D)    ← 车辆 Sprite 动态挂载点
├── WebSocketManager (Node)          ← 多连接总管
│   └── WebSocketClient × N          ← 动态实例化，每车一个
└── WebSocketMenu (Control)          ← 连接 UI
    └── VehiclePanelManager          ← 车辆信息面板总管
        └── VehiclePanel × N         ← 动态实例化，每车一个
```

EventBus 通过 Autoload 注入，所有组件通过信号通信，无需场景挂载。

## 目录结构

```
src/
├── event_bus/
│   └── event_bus.gd                 ← Autoload 单例
├── main/
│   ├── main.gd                      ← 入口脚本
│   ├── main.tscn                    ← 入口场景
│   ├── menu.gd                      ← 渲染模式选择菜单（未挂载）
│   └── menu.tscn
├── websocket/
│   ├── websocket_client.gd          ← WS 连接组件
│   ├── websocket_client.tscn
│   ├── websocket_manager.gd         ← 多连接管理
│   └── websocket_manager.tscn
├── renderer_2d/
│   ├── renderer_2d.gd               ← 2D 渲染总管
│   ├── renderer_2d.tscn
│   ├── map_data_2d.gd               ← 地图数据（Chunk 存储）
│   ├── map_data_2d.tscn
│   ├── chunk_data_2d.gd             ← Chunk Resource 类型
│   ├── map_container_2d.gd          ← TileMapLayer 渲染
│   ├── map_container_2d.tscn
│   ├── vehicle_marker_2d.gd         ← 车辆三角形标记 + Camera2D
│   ├── vehicle_marker_2d.tscn
│   ├── path_line_2d.gd              ← 路径线条（Line2D）
│   ├── path_line_2d.tscn
│   └── Vehicle/
│       └── vehicle_2d.tscn          ← 车辆场景（预挂 Camera2D + _draw 三角形）
├── renderer_3d/
│   ├── renderer_3d.gd               ← 3D 渲染总管（未挂载，信号待修复）
│   ├── renderer_3d.tscn
│   ├── map_container_3d.gd          ← MultiMeshInstance3D 体素渲染
│   ├── map_container_3d.tscn
│   ├── vehicle_marker_3d.gd         ← 3D 车辆标记
│   ├── vehicle_marker_3d.tscn
│   ├── path_line_3d.gd              ← 3D 路径线条（ImmediateMesh）
│   └── path_line_3d.tscn
├── input_handler/
│   ├── input_handler.gd             ← 键盘 WASD 输入（未挂载，信号待修复）
│   └── input_handler.tscn
├── ui/
│   ├── ui.gd                        ← UI 父容器 CanvasLayer（未挂载）
│   ├── ui.tscn
│   ├── help_label.gd                ← 操作说明标签
│   ├── help_label.tscn
│   ├── zoom_slider/
│   │   ├── zoom_slider.gd           ← 缩放滑块（信号待修复）
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
4. 小车发送 hello → WebSocketClient._on_message("hello") → _identified = true
5. EventBus.vehicle_registered(vehicle_id, url) 发出
6. WebSocketManager 收到 → 将 _vehicles[url] 替换为 _vehicles[vehicle_id]
7. Renderer2D 收到 → 创建 Vehicle2D Sprite
8. VehiclePanelManager 收到 → 创建 VehiclePanel
9. hello 之后的数据（pose / map_full / map_delta）正常流转
```

## 地图存储架构

```
MapData2D (Node, %MapData2D)
├── Chunk 大小: 256×256 cells
├── Cell 编码: 0=可通行, 1=不可通行, 2=未知
├── 存储: Dictionary{Vector2i(chunk_x, chunk_y) → ChunkData2D}
├── 持久化: user://map_data_2d/map_chunk_{x}_{y}.tres
└── API:
    ├── set_full(chunk_x, chunk_y, cells: PackedByteArray)
    ├── set_delta(voxels: Array)
    ├── get_cell(gx, gy) → int
    ├── get_chunk_cells(cx, cy) → PackedByteArray
    └── load_chunk(cx, cy) → PackedByteArray
```

地图更新触发链：`set_full` / `set_delta` → 写入 ChunkData2D → 持久化 → `EventBus.chunk_updated.emit(chunk_x, chunk_y)` → Renderer2D 通知 MapContainer2D 重绘。

## EventBus 信号

| 信号 | 发送者 | 接收者 | 说明 |
|------|------|------|------|
| `pose_received(vehicle_id: String, pose: Dictionary)` | WebSocketClient | Renderer2D, VehiclePanelManager | 车辆位姿，含 x/y/z/yaw/vx/vy |
| `map_full_received(chunk_x: int, chunk_y: int, cells: PackedByteArray)` | WebSocketClient | MapData2D | 全量 Chunk（二进制帧） |
| `map_delta_received(voxels: Array)` | WebSocketClient | MapData2D | 增量地图（JSON） |
| `chunk_updated(chunk_x: int, chunk_y: int)` | MapData2D | Renderer2D | Chunk 变更 → 触发重绘 |
| `ws_connected` | WebSocketClient | （暂无接收者） | WebSocket 握手完成 |
| `ws_connect_requested(url: String)` | WebSocketCreationMenu | WebSocketManager | 用户请求连接 |
| `ws_disconnect_requested(vehicle_id: String)` | VehiclePanel | WebSocketManager | 用户请求断开 |
| `vehicle_registered(vehicle_id: String, url: String)` | WebSocketClient | WebSocketManager, Renderer2D, VehiclePanelManager | hello 包收到，身份确认 |
| `vehicle_unregistered(vehicle_id: String)` | WebSocketManager | Renderer2D, VehiclePanelManager | 连接断开，清理资源 |
| `vehicle_control_changed(vehicle_id: String)` | VehiclePanelManager | ControlMaster | 控制权切换，空字符串 = 释放 |
| `cmd_send(vehicle_id: String, cmd: Dictionary)` | ControlMaster | WebSocketManager | PC → 小车控制指令 |

## 数据流

### map_full（二进制帧）

```
小车 ──WS Binary──→ WebSocketClient._read_packets()
                      ├── 解析 [type:1][chunk_x:4][chunk_y:4][cells:65536]
                      └── EventBus.map_full_received.emit(chunk_x, chunk_y, cells)
                            └── MapData2D.set_full(chunk_x, chunk_y, cells)
                                  ├── 写入 ChunkData2D.cells
                                  ├── 持久化到 user://
                                  └── EventBus.chunk_updated.emit(chunk_x, chunk_y)
                                        └── Renderer2D._on_chunk_updated()
                                              ├── %MapData2D.get_chunk_cells(chunk_x, chunk_y)
                                              └── MapContainer2D.render_chunk(chunk_x, chunk_y, cells)
                                                    ├── GroundLayer.set_cells_terrain_connect()  ← state=0
                                                    └── WallLayer.set_cells_terrain_connect()    ← state=1
```

### map_delta（JSON 增量）

```
小车 ──WS Text──→ WebSocketClient._on_message("map_delta")
                    └── EventBus.map_delta_received.emit(voxels)
                          └── MapData2D.set_delta(voxels)
                                ├── _group_by_chunk() → 按 Chunk 分组
                                ├── set_chunk_delta(cx, cy, updates)
                                └── EventBus.chunk_updated.emit(cx, cy)
                                      └── [同 map_full 的重绘链路]
```

### pose（车辆位姿）

```
小车 ──WS Text──→ WebSocketClient._on_message("pose")
                    └── EventBus.pose_received.emit(vehicle_id, pose_data)
                          ├── Renderer2D._on_pose(vehicle_id, pose)
                          │     ├── CoordUtils.real_to_game(x, z) → position
                          │     └── rotation = yaw
                          └── VehiclePanelManager._on_pose(vehicle_id, pose)
                                └── VehiclePanel.Update(id, pos, yaw, vel)
```

### 选中 / 取消选中

```
用户点击 VehiclePanel.Control_Area
  └── gui_input → VehiclePanelManager._on_panel_gui_input(event, vehicle_id)
        ├── 切换逻辑：同一辆车 → 取消选中，否则切换
        ├── 遍历 _panels 更新 set_selected()
        └── EventBus.vehicle_control_changed.emit(vehicle_id | "")
              └── ControlMaster._on_vehicle_control_changed(vehicle_id)
                    └── 记录 _selected_id
```

### cmd（控制指令）

```
用户按 W/A/S/D/Space
  └── InputHandler._input() → signal ctrl_input(cmd)
        └── ControlMaster._on_ctrl_input(cmd)
              ├── 若 _selected_id 为空 → 忽略
              └── EventBus.cmd_send.emit(_selected_id, cmd)
                    └── WebSocketManager._on_cmd_send(vehicle_id, cmd)
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
        └── VehiclePanelManager._on_vehicle_unregistered() → queue_free()
```

## WebSocket

### WebSocketClient

每个小车连接对应一个 WebSocketClient 实例。

- `init(url)` — 设置地址，`_ready()` 自动发起连接
- `send(msg)` — 发送 JSON 文本帧
- 收到消息：先判断文本/二进制，文本 JSON 解析后 `match type` 分发，二进制帧按 type byte 分发
- `hello` 包机制：收到 `hello` 前所有消息丢弃，收到后设 `_identified = true` 并 emit `vehicle_registered`
- 二进制帧支持：type=0 → map_full（解析 chunk_x/chunk_y/cells 后 emit `map_full_received`）

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
| cmd | JSON 文本（PC → 小车） |

## 坐标系

| 项目 | 真实世界 | 游戏世界 (Godot 2D) |
|------|---------|---------------------|
| 单位 | 1 米 | 32 像素 |
| 地图 1 cell | 0.5m × 0.5m | — |
| Chunk | 256×256 cell = 128m×128m | — |

坐标转换由 `CoordUtils`（`src/utils/coords.gd`）统一处理：

```gdscript
const SCALE := 32.0

# 真实世界 (x, z) 米 → Godot 2D Vector2
static func real_to_game(x: float, z: float) -> Vector2:
    return Vector2(x * SCALE, z * SCALE)

# Godot 2D → 真实世界
static func game_to_real(pos: Vector2) -> Dictionary:
    return {"x": pos.x / SCALE, "z": pos.y / SCALE}

# 真实世界 (x, y, z) → Godot 3D Vector3
static func real_to_game_3d(x: float, y: float, z: float) -> Vector3:
    return Vector3(x * SCALE, y * SCALE, z * SCALE)
```

## 多车数据模型

三个总管统一用 `Dictionary{vehicle_id → ...}` 管理各自资源：

```
WebSocketManager    _vehicles:   {vehicle_id → WebSocketClient}
Renderer2D          _vehicles:   {vehicle_id → Node2D (Vehicle2D)}
VehiclePanelManager _panels:     {vehicle_id → VehiclePanel}
VehiclePanelManager _selected_id: String  ← 当前选中的车辆
```

车辆生命周期：`ws_connect_requested` → 创建 WebSocketClient → `hello` → `vehicle_registered` → 创建 Sprite + Panel → `disconnect` → `vehicle_unregistered` → 清理全部资源。
