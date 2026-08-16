# Pictor 桥接入改造方案（哑管道版）

> 更新：2026-08-16（按 Rust 桥「哑管道」最终架构重写，覆盖前版「桥解析/合并」方案）
> 状态：方案定稿，待实施（P3）
> 关联：`Task/task_23_pleiades_integration.md`

---

## 1. 架构结论

Rust 侧 `PleiadesKernel`（GDExtension）是**哑管道**：不解析、不合并业务数据，只透传两条总线的数据：

- `robot_bus` 原始 ORION 帧 → `robot_frame(data: PackedByteArray)`
- `event_bus` peer 事件 → `peer_discovered / peer_left / peer_connected / peer_disconnected / peer_info_updated`（peer_id 已统一 hex）

Godot 侧新增 `KernelBridge` 适配节点，把桥信号翻译成现有 EventBus 信号，**复用 WS 时代的接收 / 渲染 / 控制链路**。

```
Godot 进程（单进程）
├── KernelBridge（新）—— 挂 PleiadesKernel，每帧 poll()，信号翻译
│     ├── robot_frame → MessageParser.parse_orion_frame → EventBus（pose / map）
│     ├── peer_connected → EventBus.vehicle_registered（改 1 参）
│     ├── peer_disconnected / peer_left → EventBus.vehicle_unregistered
│     ├── peer_info_updated → EventBus.peer_info_updated（面板车名）
│     └── EventBus.cmd_send → OrionMessages.Build_Cmd → kernel.send_command(hex, frame)
├── PleiadesKernel（Rust GDExtension）
│     └── libp2p swarm（mDNS 发现 / gossipsub / Send_Data_Try）
└── 现有表现层（Renderer2D / VehiclePanelManager / Camera / ControlMaster 基本不动）
```

---

## 2. 已拍板决策（6 条，详见 Task 23）

| # | 决策 |
|---|------|
| 1 | peer_id 统一 hex（Rust 桥内 base58 → hex） |
| 2 | 地图原始帧透传；多车合并 + 返还合并全量**暂缓** |
| 3 | WebSocket **连接层**移除；`protocol/` 四件套保留复用 |
| 4 | `kernel_ready` 前 UI 门控**不做**（fire-and-forget） |
| 5 | poll 队列背压风险**后置** |
| 6 | 车辆注册/移除由 peer 事件驱动；Godot **不做**心跳超时清理 |

---

## 3. 桥信号 → EventBus 映射

| 桥信号 | EventBus | 说明 |
|---|---|---|
| `kernel_ready()` | —（忽略/日志） | 决策 #4 不做门控 |
| `robot_frame(data)` | 解析后 → `pose_received` / `map_full_received` / `map_delta_received` | `parse_orion_frame` 按 msgid 分发，`vehicle_id = hex(sysid)` |
| `peer_connected(hex)` | `vehicle_registered(hex)` | 创建 Sprite + 面板（签名改 1 参） |
| `peer_disconnected(hex)` | `vehicle_unregistered(hex)` | 移除 |
| `peer_left(hex)` | （不消费） | mDNS 过期 ≠ 断连，不映射移除 |
| `peer_discovered(hex)` | （预留，暂不消费） | 发现态，后续做节点列表 |
| `peer_info_updated(hex, name)` | `peer_info_updated(hex, name)`（新） | 面板显示车名 |

---

## 4. 车辆身份与生命周期

- 身份键 = `hex(sysid)`。`robot_frame` 帧头 `sysid` = 发送方完整 peer_id 字节，与 `peer_*` 事件已统一 hex。
- 生命周期：
  - `peer_connected` → `vehicle_registered` → Renderer2D 建 Sprite + VehiclePanelManager 建面板（面板名先显示「连接中」）
  - `peer_info_updated` → 面板 ID 标签换成车名
  - `peer_disconnected` → `vehicle_unregistered` → 清理（`peer_left` 不消费）
- UI 细节（已定）：面板初始显示「连接中」；Disconnect 按钮删除（桥模式无主动踢车）；`peer_discovered` 不消费，仅 `peer_connected` 建 panel。
- ⚠️ **必须改**：`MessageParser.parse_orion_frame` 现在把 `frame.sysid` 丢掉（返回值无 sysid），需加 `"sysid": frame.sysid` 字段，否则多车身份无法区分。

