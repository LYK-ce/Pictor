# Pictor × Pleiades 集成设计（逻辑与表现分离，桥 = 哑管道）

> 更新：2026-08-16（按「桥 = 哑管道」最终架构重写，覆盖 08-15 草案）
> 状态：✅ 方案定稿（6 条决策 + 2 条暂缓），待实施（P3）
> 前身：task_23（WebSocket 重连）—— 本方案使其作废

---

## 1. 背景与动机

真实部署中，车端 Wi-Fi 漫游（AP 切换）会触发 NetworkManager 重新激活接口 + 重跑 DHCP，导致 L3 地址被摘，**所有 TCP 连接被杀**（SSH / WebSocket / VNC 实测均断，`journalctl` 日志已实锤）。

而车端已有的 **libp2p P2P 网络**（`Orion/` Rust 项目，`libp2p 0.56 + tcp + mdns`）在同样的漫游中**不断线**——`swarm_events.rs` 里 mDNS 发现后自动 `dial` 重连。

**结论**：与其给 Pictor 的 WebSocket 打重连补丁，不如让 Pictor 直接接入已有的、天生抗断的 libp2p 网络，并彻底移除 WebSocket。

---

## 2. 架构原则

**Pleiades = 逻辑层（网络/协议），Godot = 表现层（渲染/UI/输入），桥 = 哑管道（只透传、不解析、不合并）。**

> 关键变化（vs 08-15 草案）：桥**不再解析/合并业务数据**。pose/map 以原始 ORION 帧透传，由 Godot 复用现有解析/渲染链路；多车地图合并从「放 Rust」改为「暂缓」。

```
Godot 进程（单进程）
├── KernelBridge（Godot，薄适配器）
│     ├── 上行：robot_frame → parse_orion_frame → EventBus；peer_* → EventBus
│     └── 下行：EventBus.cmd_send → OrionMessages.Build_Cmd → kernel.send_command
├── PleiadesKernel（Rust GDExtension，哑管道）
│     └── libp2p swarm（mDNS 自动发现 / gossipsub 广播 / Send_Data_Try 单播）
└── 表现层（Renderer2D / VehiclePanelManager / Camera / ControlMaster）
                                        │
                            ┌───────────┴───────────┐
                            │   车们 (orion-robot)    │
                            │ mDNS 自动发现 + 加入    │
                            └───────────────────────┘
```

---

## 3. Rust 侧：PleiadesKernel（哑管道）

`SrcPictorKernel/lib.rs`（✅ 已实现）。Godot 通过 `.gdextension` 加载 `libpictor_kernel.so`。

**7 个上行信号**：

| 信号 | 参数 | 来源 |
|---|---|---|
| `kernel_ready` | — | 后台 bootstrap 完成，发一次 |
| `robot_frame` | `data: PackedByteArray`（原始 ORION 帧） | robot_bus（POSE/MAP_FULL/MAP_DELTA 原样透传） |
| `peer_discovered` | `peer_id: String(hex)` | event_bus mDNS 发现 |
| `peer_left` | `peer_id: String(hex)` | event_bus mDNS 过期 |
| `peer_connected` | `peer_id: String(hex)` | event_bus TCP 连接建立 |
| `peer_disconnected` | `peer_id: String(hex)` | event_bus TCP 断开 |
| `peer_info_updated` | `peer_id: String(hex), peer_name: String` | event_bus 节点名 gossip |

**2 个方法**：`send_command(peer_id_hex, frame) -> bool`（下发完整 ORION 帧）、`poll()`（每帧排空队列 emit 信号）。

要点：
- 桥不解析、不合并业务数据，只透传 robot_bus 原始帧 + event_bus peer 事件。
- peer_id 统一 **hex**（event_bus 里 base58 → hex 在桥内 `base58_to_hex()` 完成）。

---

## 4. Godot 侧架构

### 4.1 KernelBridge（新增，`src/kernel/kernel_bridge.gd`）

`WebSocketManager` 的替代者，但**薄得多**——不再做连接管理，只做两件事：

