# Pictor 桥接入方案复核报告（design_review）

> 复核日期：2026-08-16
> 复核对象：`docs/pictor_pleiades_integration.md` / `docs/bridge_integration_plan.md` / `Task/task_23_pleiades_integration.md`
> Ground Truth：`SrcPictorKernel/lib.rs`、`docs/design_doc/pictor_bridge_sync.md`、`Src/Robot/core/**`、`Src/Network/**`
> 结论摘要：**方案方向正确、信号消费者覆盖基本完整，但有 2 个阻塞项（map_data_2d 未纳入改造、VehiclePanelManager 承载节点缺失）必须先修复后才能进入实施。**

---

## 一、问题清单（按严重度）

### 🔴 阻塞项（必须先修）

#### R1. `map_data_2d.gd` 未列入改造清单：emit 已删信号 `map_merged` + MAP_FULL 语义未定（文档写 set_full、代码是 accumulate）

- **位置**
  - 代码：`src/renderer_2d/map_data_2d.gd:16-17`（`map_full_received.connect(accumulate_full)`）、`:37-38`（`EventBus.map_merged.emit(...)`、`MapAccumulator.add_full` 累加）
  - 信号定义：`src/event_bus/event_bus.gd:12`（`signal map_merged`）
  - 文档：`docs/pictor_pleiades_integration.md §5.1` 与 `docs/bridge_integration_plan.md §5` 均写 `MAP_FULL → map_full_received → MapData2D.set_full`
- **现象**
  1. 方案在 `event_bus.gd` 删除 `map_merged`，但 `map_data_2d.gd` 仍 `EventBus.map_merged.emit(...)` → 第一帧 MAP_FULL 到达即运行时错误（信号不存在），渲染链路直接崩。
  2. 三份文档的文件修改清单都**没有列 `map_data_2d.gd`**。
  3. 文档称 `set_full`（replace 语义），代码实际是 `accumulate_full`（`MapAccumulator.add_full` 累加语义，注释自述"重连/重复接入当新车处理（整表累加）"——即断线重连会 double-add）。
- **影响**
  - 直接崩溃（首帧地图）；且 MAP_FULL 是 replace 还是 accumulate 未拍板，桥时代 peer 重连会重发 FULL，累加语义会把地图翻倍、脏掉。
- **建议**
  - 把 `map_data_2d.gd` 加入修改清单：① 删除 `map_merged` emit（或改 `set_full` 替换语义后只 emit `chunk_updated`）；② 明确 **MAP_FULL = replace（set_full）**、MAP_DELTA 继续累加；③ 说明 `map_accumulator.gd` 是"保留文件但 map_data_2d 不再调用 add_full"，还是"暂不接线"。

#### R2. `VehiclePanelManager` 唯一实例在 `websocket_menu.tscn` 内，删除 WebSocketMenu 后无承载节点

- **位置**
  - 代码：`src/ui/WebSocket/websocket_menu.tscn`（`Vehicle_Panel_Manager` 节点 + `vehicle_panel_manager.gd` + `vehicle_panel_scene`/`app_state` 导出）
  - 场景：`src/main/main.tscn`（`WebSocketMenu` 实例）；方案新场景结构 `docs/pictor_pleiades_integration.md §4.5` UI 下只有 `ButtonList / TextInput / Scale`
- **现象**
  - 方案删除 `websocket_menu.gd/.tscn`（并移出 main.tscn），但 VehiclePanelManager **只**存在于该 tscn 内；新场景结构没有它的位置。
  - 修改清单只说"改 `vehicle_panel_manager.gd` 签名 + 连接 peer_info_updated"，没有说明把该节点重新挂到哪里、谁来接 `vehicle_panel_scene` 与 `app_state` 导出。
- **影响**
  - `vehicle_registered` 无人建面板 → 面板列表全空；Ctrl+点选 / Manual 切换 / 选中态 / `app_state.selected_ids` 更新全部失效；决策 #7 面板功能落空。