---

## 5. 地图数据流

`robot_frame`（MAP_FULL / MAP_DELTA 原始帧）→ `parse_orion_frame` →

- `MSGID_MAP_FULL(2)` → `map_full_received` → `MapData2D.set_full`
- `MSGID_MAP_DELTA(3)` → `map_delta_received` → `MapData2D.set_delta`（累加）→ `cells_changed` → `update_cells` 增量重绘

- 多车合并 + `map_merged` + 返还合并全量 = **暂缓**（`MapAccumulator` 不接入）。

---

## 6. 下行控制链路

- 不变：`control/` → `EventBus.cmd_send(targets, cmd)`
- 变：`cmd_send` 的消费方从 `WebSocketManager` → `KernelBridge`：
  - `OrionMessages.Build_Cmd(cmd)` → frame（拼帧逻辑完全复用）
  - `for id in targets: kernel.send_command(id, frame)`（fire-and-forget）
- `TASK_SET` members 填充逻辑（原 `WebSocketManager._on_cmd_send`）迁移到 KernelBridge。

---

## 7. 文件级修改清单

**新增**
- `src/kernel/kernel_bridge.gd`（+可选 `.tscn`）：挂 `PleiadesKernel`、每帧 `poll()`、7 信号翻译、`cmd_send` 下行转发
- `src/ui/WebSocket/vehicle_panel_manager.tscn`（面板管理器承载，从 websocket_menu 抽出）

**修改**
- `src/event_bus/event_bus.gd`：`vehicle_registered` 去 `url` 参；删 `ws_connect_requested` / `ws_disconnect_requested` / `ws_connected` / `map_merged`；新增 `peer_info_updated`
- `src/websocket/protocol/message_parser.gd`：`parse_orion_frame` 透传 `sysid`
- `src/renderer_2d/map_data_2d.gd`：`accumulate_full`→`set_full`（替换）；删 `map_merged.emit` + `MapAccumulator.add_full`
- `src/renderer_2d/renderer_2d.gd`：`_on_vehicle_registered` 签名 1 参
- `src/ui/WebSocket/vehicle_panel_manager.gd`：`_on_vehicle_registered` 签名 1 参；连接 `peer_info_updated` → 面板改名
- `src/ui/WebSocket/vehicle_panel.gd`：删除 Disconnect 按钮；显示名「连接中」→ 车名（`peer_info_updated`）
- `src/main/main.tscn`：移除 `WebSocketManager` / `WebSocketMenu` / `TestWSServer`×3，挂 `KernelBridge`
- `src/main/main.gd`：视需要

**删除（连接层）**
- `src/websocket/websocket_manager.gd` / `.tscn`
- `src/websocket/websocket_client.gd` / `.tscn`
- `src/ui/WebSocket/websocket_menu.gd` / `.tscn`
- `src/ui/WebSocket/web_socket_creation_menu.gd` / `.tscn`
- `src/test/test_ws_server.gd` / `.tscn`
- `src/test/test_e2e_multivehicle.gd` / `.tscn`
- `src/test/test_e2e_orion.gd`

**保留（测试）**：`test_orion_protocol.gd`（纯协议 roundtrip，无 WS 依赖）、`audio_record_test.gd` / `.tscn`（纯音频）

**暂缓（不接入，保留文件）**
- `src/renderer_2d/map_accumulator.gd`（多车合并阶段再启用）

---

## 8. 部署注意

- `pictor_kernel.gdextension` + `libpictor_kernel.so` 从 `kernel_test/` 移到正式位置（如 `addons/pictor_kernel/` 或项目 `bin/`），`.gdextension` 内 `.so` 路径同步更新。
- `MessageParser.parse_json` 的 hello 处理变死代码（hello 握手已由 `peer_connected` 取代），可清理。

---

## 9. 风险与注意

- `sysid` 透传遗漏 → 多车身份错乱（务必先改）。
- poll 无背压（决策 #5，后置）：pose ~10Hz/车 × N 车，主线程卡顿会积压陈旧数据。
