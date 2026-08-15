# Task 4: WebSocketClient

## 目标

实现 WebSocket 通信组件，连接小车端 Pleiades，双向收发 JSON 消息。上行消息通过 EventBus 发射，下行 `ctrl` 消息从 EventBus 订阅并转发。

## 文件位置

- 脚本：`src/websocket_client/websocket_client.gd`
- 场景：`src/websocket_client/websocket_client.tscn`

## 功能

1. 连接到小车 WebSocket Server（`ws://IP:9001`）
2. 自动重连（断线后间隔重试）
3. 收到 JSON → 解析 → 按 type 分发到 EventBus
4. 订阅 `EventBus.ctrl_send` → 转发到小车
5. 连接状态对外可见

## 消息分发

| 收到 type | EventBus 信号 |
|------|------|
| `pose` | `EventBus.pose_received.emit(dict)` |
| `voxel_full` | `EventBus.voxel_received.emit(voxels, true)` |
| `voxel_delta` | `EventBus.voxel_received.emit(voxels, false)` |
| `path` | `EventBus.path_received.emit(points)` |

## 配置

在 `project.godot` 中添加：

```ini
[websocket]
url="ws://192.168.1.100:9001"
reconnect_interval=3.0
```

## 函数

| 函数 | 说明 |
|------|------|
| `_ready()` | 读取配置，连接 EventBus 信号，发起首次连接 |
| `_process(delta)` | 轮询 WebSocket 状态，收发消息 |
| `_connect()` | 发起 WebSocket 连接 |
| `_on_message(msg)` | 解析 JSON，按 type 分发 |
| `_on_ctrl(ctrl)` | 收到 EventBus ctrl_send → send_text 到小车 |
| `_send(msg)` | 发送 JSON 字符串 |

## 状态

| 状态 | 说明 |
|------|------|
| `STATE_DISCONNECTED` | 未连接 |
| `STATE_CONNECTING` | 正在连接 |
| `STATE_CONNECTED` | 已连接 |

## 实施步骤

1. 创建 `src/websocket_client/websocket_client.gd`
   - 继承 `Node`
   - 使用 `WebSocketPeer` 进行连接
   - `_process` 中轮询
   - 收到消息后 JSON.parse → 按 type emit EventBus
   - 订阅 `ctrl_send` → 转发

2. 创建 `src/websocket_client/websocket_client.tscn`

3. 更新 `project.godot` 配置

## 测试

- 文件：`test/websocket_client/test_websocket.gd`
- 运行：`godot --headless --display-driver headless --path . --script test/websocket_client/test_websocket.gd`

### 测试用例

1. **pose 消息分发**：模拟收到 `{"type":"pose",...}` → EventBus.pose_received emit
2. **voxel_full 消息分发**：`{"type":"voxel_full","voxels":[...]}` → voxel_received(voxels, true)
3. **voxel_delta 消息分发**：`{"type":"voxel_delta","voxels":[...]}` → voxel_received(voxels, false)
4. **path 消息分发**：`{"type":"path","points":[...]}` → path_received
5. **ctrl_send 转发**：EventBus.ctrl_send.emit → ws.send_text
6. **非 JSON 处理**：收到乱码不崩溃
7. **未知 type 处理**：收到 `{"type":"unknown"}` 不崩溃

### 测试实现注意

headless 模式无真实网络。测试应绕过 WebSocket 连接，直接调用消息处理函数。如需测试 WebSocket 真实通信，用 `test/` 下的辅助脚本启动一个本地 echo server。

## 依赖

- [x] EventBus (task_2)
- [x] 通信协议（docs/protocol.md）

## 状态

- [x] 已完成 (2026-06-08)