1. **上行翻译**：挂 `PleiadesKernel`、每帧 `poll()`，把 7 个桥信号翻译成 EventBus 信号；
2. **下行路由**：消费 `EventBus.cmd_send`，拼帧后逐车 `kernel.send_command(hex, frame)`。

### 4.2 桥信号 → EventBus 映射

| 桥信号 | EventBus | 说明 |
|---|---|---|
| `kernel_ready()` | —（忽略/日志） | 决策：不做 UI 门控 |
| `robot_frame(data)` | 解析后 → `pose_received` / `map_full_received` / `map_delta_received` | `parse_orion_frame` 按 msgid 分发，`vehicle_id = hex(sysid)` |
| `peer_connected(hex)` | `vehicle_registered(hex)` | 建 Sprite + 面板（签名改 1 参） |
| `peer_disconnected(hex)` | `vehicle_unregistered(hex)` | 移除 |
| `peer_left(hex)` | （不消费） | mDNS 过期 ≠ 断连，不映射移除 |
| `peer_discovered(hex)` | （不消费） | 仅 `peer_connected` 建 panel |
| `peer_info_updated(hex, name)` | `peer_info_updated(hex, name)`（新） | 面板 ID 标签换车名 |

> ⚠️ 前置改动：`MessageParser.parse_orion_frame` 目前丢弃 `frame.sysid`，需加 `"sysid"` 字段透传，否则多车身份无法区分。

### 4.3 车辆身份与生命周期

- **身份键 = `hex(sysid)`**（`robot_frame` 帧头 sysid = 完整 peer_id 字节，与 `peer_*` 事件已统一 hex）。
- 生命周期：
  - `peer_connected` → `vehicle_registered` → Renderer2D 建 Sprite + VehiclePanelManager 建面板（面板名先显示「连接中」）
  - `peer_info_updated` → 面板 ID 标签换成车名
  - `peer_disconnected` → `vehicle_unregistered` → 清理（`peer_left` 不消费）
- 连接生命周期/失联判定由 Rust（libp2p swarm）负责，Godot **不做**心跳超时清理。

### 4.4 控制逻辑（不变）

操作方式与命令下发**完全不变**，全部 EventBus 驱动：

| 操作 | 输入组件 | 产物 |
|---|---|---|
| Ctrl+左键点选面板 | `vehicle_panel.gd` → `vehicle_panel_manager.gd` | 更新 `app_state.selected_ids` |
| 点面板 Manual 切换 | `vehicle_panel.gd` → `vehicle_panel_manager.gd` | 更新 `app_state.manual_target` + `cmd_send(模式切换)` |
| 右键地图 Goto | `auto_handler.gd` | `cmd_send(selected_ids, TASK_SET goto)` |
| WASD 手动 | `input_handler.gd` → `control_master` | `cmd_send([manual_target], MANUAL_CONTROL)` |
| LLM 指令 | `text_input.gd` → `auto_handler.gd` → `llm.gd` | `cmd_send(selected_ids, TASK_SET)` |

控制层（`control/`、`ui/`、`util/llm.gd`、`util/audio_input.gd`）全部**零改动**——它们只 `emit cmd_send`，消费方从 `WebSocketManager` 换成 `KernelBridge`，对上层透明。

### 4.5 场景结构（新 `main.tscn`）

```
Main (main.gd)
├── Camera2D
├── MapData2D
├── Renderer2D
├── KernelBridge          ← 新增，替换 WebSocketManager 位置
├── UI (CanvasLayer)
│   ├── ButtonList
│   ├── TextInput
│   └── Scale
├── ControlMaster
└── Util
```
（移除：`WebSocketManager`、`WebSocketMenu`、`TestWSServer`×3）

---

## 5. 数据流

### 5.1 上行（车 → Godot）

```
车 ──gossipsub 原始帧──► robot_bus ──► 桥 robot_forward_loop ──► out_queue ──► poll() ──► robot_frame
                                                                                        └─► KernelBridge
                                                                                              └─► MessageParser.parse_orion_frame(data)
                                                                                                    ├─ POSE(msgid1)     → pose_received → Sprite/面板/相机
                                                                                                    ├─ MAP_FULL(msgid2) → map_full_received → MapData2D.set_full
                                                                                                    └─ MAP_DELTA(msgid3)→ map_delta_received → MapData2D.set_delta
                                                                                                                          └─► cells_changed → update_cells 增量重绘
```