- **建议**
  - 在方案中明确 VehiclePanelManager 的新承载位置（新建独立 tscn 或直接挂在 main.tscn 的 UI 下），并补上 `vehicle_panel_scene`、`app_state` 接线步骤。

---

### 🟡 重要问题（应修，不阻塞单车主链路但影响正确性）

#### Y1. `peer_left → vehicle_unregistered` 与 Rust 契约语义冲突（mDNS 过期 ≠ TCP 断开，会误删在线车辆）

- **位置**
  - Godot 映射：`bridge_integration_plan.md §3/§4`、`pictor_pleiades_integration.md §4.2`（`peer_left(hex) → vehicle_unregistered(hex)` 移除）
  - Rust 契约：`Workspace/Orion/docs/design_doc/pictor_bridge_sync.md §二.4`（peer_left = mDNS 缓存过期，"供显示发现中/连接中等过渡态"）
  - Rust 源码：`Src/Network/swarm_events.rs`（`mdns::Event::Expired → "peer_left"`；`ConnectionClosed → "peer_disconnected"`）
- **现象**
  - `peer_left` 是**发现层**过期事件，并不代表 TCP/libp2p 连接断开（`peer_disconnected` 才是）。mDNS 缓存过期（最慢 ~2 分钟）与连接存续可以并存，尤其在 Wi-Fi 漫游（本项目要解决的场景）下 mDNS 重宣告可能迟到。
- **影响**
  - 仍在推 pose 的在线车辆被从界面移除（sprite/面板消失、跟车退出）；恢复后再 `peer_connected` 重建。恰与"抗漫游不断线"目标相悖。
- **建议**
  - 只把 `peer_disconnected` 映射为 `vehicle_unregistered`；`peer_left` 不消费或仅作"离线标记"。若确需兜底，应在 KernelBridge 侧维护"最近是否仍收到该 hex 的 pose"再决定是否移除，或让 Rust 侧在真正断连时合并两种事件语义。

#### Y2. `vehicle_panel.gd Update()` 每帧把 ID 标签写回 hex → `peer_info_updated` 改名被覆盖

- **位置**
  - `src/ui/WebSocket/vehicle_panel.gd:26`（`_id_label.text = vehicle_id`）
  - `src/ui/WebSocket/vehicle_panel_manager.gd:89`（每次 `pose_received` → `panel.Update(vehicle_id, ...)`，10Hz）
  - 方案 §7 仅写"显示名『连接中』→ 车名"，未提 Update 覆盖问题
- **现象**
  - 即使 `peer_info_updated` 把面板名改成车名，100ms 内下一次 pose 到达即被 `Update` 改回 hex。
- **影响**
  - 决策 #7（面板显示车名）实际失效。
- **建议**
  - `vehicle_panel.gd` 增加 `_display_name` 字段与 `set_vehicle_name()`；`Update` 不再无条件覆盖 ID 标签（或仅当名字为空时回退为 vehicle_id）；注册时初始化为「连接中」。

#### Y3. 桥把 models/sessions 的 `peer_info_updated`（空名）也透传，会清空面板名

- **位置**
  - `Src/Network/swarm_events.rs`（TOPIC_MODELS / TOPIC_SESSIONS 同样 publish `type="peer_info_updated"` 且 `peer_name=""`）
  - `SrcPictorKernel/lib.rs` `event_loop`（只按 `type=="peer_info_updated"` 转发，未区分来源、未过滤空名）
- **现象**
  - 若局域网内有其他 Pleiades 节点发布 models/sessions，桥会转发 `peer_info_updated(hex, "")` → Godot 面板名被置空。
- **影响**
  - 面板车名可能被清空（与 Y2 叠加表现更乱）。纯"车 + Pictor"部署概率较低，但契约上存在。
- **建议**
  - KernelBridge 侧忽略空 `peer_name`；或 Rust `event_loop` 只转发 TOPIC_PEER_INFO 来源（带非空名）的事件。

