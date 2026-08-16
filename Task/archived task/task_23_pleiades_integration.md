# Task 23: Pleiades 集成（逻辑与表现分离）

> 创建日期：2026-08-15
> 状态：✅ 已实施 + 测试通过（2026-08-16）
> 前身：task_23_websocket_reconnect（已重定向——WebSocket 重连方案作废）
> 复核：`docs/design_review.md`（2026-08-16，14 问题 2🔴6🟡6🟢，已全部定案）

---

## 背景

真实部署中，车端 Wi-Fi 漫游（AP 切换）会触发 NetworkManager 重新激活接口 + 重跑 DHCP，导致 L3 地址被摘、**所有 TCP 连接被杀**（SSH / WebSocket / VNC 实测均断，`journalctl` 日志实锤）。

而车端已有的 **libp2p P2P 网络**（`Orion/`，libp2p 0.56 + tcp + mdns）在同样漫游中**不断线**——`swarm_events.rs` 里 mDNS 发现后自动 `dial` 重连。

**结论**：与其给 Pictor 的 WebSocket 打重连补丁，不如让 Pictor 直接接入已有的、天生抗断的 libp2p 网络，并彻底移除 WebSocket。

## 方案定稿

**架构原则：逻辑与表现分离，桥 = 哑管道（不解析、不合并业务数据）。**

```
Godot 进程（单进程）
├── KernelBridge（Godot，薄适配器）
│     ├── 上行：robot_frame → parse_orion_frame → EventBus；peer_* → EventBus
│     └── 下行：EventBus.cmd_send → Build_Cmd → kernel.send_command
├── PleiadesKernel（Rust GDExtension，哑管道）
│     └── libp2p swarm（mDNS 自动发现 / gossipsub 广播 / Send_Data_Try 单播）
└── 表现层（Renderer2D / VehiclePanelManager / Camera / ControlMaster）
                                        │
                            ┌───────────┴───────────┐
                            │   车们 (orion-robot)    │
                            └───────────────────────┘
```

详见 `docs/pictor_pleiades_integration.md`。

## 设计决策记录

| 决策 | 结论 |
|------|------|
| 桥角色 | ✅ 哑管道（不解析、不合并业务数据，只透传原始帧 + peer 事件） |
| 通信方式 | ✅ 纯 libp2p，移除 WebSocket；Godot 连接层（websocket_client/manager/menu）删除 |
| 进程模型 | ✅ GDExtension 内嵌（单进程多线程；Pleiades 跑后台 tokio 线程） |
| 无头模式 | ✅ Pleiades 不启动 TUI（`Src/TUI/` 独立模块），状态由桥导出 |
| 嵌入范围 | ✅ 保留全部功能（ML/API/VM 照常），仅无头化（不启动 TUI） |
| 桥：下行（命令） | ✅ `send_command(peer_id_hex, frame)` → `Send_Data_Try` 单播到指定 peer_id（Godot 拼好完整 ORION 帧） |
| 桥：上行（数据/事件） | ✅ 哑管道透传：robot_bus 原始 ORION 帧 → `robot_frame`；event_bus peer 事件 → `peer_*`；Godot 每帧 `poll()` 排空队列 emit |
| peer_id 编码 | ✅ 统一 hex（event_bus 的 base58 → hex 在桥内 `base58_to_hex()` 完成） |
| 地图数据 | ✅ Rust 不合并、只透传原始帧；Godot 单表渲染：**MAP_FULL=替换(set_full)、MAP_DELTA=累加(set_delta)**；多车朴素共表、一致性后置（多车合并 + 返还**暂缓**） |
| 跨桥数据格式 | ✅ 原始 ORION 帧（PackedByteArray）经 `robot_frame` 透传，Godot `parse_orion_frame` 解码；peer 事件为 hex 字符串 |
| Godot 版本 | ✅ 4.7.1 + gdext 对应版本（task 17 已调研 godot crate 0.5.4） |

## 待决策问题（已全部定案）