### 5.2 下行（Godot → 车）

```
控制层 ──► EventBus.cmd_send(targets, cmd)
              └─► KernelBridge
                    ├─ TASK_SET 时填 members（hex → bytes）
                    ├─ OrionMessages.Build_Cmd(cmd) → frame
                    └─ for id in targets: kernel.send_command(id, frame)
                          └─► 桥 Send_Data_Try(peer, Robot, frame) → 单播到指定车
```

---

## 6. 已拍板决策（2026-08-16）

| # | 决策 |
|---|------|
| 1 | peer_id 统一 hex（桥内 base58 → hex） |
| 2 | 地图原始帧透传；多车合并 + 返还合并全量**暂缓** |
| 3 | WebSocket **连接层**移除；`protocol/` 四件套保留复用 |
| 4 | `kernel_ready` 前 UI 门控**不做**（fire-and-forget） |
| 5 | poll 队列背压风险**后置** |
| 6 | 车辆注册/移除由 peer 事件驱动（`peer_connected`→显示、`peer_disconnected`→移除、`peer_left` 不消费）；Godot **不做**心跳超时 |
| 7 | 面板显示名「连接中」→ 车名；Disconnect 按钮删除；`peer_discovered` 不消费 |
| 8 | e2e 测试删除（`test_ws_server`/`e2e_*`）；⏸️ LLM/STT 归属暂缓 |

---

## 7. 文件级改动

**新增**
- `src/kernel/kernel_bridge.gd`（+可选 `.tscn`）
- `src/ui/WebSocket/vehicle_panel_manager.tscn`（面板管理器承载，从 websocket_menu 抽出）

**修改**
- `src/event_bus/event_bus.gd`：`vehicle_registered` 去 `url` 参；删 `ws_connect_requested` / `ws_disconnect_requested` / `ws_connected` / `map_merged`；新增 `peer_info_updated`
- `src/websocket/protocol/message_parser.gd`：`parse_orion_frame` 透传 `sysid`
- `src/renderer_2d/map_data_2d.gd`：`accumulate_full`→`set_full`（替换）；删 `map_merged.emit` + `MapAccumulator.add_full`
- `src/renderer_2d/renderer_2d.gd`：`_on_vehicle_registered` 签名 1 参
- `src/ui/WebSocket/vehicle_panel_manager.gd`：`_on_vehicle_registered` 签名 1 参；连接 `peer_info_updated`
- `src/ui/WebSocket/vehicle_panel.gd`：删 Disconnect 按钮；显示名「连接中」→ 车名
- `src/main/main.tscn`：移除 WebSocket 节点、挂 KernelBridge
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

**暂缓（保留文件，不接入）**
- `src/renderer_2d/map_accumulator.gd`（多车合并阶段启用）
- `src/util/llm.gd`、`src/control/audio_input.gd`（LLM/STT 归属暂缓）

---

## 8. 分阶段计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | GDExtension 骨架：tokio + swarm | ✅ 完成（kernel_test 验证） |
| P1 | Pleiades 无头模式 + 桥 crate 骨架 | ✅ 完成 |
| P2 | 桥 API：robot_frame + peer 事件 + send_command/poll + hex 统一 | ✅ 完成 |
| P3 | Godot 拆 WebSocket 连接层，KernelBridge 切桥 | ⬜ 待做 |
| P4 | e2e + 断线重连验证 | ⬜ 待做（联调方案暂缓） |

---

## 9. 部署注意

- `pictor_kernel.gdextension` + `libpictor_kernel.so` 从 `kernel_test/` 移到正式位置（如 `addons/pictor_kernel/` 或项目 `bin/`），`.gdextension` 内路径同步更新。
- `MessageParser.parse_json` 的 hello 处理变死代码，可清理。
- 风险（后置）：poll 队列无背压——pose ~10Hz/车 × N 车，主线程卡顿会积压陈旧数据。
