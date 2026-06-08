# Task 5: 集成测试工具 & 端到端验证

## 目标

使用 Python 实现一个小车端模拟器，在本地完成 Pictor（Godot）↔ Pleiades（模拟）的 WebSocket 闭环测试，验证整个通信链路。

## 文件位置

- 工具：`test/test_tool/mock_car_server.py`
- 依赖：`test/test_tool/requirements.txt`

## 整体架构

```
Pictor (Godot)                           test_tool (Python)
                                                  
WebSocketClient ──── ws://localhost:9001 ────→  mock_car_server.py
     │                                              │
     │  ← pose / voxel_full / voxel_delta / path ──  定时发送 mock 数据
     │  ── ctrl ──────────────────────────────────→  接收并打印指令
```

## mock_car_server 功能

1. 启动 WebSocket Server，监听 `ws://0.0.0.0:9001`
2. 客户端连接后：
   - 发送一次 `voxel_full`（模拟已建好的地图）
   - 以 10Hz 频率发送 `pose`（模拟车辆移动）
   - 发送一次 `path`（模拟规划路径）
   - 随机发送 `voxel_delta`（模拟新发现的障碍物）
3. 接收来自 Pictor 的 `ctrl` 消息，打印到终端
4. 支持多客户端连接
5. `Ctrl-C` 优雅退出

## mock 数据设计

### 初始地图 voxel_full
- 10×10 网格，四周为占用（模拟围墙），内部为空

### 车辆 pose
- 初始位置 (0, 0, 0)
- 随时间沿 path 移动（模拟自动导航）
- 若收到 `ctrl` 指令，按指令调整速度和方向

### 规划路径 path
- 从起点到目标点的一条直线路径

### 动态障碍物 voxel_delta
- 每隔 5 秒在路径前方随机放置一个临时障碍物

## 技术选型

使用 Python 标准库 `asyncio` + `websockets`：

```
pip install websockets
```

## 运行方式

```bash
# 1. 启动模拟小车
cd test/test_tool
pip install -r requirements.txt
python mock_car_server.py

# 2. 启动 Pictor（本地 Godot 编辑器）
godot --path .

# 3. 观察：
#    - Godot 终端收到 pose/voxel/path 日志
#    - Python 终端打印收到的 ctrl 指令（WASD 按键）
```

## 测试用例（验证清单）

| # | 测试项 | 预期 |
|------|------|------|
| 1 | Pictor 连接成功 | Python 打印 "client connected" |
| 2 | 收到 voxel_full | Godot 终端输出体素数量 |
| 3 | 收到连续 pose | 每秒约 10 条 pose 更新 |
| 4 | 收到 path | Godot 终端输出路径点数量 |
| 5 | 按 W 键 | Python 打印 `ctrl: w press` |
| 6 | 松 W 键 | Python 打印 `ctrl: w release` |
| 7 | 按 Space | Python 打印 `ctrl: space press` |
| 8 | 断线重连 | Python 打印新的连接 |

## 实施步骤

1. 创建 `test/test_tool/requirements.txt`
2. 创建 `test/test_tool/mock_car_server.py`
3. 本地运行验证完整闭环

## 依赖

- [x] WebSocketClient (task_4)
- [x] InputHandler (task_3)
- [x] EventBus (task_2)
- [x] 通信协议（docs/protocol.md）
- Python 3.8+ with `websockets`

## 状态

- [x] 已完成 (2026-06-08)