#### Y4. `test/` 目录悬空引用：`test_e2e_multivehicle` / `test_e2e_orion` 依赖被删文件与信号

- **位置**
  - `src/test/test_e2e_multivehicle.gd:40,54`（`EventBus.ws_connect_requested.emit`）
  - `src/test/test_e2e_multivehicle.tscn`（实例 `test_ws_server.tscn`、`websocket_manager.tscn`）
  - `src/test/test_e2e_orion.gd:41`（`load("res://src/test/test_ws_server.gd")`）
  - 方案只删 `test_ws_server.gd/.tscn`
- **现象**
  - 删除 `test_ws_server` 与 `ws_connect_requested` 后，这两个测试场景加载/运行即报错。
- **影响**
  - 回归测试不可用（CI 断裂）。
- **建议**
  - 将 `test_e2e_multivehicle.*` 与 `test_e2e_orion.gd` 一并删除或改写为桥模式（PleiadesKernel 模拟多车），或在方案中明确"随 P4 暂缓"并列入待办。`test_orion_protocol.gd`、`audio_record_test.gd` 无 WS 依赖，可保留。

#### Y5. 多车地图数据在「合并暂缓」下仍会合入同一张表（数据路径未按车隔离）

- **位置**
  - `src/renderer_2d/map_data_2d.gd`（`accumulate_full` / `set_delta` 共用单 `_chunks` 表；`map_delta_received(voxels)` 无 vehicle 参数）
  - 方案 §5 保留 `map_delta_received(voxels)` 不变
- **现象**
  - 决策 #2 说"多车合并暂缓"，但 N 辆车时：MAP_FULL 累加进同一 chunk、MAP_DELTA 全部 `set_delta` 进同一 chunk → 屏幕地图实际仍是"朴素合并"。
- **影响**
  - 与"暂缓"表述自相矛盾；多车时地图归属/覆盖语义不可预期。
- **建议**
  - 文档明确 P3 阶段地图语义（例如"单表、FULL=replace、DELTA 累加，N 车时朴素共表，多车一致性后置"）；或将 `map_delta_received` 增加 vehicle_id 并按车分表（工作量显著上升，需重新拍板）。

#### Y6. 桥契约文档与决策 #4 冲突（kernel_ready 门控）

- **位置**
  - `Workspace/Orion/docs/design_doc/pictor_bridge_sync.md §二.1`（"收到 kernel_ready 前不应调 send_command"）、`§六.2`（"连接 kernel_ready → 之后才可发命令"）
  - Pictor 三文档决策 #4（不做门控，fire-and-forget，`send_command` 未就绪返回 false 时忽略）
- **现象**
  - Rust 侧契约文档要求门控，Godot 侧方案明确不做。两份"基线"互相矛盾。
- **影响**
  - 实施者无所适从；若照契约做门控则与决策 #4 冲突。
- **建议**
  - 统一为决策 #4（未就绪返回 false 即忽略），同步更新 `pictor_bridge_sync.md`（或注明该条仅建议，以 task_23 决策 #4 为准）。

---

### 🟢 次要问题（建议，不阻塞）

#### G1. `project.godot` 残留 `[websocket]` 死配置

- 位置：`project.godot:41-43`（`url` / `reconnect_interval`）
- 建议：随连接层删除一并移除；无功能影响。

#### G2. `vehicle_panel.tscn` 保留 "Address"（网络地址）标签、ID 默认文本为 "小车ID"

- 位置：`src/ui/WebSocket/vehicle_panel.tscn`（`Address` 标签；`ID` 标签默认文本 "小车ID"）
- 建议：删除 Address 行或改造；ID 默认文本设为「连接中」（对齐决策 #7）。

#### G3. hello 死代码清理范围（`parse_json` / `MSG_HELLO`）

- 位置：`message_parser.gd:17-30`（`parse_json`）、`protocol_def.gd:13`（`MSG_HELLO`）
- 核实：删除 `websocket_client` 后 `parse_json` 无调用者（`test_e2e_orion` 用 `text.contains("hello")`，随 test_ws_server 一并处理）；保留不报错。
- 建议：可清理或保留均可；若保留，`test_orion_protocol.gd` 不受影响。

