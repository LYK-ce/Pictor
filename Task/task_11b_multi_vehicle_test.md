# Task 11b: 多车测试 — 3 车模拟

## 目标

在 Godot 内模拟 3 辆小车，验证多车连接的完整链路。

```
car_a (9090) → hello + map_full + pose (10Hz)
car_b (9091) → hello + pose (10Hz)
car_c (9092) → hello + pose (10Hz)
```

## 改动

### test_ws_server.gd

- [ ] 新增 `vehicle_id` 和 `port` 导出变量
- [ ] 握手完成后先发 `hello`（第一帧）
- [ ] 新增 `send_map` 开关：car_a 发 map_full，其余不发
- [ ] pose 频率统一 10Hz

### main.gd

- [ ] 加载 test_ws_server.gd，创建 3 个实例：
  - car_a: port=9090, send_map=true
  - car_b: port=9091, send_map=false
  - car_c: port=9092, send_map=false

## 测试流程

1. Godot 运行 → 自动启动 3 个 TestWSServer
2. 点击 Connect → 输入 `127.0.0.1:9090` → 创建（car_a + 地图渲染）
3. 点击 Connect → `127.0.0.1:9091` → 创建（car_b）
4. 点击 Connect → `127.0.0.1:9092` → 创建（car_c）
5. 观察左侧面板：3 辆车信息实时更新
6. 观察地图：car_a 的地图渲染，3 辆小车随机移动

## 预期结果

```
WebSocketMenu:
  ├── vehicle_panel "car_a" → ID:car_a, Pose:45°, Pos:5.2,3.1
  ├── vehicle_panel "car_b" → ID:car_b, Pose:120°, Pos:8.1,2.7
  └── vehicle_panel "car_c" → ID:car_c, Pose:270°, Pos:3.5,9.4

Renderer2D:
  ├── car_a Sprite (Vehicle2D)
  ├── car_b Sprite
  └── car_c Sprite
```

## 状态

- [x] 1. 更新 test_ws_server.gd
- [x] 2. 更新 main.gd
- [ ] 3. 手动测试验证
