# Task 1: Main 场景搭建 & 集成

## 目标

创建项目入口场景 `main.tscn`，集成已完成的所有组件（WebSocketClient + InputHandler），通过 mock car server 完成端到端集成测试。

## 文件位置

- 场景：`src/main/main.tscn`
- 脚本：`src/main/main.gd`

## 功能

1. 读取 `renderer/mode` 配置，决定实例化 Renderer2D 还是 Renderer3D（当前暂无 Renderer，跳过）
2. 实例化 `WebSocketClient`（从 tscn 加载）
3. 实例化 `InputHandler`（从 tscn 加载）
4. 可选：实例化 Renderer

## 场景结构

```
Main (Node, main.gd)
├── WebSocketClient  (websocket_client.tscn)  ✅ task_4
├── InputHandler     (input_handler.tscn)     ✅ task_3
└── Renderer         (renderer_2d.tscn)       ⬜ task_6
```

EventBus 通过 Autoload 注入，不需要在场景中挂载。

## 实施步骤

1. 创建 `src/main/main.gd`
   - `_ready()`：读取 `renderer/mode`，实例化子组件
   - 若 mode="2d" 且 Renderer2D 存在 → 实例化
   - 实例化 WebSocketClient 和 InputHandler

2. 创建 `src/main/main.tscn`

3. 集成测试：
   - 启动 mock_car_server.py
   - `godot --headless --path . --script test/main/test_main.gd`
   - 验证 WebSocketClient 收到 voxel_full / path / pose
   - 验证 InputHandler ctrl → 转发到 WebSocket

## 依赖

- [x] EventBus (task_2)
- [x] InputHandler (task_3)
- [x] WebSocketClient (task_4)
- [x] 测试工具 (task_5)
- [ ] Renderer2D (task_6)

## 状态

- [x] 已完成 (2026-06-08)