#### G4. `main.gd` 仅注释引用 WebSocketManager/WebSocketMenu

- 位置：`src/main/main.gd:5`
- 建议：无代码依赖，改注释即可（方案"视需要"成立）。

#### G5. `.gdextension` 部署位置

- 位置：`pictor_kernel.gdextension`（`res://bin/libpictor_kernel.so`）
- 核实：`kernel_test/` 在 `res://` 内且无独立 `project.godot`，Godot 启动会自动扫描全部 `.gdextension`，故扩展**当前已可被发现**；`entry_symbol="gdext_rust_init"` 与 `lib.rs` 的 `#[gdextension]` 默认入口一致。
- 建议：移动到 `addons/pictor_kernel/` 或 `bin/` 属清理而非功能必需；移动时同步 `.gdextension` 内 `.so` 路径即可，`project.godot` 无需注册。

#### G6. 注释中的 "WebSocketManager" 字样

- 位置：`auto_handler.gd:55,92`、`event_bus.gd:20`、`message_builder.gd:5-6`（均为注释）
- 建议：无代码依赖，改注释即可。

---

## 二、文档间不一致

1. **`set_full` vs `accumulate_full`**：`pictor_pleiades_integration.md §5.1` 与 `bridge_integration_plan.md §5` 写 `MapData2D.set_full`，代码只有 `accumulate_full`；且 `map_data_2d.gd` 不在任何修改清单里。（对应 R1）
2. **决策编号/数量口径**：`pictor_pleiades_integration.md` 标题"6 条决策 + 2 条暂缓"但 §6 表列 8 行（#1–#8）；`bridge_integration_plan.md §2` 说"6 条"且表只列 #1–#6（漏 #7 面板细节）；`task_23` 列 8 条。数量口径不一致。
3. **kernel_ready 门控**：`pictor_bridge_sync.md`（Rust 契约）要求门控 vs 三份 Godot 文档决策 #4 不做门控。（对应 Y6）
4. **peer_left 语义**：`pictor_bridge_sync.md` 定义 peer_left 为"发现层过渡态"，三份 Godot 文档却把它映射为 `vehicle_unregistered`（移除）。（对应 Y1）
5. **暂缓清单**：`bridge_integration_plan.md §7` 暂缓只列 `map_accumulator.gd`；`pictor_pleiades_integration.md` 与 `task_23` 还列 `llm.gd` / `audio_input.gd`（实质"保留不接入"，不冲突但清单不齐）。

---

## 三、遗漏的 consumer / 依赖清单

| 被引用对象 | 引用位置 | 方案是否覆盖 | 后果 |
|---|---|---|---|
| `map_merged`（信号） | `map_data_2d.gd:38` emit | ❌ 未覆盖 | 删除信号后首帧崩溃（R1） |
| `MapAccumulator.add_full` | `map_data_2d.gd:24` | ⚠️ 仅"暂缓不接入"但代码仍调用 | 语义矛盾（R1/Y5） |
| VehiclePanelManager 承载节点 | `websocket_menu.tscn` 内 | ❌ 删除后未重挂 | 面板全空（R2） |
| `ws_connect_requested` | `test_e2e_multivehicle.gd:40,54` emit | ❌ 未覆盖 | 测试场景报错（Y4） |
| `test_ws_server` | `test_e2e_multivehicle.tscn`、`test_e2e_orion.gd:41` | ❌ 只删 test_ws_server 本身 | 悬空引用（Y4） |
| `ws_disconnect_requested` | `vehicle_panel.gd:39` `_on_disconnect_pressed` | ⚠️ 方案只写"删 Disconnect 按钮" | 需连同 handler 一起删，否则残留死代码 |
| `websocket_manager.gd/.tscn` | `test_e2e_multivehicle.tscn` 实例 | ❌ 未覆盖（测试场景） | 测试报错（Y4） |
| `[websocket]` 配置 | `project.godot:41-43` | ❌ 未提及 | 死配置（G1） |
| `MapData2D`（%MapData2D） | `renderer_2d.gd` 依赖 | ✅ main.tscn 保留 | 无问题 |