1. ✅ **peer_id 编码统一 hex** — 桥 `event_loop` 内 `base58_to_hex()` 统一，Godot 零 base58 解码。
2. ✅ **地图同步：哑管道原始帧透传** — `map_updated` 全量轮询移除；POSE/MAP_FULL/MAP_DELTA 原始帧经 `robot_frame` 透传；多车合并 + 返还**暂缓**。
3. ✅ **WebSocket 连接层移除** — `protocol/` 四件套保留复用（解 `robot_frame` + 拼 cmd 帧）。
4. ✅ **kernel_ready 门控不做** — fire-and-forget，`send_command` 未就绪返回 false 时忽略。
5. ⏳ **poll 队列无背压**（风险后置）— 队列无上限，主线程卡顿积压；建议队列上限 + 丢旧策略（pose 可丢、map_delta 不可丢），后置处理。
6. ✅ **车辆注册/移除由 peer 事件驱动（复核修正）** — `peer_connected` → 显示；`peer_disconnected` → 移除；**`peer_left`（mDNS 过期 ≠ 断连）不消费**（同 `peer_discovered`）。Godot 不做心跳超时。
7. ✅ **面板/UI 细节** — ① 面板名「连接中」→ 车名（`peer_info_updated`），且 `Update` 不得覆盖名字；② Disconnect 按钮删除；③ `peer_discovered` 不消费。
8. ✅ **e2e 测试删除** — `test_ws_server` / `test_e2e_multivehicle` / `test_e2e_orion` 删除（WS Server 不再需要）；⏸️ LLM/STT 归属暂缓（`llm.gd` 现状保留）。

---

## P3 实施详细方案（Godot 侧切桥）

### 改动目的

把 Pictor 的数据通道从「WebSocket 直连」切换到「进程内 Rust 桥（libp2p）」：
1. **连接管理上移 Rust**：libp2p 抗 Wi-Fi 漫游断连（本任务的初衷）；
2. **Godot 只做表现**：复用 WS 时代已有的 `parse_orion_frame` / MapData2D / Renderer2D / 控制链路，把「数据源」从 WS socket 换成 `robot_frame` 信号；
3. **删除 WebSocket 连接层**，消除死代码与双通道维护成本。

### 涉及文件（完整清单）

**新增**
| 文件 | 说明 |
|---|---|
| `src/kernel/kernel_bridge.gd` | 桥适配器：挂 PleiadesKernel、每帧 poll、信号翻译、cmd_send 下行路由 |
| `src/ui/WebSocket/vehicle_panel_manager.tscn` | 面板管理器承载场景（从 websocket_menu.tscn 抽出） |

**修改**
| 文件 | 改动 |
|---|---|
| `src/event_bus/event_bus.gd` | `vehicle_registered` 去 `url` 参；删 `ws_connect_requested`/`ws_disconnect_requested`/`ws_connected`/`map_merged`；新增 `peer_info_updated(vehicle_id, peer_name)` |
| `src/websocket/protocol/message_parser.gd` | `parse_orion_frame` 返回值透传 `sysid` |
| `src/renderer_2d/map_data_2d.gd` | `accumulate_full`→`set_full`（替换语义）；删 `map_merged.emit` + `MapAccumulator.add_full` 调用 |
| `src/renderer_2d/renderer_2d.gd` | `_on_vehicle_registered` 签名 1 参 |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | `_on_vehicle_registered` 签名 1 参；连接 `peer_info_updated` → 面板改名 |
| `src/ui/WebSocket/vehicle_panel.gd` | 删 Disconnect 按钮 + 其 handler；加 `_display_name`，`Update` 不覆盖名字 |
| `src/main/main.tscn` | 移除 WebSocketManager/WebSocketMenu/TestWSServer×3；挂 KernelBridge + vehicle_panel_manager.tscn |
| `src/main/main.gd` | 仅注释修正（引用被删节点的注释） |
| `project.godot` | 删 `[websocket]` 死配置 |

**删除（连接层 + 测试）**
- `src/websocket/websocket_manager.gd` / `.tscn`
- `src/websocket/websocket_client.gd` / `.tscn`
- `src/ui/WebSocket/websocket_menu.gd` / `.tscn`
- `src/ui/WebSocket/web_socket_creation_menu.gd` / `.tscn`
- `src/test/test_ws_server.gd` / `.tscn`
- `src/test/test_e2e_multivehicle.gd` / `.tscn`
- `src/test/test_e2e_orion.gd`

**保留**
- `src/websocket/protocol/`（orion_frame / orion_messages / message_parser / protocol_def）
- `src/test/test_orion_protocol.gd`（纯协议 roundtrip，无 WS 依赖）
- `src/test/audio_record_test.gd` / `.tscn`（纯音频）

**暂缓（保留文件，不接入）**
- `src/renderer_2d/map_accumulator.gd`（多车合并阶段启用）
- `src/util/llm.gd`、`src/control/audio_input.gd`（LLM/STT 归属暂缓）

### 新文件架构形式

