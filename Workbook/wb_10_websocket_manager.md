# wb_10_websocket_manager

## meta
- task: task_10_websocket_manager
- start: 2026-07-12
- status: in_progress

## decisions
- WebSocketClient._on_message → 直接 emit EventBus（无中间层）
  - note: 后续可能有其他设计，当前选择最短路径
- WebSocketClient.send() — 只提供发送方法，cmd 路由暂不讨论

## implemented
- 2026-07-12: 合并 `websocket_client/` → `websocket/`
- 2026-07-12: WebSocketClient 重写（send 报错无缓存, _on_message JSON→EventBus）
- 2026-07-12: WebSocketManager 重写（extends Node, 无 UI, Dictionary{url→WS}）
- 2026-07-12: EventBus 精简为 5 信号（pose, map_full, map_delta, chunk_updated, ws_connected）
- 2026-07-12: Renderer2D 移除 zoom_changed, MapData2D 订阅新信号

## test_infra
- 2026-07-13: 删除 test/，创建 test_tool/
- 2026-07-13: mock_vehicle.py — 先发 map_full(50×50) → 再循环发 pose(1Hz)
- 2026-07-13: main 挂 WebSocketManager，自连 ws://127.0.0.1:9090

## ws_buffer_issue
- date: 2026-07-13
- Godot WebSocketPeer 默认 inbound_buffer_size = 65535 (64KB)
- map_full 消息 137KB 超出默认缓冲 → WebSocketPeer 内部断开
- 修复: `_ws.inbound_buffer_size = 1 << 20` (1MB)
- 注: 后续如需发更大 Chunk (256×256≈2.6MB)，需进一步增大或改用分片