---

## 四、已核实无问题的项（不凑数，明确确认）

1. **`ws_connected` 删除安全**：全仓只有 `websocket_client.gd:42` emit，无任何消费者。
2. **`vehicle_registered` 签名改动覆盖完整**：消费者仅 `renderer_2d.gd`、`vehicle_panel_manager.gd`、`websocket_manager.gd`；前两者已在方案修改清单（改 1 参），后者删除。emit 方仅 `websocket_client.gd`（删除）。
3. **`vehicle_unregistered` 幂等**：`renderer_2d` / `vehicle_panel_manager` / `camera_2d` 的 handler 均可重复调用（queue_free + erase + 状态复位），`peer_disconnected` 与 `peer_left` 双触发不崩溃。
4. **`pose_received` 改 hex 无类型问题**：三处消费者（renderer_2d / camera_2d / vehicle_panel_manager）均以 vehicle_id 字符串做字典键，hex 与 peer 事件键一致。
5. **控制层"零改动"成立**：`control/*`、`ui/*`（WebSocket 目录外）、`util/llm.gd`、`util/audio_input.gd` 无任何 WS 类引用（仅注释），只 emit `cmd_send` / `command_requested` / `audio_record_*`。
6. **下行链路迁移完整**：`Build_Cmd` 终端上行 = 空 sysid + `COMPID_TERMINAL(200)`；车端 `command_consumer` → `parse_orion_frame` 只按 msgid 分发、不校验 sysid/compid，桥时代语义不变。TASK_SET 的 members 填充、cancel（missions 空不填 members → member_count=0）语义均可原样迁移。
7. **`_peer_ids` 在桥时代不再必要**：桥时代 vehicle_id 即 hex peer_id，members 直接 `id.hex_decode()` 即可，无需再维护 hex→bytes 查表（方案未明说，但不影响正确性，建议在 KernelBridge 实现时直接删表）。
8. **身份编码一致性（Rust ↔ Godot）**：`hex(sysid)`（sysid = `PeerId::to_bytes()`，Ed25519 38B）与桥 `base58_to_hex`（`PeerId::to_bytes()` 后 hex）完全一致；`parse_peer_hex`（`PeerId::from_bytes`）互为逆；两侧均为小写 hex。
9. **`test_orion_protocol.gd` 与 `audio_record_test.gd` 不受影响**：前者纯协议 roundtrip（对 `parse_orion_frame` 新增 sysid 字段无断言冲突，`MapAccumulator` 文件保留即可）；后者纯音频。
10. **`renderer_3d` 与本次方案无关**：不在 main.tscn 中实例化；其引用的 `voxel_received`/`path_received` 在 event_bus 中本就不存在（既有死代码，非本次引入）。

---

## 五、结论

**方案能否进入实施：否（有 2 个阻塞项，先修后实施）。**

- 必须修复的阻塞项：
  1. **R1**：把 `map_data_2d.gd` 纳入改造清单——删除 `map_merged` emit、明确 MAP_FULL=replace（set_full）/ MAP_DELTA=累加，否则删除 `map_merged` 信号后第一帧地图即崩溃。
  2. **R2**：为 `VehiclePanelManager` 指定新承载节点并接线（删除 `websocket_menu.tscn` 后它没有挂载点），否则车辆面板链路整体失效。
- 强烈建议同时定稿：`peer_left` 语义（Y1，误删在线车辆风险）、`vehicle_panel` 改名覆盖问题（Y2）、空 `peer_name` 过滤（Y3）、两个 e2e 测试去留（Y4）。
- 其余维度（信号消费者覆盖、下行链路、身份编码、生命周期幂等）经逐条核对基本成立，方案骨架可复用 WS 时代接收/渲染/控制链路。
