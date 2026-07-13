# Pictor Architecture

## 概述

Pictor 是 Pleiades 系统的 Godot 可视化与控制终端。通过 WebSocket 与小车端 Pleiades 双向通信。

## 场景结构

```
Main (Node, main.gd)
├── MapData2D (Node, unique_name)     ← 地图数据层，%MapData2D 全局访问
└── Renderer2D (Node2D)              ← 2D 渲染器
    ├── MapContainer2D (Node2D)      ← 地图渲染（GroundLayer + WallLayer）
    │   ├── GroundLayer (TileMapLayer)
    │   └── WallLayer (TileMapLayer)
    └── VehicleContainer (Node2D)    ← 车辆挂载点 + Camera2D
```

## 目录结构

```
src/
├── event_bus/
│   └── event_bus.gd
├── main/
│   ├── main.gd
│   └── main.tscn
├── websocket/
│   ├── websocket_client.gd
│   ├── websocket_client.tscn
│   ├── websocket_manager.gd
│   └── websocket_manager.tscn
├── renderer_2d/
│   ├── renderer_2d.gd
│   ├── renderer_2d.tscn
│   ├── map_data_2d.gd
│   ├── map_data_2d.tscn
│   ├── chunk_data_2d.gd
│   ├── map_container_2d.gd
│   ├── map_container_2d.tscn
│   └── Vehicle/
│       └── vehicle_2d.tscn
└── utils/
    └── coords.gd
```

## 地图存储架构

```
MapData2D (Node, %MapData2D)
├── Chunk: 256×256 格，PackedByteArray
│   └── cells[index] = 0 → 可通行, 1 → 不可通行
├── SparseChunkMap: Dictionary{Vector2i(cx,cy) → ChunkData2D}
├── 持久化: user://map_data_2d/map_chunk_{x}_{y}.tres
└── API:
    ├── set_full(voxels) / set_delta(voxels)
    ├── get_cell(gx, gy) → int
    ├── get_chunk_cells(cx, cy) → PackedByteArray
    └── load_chunk(cx, cy) → PackedByteArray
```

## EventBus 信号

| 信号 | 发送者 | 接收者 | 说明 |
|------|------|------|------|
| `pose_received(pose)` | WS Client | Renderer2D | 车辆位姿 |
| `map_full_received(voxels)` | WS Client | MapData2D | 全量地图 |
| `map_delta_received(voxels)` | WS Client | MapData2D | 增量地图 |
| `chunk_updated(cx, cy)` | MapData2D | Renderer2D | Chunk 更新 → 重绘 |
| `ws_connected` | WS Client | Renderer2D | 连接后创建车辆 |

## 数据流

```
小车 ──WS──→ WebSocketClient
                ├── map_full/map_delta ──EventBus──→ MapData2D ──chunk_updated──→ Renderer2D.MapContainer2D
                ├── pose ──EventBus──→ Renderer2D.Vehicle
                └── ws_connected ──EventBus──→ Renderer2D (创建车辆)
```

## WebSocket

### WebSocketClient
- `init(url)` — 设置地址，`_ready()` 自动连接，断线自动重连
- `send(msg)` — 发送 JSON 文本，未连接报错
- 收到消息 → JSON 解析 → `match type` → EventBus emit

### WebSocketManager
- `create_connection(url)` / `close_connection(url)`
- `get_connections()` / `get_state(url)`
- Dictionary{url → WebSocketClient}

## 坐标系

| 项目 | 真实世界 | 游戏世界 (Godot) |
|------|------|------|
| 单位 | 1 米 | 16 游戏单位 |
| 地图 1 格 | 1m × 1m | 1×1 TileMap 坐标 |

真实世界 (x, y) → Godot `position = Vector2(x * 16, y * 16)`（CoordUtils）