**`src/kernel/kernel_bridge.gd`（extends Node）**
```
var kernel: Object                          # PleiadesKernel 实例

func _ready():
    kernel = ClassDB.instantiate("PleiadesKernel")
    add_child(kernel)                        # 触发 Rust 侧 ready() → 后台 bootstrap
    kernel.robot_frame.connect(_on_robot_frame)
    kernel.peer_connected.connect(_on_peer_connected)
    kernel.peer_disconnected.connect(_on_peer_disconnected)
    kernel.peer_info_updated.connect(_on_peer_info_updated)
    # kernel.peer_discovered / peer_left：不连接（决策 #6/#7，不消费）
    EventBus.cmd_send.connect(_on_cmd_send)

func _process(_delta): kernel.poll()         # 每帧排空 out_queue 并 emit

func _on_robot_frame(data: PackedByteArray):
    var r := MessageParser.parse_orion_frame(data)   # r 含新增 sysid
    if not r.ok: return
    var vid := _hex(r.sysid)                 # sysid 字节 → hex 字符串 = vehicle_id
    match r.msgid:
        ProtocolDef.MSGID_POSE:      EventBus.pose_received.emit(vid, r.data)
        ProtocolDef.MSGID_MAP_FULL:  EventBus.map_full_received.emit(vid, r.data.chunk_x, r.data.chunk_y, r.data.cells)
        ProtocolDef.MSGID_MAP_DELTA: EventBus.map_delta_received.emit(r.data.voxels)

func _on_peer_connected(hex):   EventBus.vehicle_registered.emit(hex)
func _on_peer_disconnected(hex): EventBus.vehicle_unregistered.emit(hex)
func _on_peer_info_updated(hex, name):
    if not name.is_empty(): EventBus.peer_info_updated.emit(hex, name)   # 空名过滤（Y3）

func _on_cmd_send(targets: Array[String], cmd: Dictionary):
    if cmd.get("msgid", -1) == ProtocolDef.MSGID_TASK_SET and not cmd.has("members"):
        var members: Array = []
        if not cmd.get("missions", []).is_empty():
            for id in targets: members.append(id.hex_decode())   # hex → 字节
        cmd["members"] = members
    var frame := OrionMessages.Build_Cmd(cmd)
    for id in targets: kernel.send_command(id, frame)            # fire-and-forget
```

**`src/ui/WebSocket/vehicle_panel_manager.tscn`（从 websocket_menu.tscn 抽出）**
```
PanelContainer
└── MarginContainer / VBoxContainer
    └── ScrollContainer
        └── Vehicle_Panel_Manager (VBoxContainer, vehicle_panel_manager.gd)
            ├── vehicle_panel_scene = res://src/ui/WebSocket/vehicle_panel.tscn
            └── app_state = res://src/app_state/app_state.tres
```
（去掉原 websocket_menu.tscn 里的「创建连接」按钮 + web_socket_creation_menu 引用）

### 详细步骤

**Step 1 — EventBus 信号改造**（`src/event_bus/event_bus.gd`）
- `vehicle_registered(vehicle_id, url)` → `vehicle_registered(vehicle_id)`
- 删信号：`ws_connect_requested` / `ws_disconnect_requested` / `ws_connected` / `map_merged`
- 新增：`peer_info_updated(vehicle_id: String, peer_name: String)`
- 目的：对齐桥的 7 信号 + 移除 WebSocket 专属信号。⚠️ 删 `map_merged` 前必须先做 Step 3（否则 map_data_2d 仍 emit 它 → 崩溃）。

**Step 2 — 协议层透传 sysid**（`message_parser.gd`）
- `parse_orion_frame` 返回值增加 `"sysid": frame.sysid`（PackedByteArray）
- 目的：多车共用一个 `robot_frame` 信号，sysid 是唯一身份来源。

**Step 3 — MapData2D 改造（R1）**（`map_data_2d.gd`）
- `accumulate_full` → `set_full`：`chunk.cells = incoming`（替换，不再 `MapAccumulator.add_full` 累加）
- 删除 `EventBus.map_merged.emit(...)` 行（保留 `chunk_updated.emit` 触发重绘）
- `set_delta` 累加逻辑保持不变
- 目的：修复「删 map_merged 后首帧崩溃」+「断线重连 double-add」；地图语义 = 单表、FULL 替换、DELTA 累加。

**Step 4 — 新建 KernelBridge**（`src/kernel/kernel_bridge.gd`）
- 按上文「新文件架构形式」实现。
- 目的：核心适配器——上行翻译（robot_frame→EventBus、peer_*→registered/unregistered）、下行路由（cmd_send→send_command）。

