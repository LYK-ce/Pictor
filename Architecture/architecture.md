# Pictor Architecture

## 概述

Pictor 是 Pleiades 系统的 Godot 可视化与控制终端。通过 WebSocket 与小车端 Pleiades 双向通信。

## 场景结构

```
Main (Node)
├── WebSocketClient
├── InputHandler
└── Renderer (2D 或 3D)
```

**所有组件只与 EventBus 通信，彼此零引用。**

## 目录结构

```
src/
├── event_bus/            EventBus Autoload（纯脚本，无 scene）
│   └── event_bus.gd
├── websocket_client/     WebSocket 连接管理
│   ├── websocket_client.gd
│   └── websocket_client.tscn
├── input_handler/        键盘输入 → ctrl 消息
│   ├── input_handler.gd
│   └── input_handler.tscn
├── renderer_2d/          2D 俯视渲染
│   ├── renderer_2d.gd
│   ├── renderer_2d.tscn
│   ├── map_container_2d.gd
│   ├── map_container_2d.tscn
│   ├── vehicle_marker_2d.gd
│   ├── vehicle_marker_2d.tscn
│   ├── path_line_2d.gd
│   └── path_line_2d.tscn
├── renderer_3d/          3D 透视渲染
│   ├── renderer_3d.gd
│   ├── renderer_3d.tscn
│   ├── map_container_3d.gd
│   ├── vehicle_marker_3d.gd
│   ├── path_line_3d.gd
│   └── camera_rig.gd
└── main/                 主场景 + 启动逻辑
    ├── main.gd
    └── main.tscn

test/                     组件测试（headless 运行）
├── event_bus/
│   └── test_event_bus.gd
├── websocket_client/
│   └── test_websocket.gd
├── input_handler/
│   └── test_input.gd
├── renderer_2d/
│   ├── test_map_container.gd
│   ├── test_vehicle_marker.gd
│   └── test_path_line.gd
└── test_tool/             Python 小车模拟器
    ├── mock_car_server.py
    └── requirements.txt
```

### Renderer 变体

| 模式 | 类 | 根节点 | 渲染方式 |
|------|------|------|------|
| 2D | `Renderer2D` | Node2D | 俯视图，矩形/圆形/线条 |
| 3D | `Renderer3D` | Node3D | 透视，立方体/模型/3D 线条 |

启动时 `Main` 读取配置项 `renderer/mode`，实例化对应 Renderer：

```
renderer/mode = "2d"  →  add_child(Renderer2D)
renderer/mode = "3d"  →  add_child(Renderer3D)
```

两个 Renderer 实现相同信号接口，对外透明。

## 运行模式

| 模式 | 场景组件 | 用途 |
|------|------|------|
| 🎮 **控制模式** | Main + InputHandler + WebSocketClient | 纯键盘遥控小车，无需 Renderer |
| 🗺️ **2D 可视化** | + Renderer2D | 俯视地图渲染 + 遥控 |
| 🗺️ **3D 可视化** | + Renderer3D | 3D 地图渲染 + 遥控 |

## 通信协议

- **传输**：WebSocket（全双工，单连接）
- **格式**：JSON 文本消息
- **方向**：双向
- **角色**：小车 = Server，PC = Client

### 小车 → PC（上行）

| type | 内容 | 频率 |
|------|------|------|
| `voxel_full` | 全量体素数组 | 初始化 / 重连 |
| `voxel_delta` | 增量体素更新 | 实时 |
| `pose` | 车辆位置/朝向/速度 | 10-30 Hz |
| `path` | 规划路径点序列 | 规划更新时 |

### PC → 小车（下行）

| type | 内容 |
|------|------|
| `ctrl` | 键盘：`w`/`s` 前后，`a`/`d` 原地旋转，`space` 急停（坦克式操纵） |

## 组件职责

### EventBus (Autoload)
- 全局单例，组件间唯一通信通道
- 定义 4 个信号

| 信号 | 数据 | 发送者 → 接收者 |
|------|------|------|
| `pose_received(dict)` | 车辆位姿 | WebSocket → Renderer |
| `voxel_received(array, is_full)` | 体素列表 | WebSocket → Renderer |
| `path_received(array)` | 路径点 | WebSocket → Renderer |
| `ctrl_send(dict)` | 控制指令 | InputHandler → WebSocket |

### InputHandler
- 捕获键盘事件（`_input`）
- WASD 转换为 `ctrl` JSON
- `EventBus.ctrl_send.emit(msg)`

### WebSocketClient
- 连接管理 + 自动重连
- JSON 解析/序列化
- 收到消息 → `EventBus.xxx.emit()`
- 订阅 `EventBus.ctrl_send`，发送到小车

### Renderer (2D)
- 俯视图，Node2D
- MapContainer：矩形色块（按状态/置信度着色）
- VehicleMarker：圆形 + 方向箭头
- PathLine：线条连接路径点
- 相机：正交俯视，滚轮缩放，中键拖拽

### Renderer (3D)
- 透视视角，Node3D
- MapContainer：MultiMeshInstance3D 立方体
- VehicleMarker：3D 模型 + 速度矢量
- PathLine：3D 线条 + 目标高亮
- 相机：CameraRig 自由视角

## 数据流

```

小车 ──ws──→ WebSocketClient ──emit──→ EventBus ──on──→ Renderer
键盘 ──────→ InputHandler    ──emit──→ EventBus ──on──→ WebSocketClient ──ws──→ 小车
```

## 坐标系

### 真实世界 → 游戏世界转换

| 项目 | 真实世界 | 游戏世界 (Godot) |
|------|------|------|
| 单位 | 1 米 | 16 游戏单位 |
| 转换公式 | — | `game = real × 16` |
| 地图 1 格 | 1m × 1m | 16×16 px (TileMap 默认 tile_size) |

### 坐标轴

```
真实世界:          游戏世界 (Godot 2D):
    +Z (南)            +Y (下)
     ↑                  ↑
     |                  |
     +----→ +X (东)     +----→ +X (右)
```

真实世界的 (x, z) 映射到游戏世界的 (x, z) → Godot `position = Vector2(x × 16, z × 16)`。

`yaw` 角度：
- `yaw = -π/2` → 朝北（-Z，游戏世界 -Y）— **默认朝向**
- `yaw = 0`    → 朝东（+X，游戏世界 +X）
- `yaw = π/2`  → 朝南（+Z，游戏世界 +Y）
- A/D 键：减小/增大 yaw，即左旋/右旋

### 应用位置

| 数据 | 转换入口 | 代码 |
|------|------|------|
| Vehicle pose | `vehicle_marker_2d.gd` | `position = Vector2(x * 16, z * 16)` |
| Path points | `path_line_2d.gd` | `Vector2(x * 16, z * 16)` |
| Voxel grid | TileMap 原生 | `set_cell(Vector2i(gx, gz))` — 无需转换，grid 坐标自动对