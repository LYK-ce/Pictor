# Pictor

Pleiades 系统的 Godot 可视化与控制终端。通过 WebSocket 与小车端双向通信，实时渲染 2D 地图和车辆位姿。

## 快速开始

1. Godot 4.x 打开项目
2. 运行 `src/main/main.tscn`
3. 点击左上角 **Connect** → 输入地址端口 → 创建连接

## 场景结构

```
Main
├── MapData2D          ← 地图数据层 (Chunk 256×256)
├── Renderer2D         ← 2D 渲染器
│   ├── MapContainer2D ← GroundLayer + WallLayer (TileMapLayer)
│   └── VehicleContainer
├── WebSocketManager   ← 多连接管理
└── WebSocketMenu      ← 连接 UI
```

## 目录

```
src/
├── event_bus/         ← EventBus Autoload 信号
├── main/              ← 入口场景
├── websocket/         ← WebSocket 客户端 + 管理器
├── renderer_2d/       ← 2D 地图渲染 + 车辆
├── renderer_3d/       ← 3D 渲染（预留）
├── input_handler/     ← 键盘输入
├── ui/                ← UI 组件
└── utils/             ← CoordUtils 坐标转换
```

## 通信协议

见 [docs/websocket_protocol.md](docs/websocket_protocol.md)