**Step 5 — 车辆生命周期接线**
- `renderer_2d.gd`：`_on_vehicle_registered(vehicle_id)`（去 `_url`）
- `vehicle_panel_manager.gd`：`_on_vehicle_registered(vehicle_id)`；新增 `_on_peer_info_updated(vehicle_id, name)` → `panel.set_vehicle_name(name)`
- `vehicle_panel.gd`：删 Disconnect 按钮 + `_on_disconnect_pressed`；加 `var _display_name := "连接中"` + `set_vehicle_name(name)`；`Update()` 里 ID 标签改用 `_display_name`（名字为空时回退 hex），不再每帧覆盖
- 目的：面板「连接中」→ 车名（决策 #7），且不被 10Hz pose 覆盖（Y2）。

**Step 6 — 新建 vehicle_panel_manager.tscn（R2）**
- 按上文结构从 `websocket_menu.tscn` 抽出，新建 `src/ui/WebSocket/vehicle_panel_manager.tscn`。
- 目的：删除 WebSocketMenu 后面板管理器仍有承载节点。

**Step 7 — main.tscn 改造**
- 移除节点：`WebSocketManager`、`UI/WebSocketMenu`、`TestWSServer`×3
- 挂载：`KernelBridge`（Main 下）、`UI/vehicle_panel_manager`（UI 下）
- 目的：场景结构切换到桥。

**Step 8 — 删除连接层 + 测试文件**
- 删 `websocket_manager` / `websocket_client` / `websocket_menu` / `web_socket_creation_menu` / `test_ws_server` / `test_e2e_multivehicle` / `test_e2e_orion`（.gd + .tscn）
- 目的：移除 WS 连接层与依赖它的测试；`test_orion_protocol`、`audio_record_test` 保留。

**Step 9 — 清理（🟢）**
- `project.godot` 删 `[websocket]` 配置
- `main.gd` 删/改引用被删节点的注释
- `message_parser.gd` 的 `parse_json`（hello）与 `protocol_def.gd` 的 `MSG_HELLO` 死代码清理（可选，不阻塞）

**Step 10 — 验证**
- 编译：`godot --headless --path . --quit`（无脚本/场景错误）
- 运行：起 `main.tscn`，确认 KernelBridge 挂载 + `kernel_ready` 后，真实/模拟 orion-robot 接入 → 面板出现「连接中」→ 车名 → Sprite/地图/pose 更新 → 手动/Goto 命令下发（`send_command` 返回 true）
- 断连：kill 车端 → 面板/Sprite 移除（`peer_disconnected`）

### 依赖顺序（务必遵守）

Step 3 必须先于 Step 1 的「删 map_merged」；Step 4 依赖 Step 2（sysid）；Step 5/6/7 依赖 Step 1/4。建议按 1→2→3→4→5→6→7→8→9→10 顺序推进，每步保持可运行。

---

## 依赖

- 车端 orion-robot：数据路径已就绪（mDNS + gossipsub）；命令路径需加 request-response 接收路由
- task 17（STT）/ task 16（LLM）：⏸️ 暂缓（`llm.gd` 现状保留，后续 task 再并入 Rust 逻辑层）
- 多车地图一致性（CRDT 调研）：⏸️ 暂缓（多车合并暂缓）
- Rust 契约文档 `docs/design_doc/pictor_bridge_sync.md`：kernel_ready 门控表述与决策 #4 冲突，需同步修正（以决策 #4 为准）

## 实施结果（2026-08-16）

- ✅ P0-P3 完成：Rust 桥（哑管道）+ Godot 侧切桥（KernelBridge）
- ✅ Linux headless 验证通过（场景加载 + 内核 bootstrap + 信号连接）；Windows 真机测试通过（用户验证）
- 🐛 踩坑：Windows `.dll` 依赖 CUDA（`pleiades` 默认 cuda feature 链了 `curand64_10.dll`=CUDA10，与本机 12.8 不匹配 → Error 126）；关闭 cuda feature（`default-features = false`）重编解决
- `.gdextension` 置于项目根 `res://pictor_kernel.gdextension`（含 linux+windows 条目）；二进制放 `kernel_test/bin/`（gitignore，不提交）
- ⏸️ P4（e2e + 断线重连）后置：真车/模拟节点到位再验

## 待办

- [x] 架构收敛（逻辑/表现分离 + 移除 WS）
- [x] 设计文档 `docs/pictor_pleiades_integration.md`
- [x] 桥接入调研 → `docs/bridge_integration_plan.md`
- [x] 方案复核 → `docs/design_review.md`（14 问题，已定修复方案）
- [x] 拍板「待决策问题」第 1-8 项
- [x] P3 实施（Step 1-10 完成；Linux headless + Windows 真机测试均通过）
- [ ] P4 e2e + 断线重连验证（⏸️ 后置：真车/模拟节点到位再验）
