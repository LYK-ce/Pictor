# Task 10: WebSocket Manager

## 目标

重构 WebSocket 模块，合并 `websocket_client/` 和 `websocket/` 为统一目录。

## 待完成

- [x] 合并 `src/websocket_client/` → `src/websocket/`
  - 移动 `websocket_client.gd` + `websocket_client.tscn`
  - 删除 `src/websocket_client/` 目录
  - 更新所有引用路径

- [x] `WebSocketManager` 逻辑与 UI 分离
  - 改为 `extends Node`（当前 `extends Control`）
  - 移除 UI 相关代码
  - 保留：连接创建/销毁、WebSocketClient 管理、状态查询

- [x] `WebSocketClient` 重写
  - send() 未连接报错，无缓存
  - _on_message JSON 解析 → EventBus emit

- [x] `EventBus` 信号精简
  - 新增 `map_full_received`、`map_delta_received`
  - 移除 `voxel_received`、`path_received`、`ctrl_send`、`zoom_changed`

## 状态

### WebSocketManager API

```gdscript
# 存储结构: Dictionary{url → WebSocketClient}
var _connections: Dictionary = {}

func create_connection(url: String) -> void     # 新建 WebSocketClient
func close_connection(url: String) -> void      # 断开并移除
func get_connections() -> Array[String]          # 所有活跃 URL
func get_state(url: String) -> int               # 查询连接状态
```

- URL 作为 key，天然去重
- WebSocketClient 自身持有 `_url`、`_state`、消息收发逻辑

### WebSocketClient 重构

```gdscript
# 发送：未连接则报错，不缓存
func send(msg: String) -> void
```

- 移除 `_pending_messages` 队列
- 移除 `_ready()` 中的 `ProjectSettings` 配置读取（由 Manager 传 URL）
- 移除 `EventBus.ctrl_send` 订阅（收发由外部驱动）

收侧：收到文本 → JSON 解析 → 按 `type` 分发 EventBus：

```gdscript
func _on_message(text: String) -> void:
    # parse JSON → match type:
    #   "pose"       → EventBus.pose_received.emit(data)
    #   "map_full"   → EventBus.map_full_received.emit(voxels)
    #   "map_delta"  → EventBus.map_delta_received.emit(voxels)
```

### EventBus 上行信号变更

```gdscript
signal pose_received(pose: Dictionary)
signal map_full_received(voxels: Array)
signal map_delta_received(voxels: Array)
signal ws_connected
```

- `voxel_received(voxels, is_full)` → 拆为 `map_full_received` + `map_delta_received`
- 移除 `path_received`（Task 9 已删）
- 移除 `ctrl_send`（cmd 路由暂不讨论）
- 移除 `zoom_changed`

信号流向：

| 信号 | 发送者 | 接收者 | 说明 |
|------|------|------|------|
| `pose_received` | WS Client | Renderer2D | 更新车辆位姿 |
| `map_full_received` | WS Client | MapData2D | 全量地图 |
| `map_delta_received` | WS Client | MapData2D | 增量地图 |
| `chunk_updated` | MapData2D | Renderer2D | 触发局部重绘 |
| `ws_connected` | WS Client | Renderer2D | 收到后创建 vehicle 实例 |

### 协议坐标系对齐

- [x] 更新 `docs/websocket_protocol.md`
  - 坐标系：2D 用 `(x, y)`，3D 高度用 `z`，与 Godot 统一
  - voxel 字段 `gx, gy` 为 2D 网格坐标，`gz` 为高度层
  - pose 字段 `x, y` 为 2D 世界坐标，`z` 为高度
  - 消息类型 `voxel_full` → `map_full`，`voxel_delta` → `map_delta`，移除 `path`

## 状态

- [x] 已完成 (2026-07-13)

## 新任务

### 重构测试方案

- [x] 删除 `test/` 目录（所有 `.gd` 测试脚本）
- [x] 创建 `test_tool/` 目录，仅保留 Python 工具
  - 移入 `test/test_tool/mock_car_server.py`
  - 删除 `mock_car_server_3d.py`
- [x] 修复 `mock_vehicle.py` — 按 Chunk 粒度发送数据
  - 改为发送完整 256×256 chunk(0,0) 数据
- [x] 更新 `main.gd` + `main.tscn` 测试流程
  - Main 启动后挂载 WebSocketManager
  - 自动 `create_connection("ws://localhost:9090")`
  - 连接 → 收 map_full → MapData2D 更新 → Renderer2D 渲染
  - 测试流程：先启 mock_vehicle.py → 再启 Godot → 看到地图即通过
- [ ] 后续测试以 Python mock server 为主，配合 Godot 编辑器手动验证

## 状态

- [ ] 进行中
