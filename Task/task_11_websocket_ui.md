# Task 11: WebSocket UI — 多车连接管理面板

## 目标

实现 WebSocket 多车连接管理的完整 UI 与业务逻辑。
三个总管统一用 `Dictionary{vehicle_id → ...}` 管理各自资源。

## 数据模型

```
WebSocketManager:     _vehicles: Dictionary{vehicle_id → WebSocketClient}
Renderer2D:           _vehicles: Dictionary{vehicle_id → Node2D}
VehiclePanelManager:  _panels:  Dictionary{vehicle_id → VehiclePanel}
```

## 实施步骤

### 1. 更新 EventBus

- [ ] 新增 `vehicle_registered(vehicle_id: String, url: String)`
- [ ] 新增 `vehicle_unregistered(vehicle_id: String)`
- [ ] 新增 `ws_disconnect_requested(vehicle_id: String)`
- [ ] `pose_received` 改为 `pose_received(vehicle_id: String, pose: Dictionary)`

### 2. 更新 WebSocketClient

- [ ] 解析 `hello` 消息，存储 `vehicle_id`
- [ ] 直接 emit `EventBus.vehicle_registered(vehicle_id, address)` — `hello` 里包含 `address` 字段
- [ ] `pose` / `map_full` / `map_delta` 带上 `vehicle_id` 转发
- [ ] `hello` 之前收到的消息丢弃

### 3. 更新 WebSocketManager

- [ ] `_vehicles: Dictionary{vehicle_id → WebSocketClient}`
- [ ] `create_connection` 时先按 `url` 暂存 key，等收到 `hello` 再替换为 `vehicle_id`
- [ ] 监听 `vehicle_registered` → 用 `address` 找到 client，替换 dictionary key
- [ ] 监听 `ws_disconnect_requested` → 执行 `close_connection`
- [ ] 连接断开时 emit `vehicle_unregistered`，清理映射

### 4. 更新 Renderer2D

- [ ] `_vehicles: Dictionary{vehicle_id → Node2D}`
- [ ] 监听 `vehicle_registered` → 创建 Sprite
- [ ] 监听 `pose_received` → O(1) 按 ID 更新
- [ ] 监听 `vehicle_unregistered` → 移除 Sprite

### 5. 更新 VehiclePanelManager

- [ ] `_panels: Dictionary{vehicle_id → VehiclePanel}`
- [ ] 监听 `vehicle_registered` → add panel
- [ ] 监听 `pose_received` → O(1) 按 ID 更新标签
- [ ] 监听 `vehicle_unregistered` → remove panel
- [ ] 断开按钮 → `EventBus.ws_disconnect_requested.emit(vehicle_id)`

## 依赖

- EventBus
- WebSocketManager / WebSocketClient
- Renderer2D / Vehicle2D
- vehicle_panel.tscn / vehicle_panel_manager.gd

## 状态

- [x] 1. 更新 EventBus
- [x] 2. 更新 WebSocketClient
- [x] 3. 更新 WebSocketManager
- [x] 4. 更新 Renderer2D
- [x] 5. 更新 VehiclePanelManager
- [x] 6. map_full 二进制帧重构 (2026-07-21)
- [x] 7. 3 车测试验证
- [x] 8. 断开/重连链路修复
- [x] 9. map_container_2d 跳过未知格子
