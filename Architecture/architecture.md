# Pictor Architecture

> 更新日期：2026-08-16（对齐 KernelBridge 迁移后的实际代码；本文件以实际代码为准）

## 概述

Pictor 是 Pleiades 系统的 Godot 可视化与控制终端。通过 Rust GDExtension（`PleiadesKernel`，libp2p）经 **KernelBridge** 与小车端双向通信，支持多车同时连接。

> **连接层迁移**：原 WebSocket 连接层（`websocket_client` / `websocket_manager` / `hello` 握手）已退役，连接/Peer 管理完全在 Rust `PleiadesKernel`（libp2p swarm）内，Godot 只通过 `KernelBridge` 收发 ORION 帧。

## 场景结构

主场景 `src/main/main.tscn` 组件树（7 个顶层节点）：

```
Main (Node, main.gd)
├── Camera2D (camera_2d.tscn)              ← 2D 相机（IDLE/FOLLOW 状态机）
├── MapData2D (map_data_2d.tscn)           ← 地图数据层（log-odds 存储，%MapData2D）
├── Renderer2D (renderer_2d.tscn)          ← 2D 渲染总管
├── KernelBridge (Node, kernel_bridge.gd)  ← Rust 桥适配器（替代 WebSocketManager）
├── UI (CanvasLayer)
│   ├── VehiclePanelManager (vehicle_panel_manager.tscn)  ← 车辆面板总管
│   ├── Button (button_list.tscn)          ← Lock Camera / Goto / 录音按钮
│   ├── TextInput (text_input.tscn)        ← 自然语言指令输入
│   └── Scale (scale.tscn)                 ← 坐标标尺 + 状态栏
├── ControlMaster (control.tscn, Node2D 无脚本)
│   ├── InputHandler (input_handler.tscn)  ← 键盘 WASD 手动控制
│   ├── AutoHandler (Node2D, auto_handler.gd)  ← 右键 Goto / Z 键 Circle / LLM 编排
│   └── AudioInput (audio_input.tscn)      ← 麦克风录音
└── Util (util.tscn)
    └── LLM (llm.tscn)                     ← 自然语言 → 指令（DeepSeek）
```

EventBus 通过 Autoload 注入，所有组件通过信号通信，无需场景挂载。

## 目录结构

```
src/
├── event_bus/event_bus.gd             ← Autoload 单例（15 个信号）
├── app_state/app_state.gd(.tres)      ← AppStateResource（Mode 枚举 + selected_ids/manual_target）
├── main/
│   ├── main.gd / main.tscn            ← 入口
│   └── menu.gd / menu.tscn            ← 渲染模式菜单（⚠️未接入）
├── kernel/
│   └── kernel_bridge.gd               ← Rust 桥适配器（核心连接层）
├── camera/camera_2d.gd/.tscn          ← 2D 相机
├── control/
│   ├── control.tscn                   ← ControlMaster 容器（Node2D 无脚本）
│   ├── input_handler.gd/.tscn         ← 手动 WASD
│   ├── auto_handler.gd                ← 右键 Goto / Z 键 Circle / LLM 编排
│   └── audio_input.gd/.tscn           ← 麦克风录音
├── renderer_2d/
│   ├── renderer_2d.gd/.tscn           ← 2D 渲染总管
│   ├── map_data_2d.gd/.tscn           ← 地图数据层（Chunk + log-odds）
│   ├── chunk_data_2d.gd               ← Chunk Resource + i8/u8 转换
│   ├── map_accumulator.gd             ← 多车聚合纯静态助手（⚠️暂未接入）
│   ├── map_container_2d.gd/.tscn      ← TileMapLayer 渲染
│   ├── input_indicator.gd             ← Goto/Circle 目标高亮框
│   ├── path_line_2d.gd/.tscn          ← 路径线（⚠️未实例化）
│   └── Vehicle/vehicle_2d.tscn        ← 车辆 Sprite
├── renderer_3d/                       ← 3D 渲染（⚠️未接入，信号缺失）
│   ├── renderer_3d.gd/.tscn
│   ├── map_container_3d.gd/.tscn
│   ├── vehicle_marker_3d.gd/.tscn
│   └── path_line_3d.gd/.tscn
├── ui/
│   ├── button_list.gd/.tscn           ← Lock Camera / Goto / 录音按钮
│   ├── text_input.gd/.tscn            ← 自然语言输入框
│   ├── help_label.gd/.tscn            ← 操作说明（⚠️未挂载，文本过时）
│   ├── ui.gd/.tscn                    ← UI 父容器（⚠️未使用）
│   ├── scaler/scale.gd/.tscn + axis_ruler.gd  ← 坐标标尺
│   └── WebSocket/
│       ├── vehicle_panel.gd/.tscn     ← 单车信息面板
│       └── vehicle_panel_manager.gd/.tscn  ← 多面板总管
├── util/
│   ├── util.gd/.tscn                  ← 工具箱容器（挂 LLM）
│   └── llm.gd/.tscn                   ← DeepSeek 自然语言翻译
├── utils/coords.gd                    ← CoordUtils 坐标转换
├── websocket/protocol/                ← Orion 协议编解码（连接层退役，协议层保留）
│   ├── protocol_def.gd                ← 常量 + mission type 归一化
│   ├── orion_frame.gd                 ← MAVLink 风格帧编解码（大端）
│   ├── orion_messages.gd              ← 5 种消息 payload 编解码 + Build_Cmd
│   ├── message_builder.gd             ← 下行命令构造
│   └── message_parser.gd              ← 上行帧解析（parse_orion_frame）
└── test/
    ├── test_orion_protocol.gd         ← 协议 headless 单测
    └── audio_record_test.gd/.tscn     ← 录音验证场景
```

## 连接流程（KernelBridge）

无 hello 握手。车辆身份 = libp2p peer_id（帧头 sysid 完整字节），Pictor 侧以 hex 编码作为 `vehicle_id`：

```
1. Rust libp2p 连接建立 → kernel.peer_connected(peer_id hex)
2. KernelBridge._on_peer_connected → EventBus.vehicle_registered(peer_id)
3. Renderer2D 收到 → 实例化 vehicle_2d.tscn
4. VehiclePanelManager 收到 → 实例化 vehicle_panel.tscn
5. kernel.peer_info_updated → EventBus.peer_info_updated → 面板显示车名
6. 之后数据（pose / map_full / map_delta）正常流转
7. 断开 → kernel.peer_disconnected → vehicle_unregistered → 清理 Sprite/面板/相机/选中
```

## Protocol 层

协议定义/构造/解析统一在 `src/websocket/protocol/`，Orion 统一通信协议（MAVLink 风格帧，大端）：

| 文件 | 职责 |
|------|------|
| `ProtocolDef` | 常量集中管理（MSGID_*/ACTION_*/MISSION_TYPE_*/LOG_ODDS_*/SYSID*/COMPID*/MAP_*）+ `Mission_Type_From()` 归一化 |
| `OrionFrame` | 帧编解码：magic 0x4F + len u32 + seq + sysid_len + sysid(变长 peer_id) + compid + msgid u16 + payload + checksum |
| `OrionMessages` | 5 种消息 payload 编解码（大端）+ 下行组装入口 `Build_Cmd` |
| `MessageBuilder` | 下行命令构造（返回带 msgid 的 Dictionary） |
| `MessageParser` | 上行帧解析 `parse_orion_frame`（`parse_json`/`MSG_HELLO` 为遗留死代码） |

5 种消息：

| msgid | 消息 | 方向 |
|---|---|---|
| 1 | `ORION_POSE`（33B，含意图 valid/sub_gx/sub_gy） | 车 → 终端 |
| 2 | `ORION_MAP_FULL`（log-odds i8 整表） | 双向 |
| 3 | `ORION_MAP_DELTA`（差分 Δ 累加） | 车 → 终端 |
| 4 | `ORION_MANUAL_CONTROL`（action + param） | 终端 → 车 |
| 5 | `ORION_TASK_SET`（任务队列，含 members 群发） | 终端 → 车 |

`ORION_TASK_SET` mission type：**0 = `Goto`，1 = `Circle`**（Task 24）。Circle 的 `x/y` = 圆心（世界坐标，米），**半径写死 0.5m 不进协议**，车端按 peer_id 字节升序在环上均匀铺开。

身份约定：终端上行 = 空 sysid（sysid_len=0）+ compid=200；车 = compid=1。

## 地图存储架构

```
MapData2D (Node, %MapData2D)
├── Chunk 大小: 256×256 cells
├── 存储: Dictionary{Vector2i(chunk_x, chunk_y) → ChunkData2D}
├── Cell 编码: log-odds i8（−8~+8，u8 位模式存储，clamp ±8）
├── 显示三态: 阈值 ±6 派生（>+6 Occupied / <−6 Free / 其余 Unknown）
├── 持久化: user://map_data_2d/（_save_chunk 已注释，暂关闭）
└── API:
    ├── set_full(vehicle_id, chunk_x, chunk_y, cells)  ← replace 语义
    ├── set_delta(voxels)                              ← 累加式（先加后 clamp）
    ├── get_cell(gx, gy) → int（i8）
    ├── get_chunk_cells(cx, cy) → PackedByteArray
    └── load_chunk(cx, cy) → PackedByteArray（无调用者）
```

地图更新触发链：

- **全量更新**：`set_full` → 写入 ChunkData2D（replace + clamp）→ `chunk_updated.emit` → Renderer2D → MapContainer2D 全量重绘
- **增量更新**：`set_delta` → 逐 cell `clampi(old+Δ, ±8)` → `cells_changed.emit` → Renderer2D → MapContainer2D 增量重绘

> ⚠️ 多车地图合并暂缓：`set_full` 当前为 replace 语义（单表），`MapAccumulator` 存在但未接入；`map_delta_received` 未携带 vehicle_id。

## EventBus 信号（15 个）

| 信号 | 发送者 | 接收者 | 说明 |
|------|------|------|------|
| `pose_received(vehicle_id, pose)` | KernelBridge | Renderer2D, VehiclePanelManager, Camera2D | 车辆位姿 |
| `map_full_received(vehicle_id, chunk_x, chunk_y, cells)` | KernelBridge | MapData2D | 全量地图（own 表） |
| `map_delta_received(voxels)` | KernelBridge | MapData2D | 增量地图（无 vehicle_id） |
| `chunk_updated(chunk_x, chunk_y)` | MapData2D | Renderer2D | 全量重绘触发 |
| `cells_changed(updates)` | MapData2D | Renderer2D | 增量重绘触发 |
| `vehicle_registered(vehicle_id)` | KernelBridge | Renderer2D, VehiclePanelManager | peer 接入 |
| `vehicle_unregistered(vehicle_id)` | KernelBridge | Renderer2D, VehiclePanelManager, Camera2D | peer 断开 |
| `peer_info_updated(vehicle_id, peer_name)` | KernelBridge | VehiclePanelManager | 车名更新 |
| `selection_changed(id)` | （无） | （无） | ⚠️ 孤儿信号 |
| `cmd_send(targets: Array[String], cmd)` | InputHandler, AutoHandler, VehiclePanelManager | KernelBridge | 控制指令下发 |
| `goto_issued(x, y)` | AutoHandler | InputIndicator | Goto/Circle 目标高亮 |
| `mode_transited(mode)` | AppStateResource (setter) | Camera2D | Mode 切换 |
| `audio_record_started` | button_list | audio_input | 录音开始 |
| `audio_record_finished` | button_list | audio_input | 录音结束 |
| `command_requested(text)` | text_input | auto_handler | 自然语言指令 |

## 数据流

### pose（车辆位姿）

```
车 → Rust robot_frame → KernelBridge._on_robot_frame
  → MessageParser.parse_orion_frame → msgid=1
  → EventBus.pose_received(vid, pose)
      ├─ Renderer2D: 更新 vehicle_2d 位姿（CoordUtils.real_to_game + yaw）
      ├─ Camera2D: 仅 FOLLOW 且 vid==selected_id 时更新 lerp 目标
      └─ VehiclePanelManager: 面板更新位姿/速度
```

### map_full / map_delta

```
车 → robot_frame → parse_orion_frame
  ├─ msgid=2 → map_full_received(vid, chunk_x, chunk_y, cells) → MapData2D.set_full（replace）
  └─ msgid=3 → map_delta_received(voxels) → MapData2D.set_delta（累加 clamp）
```

### cmd（控制指令）

```
Manual 模式（键盘 WASD）:
  按 W/A/S/D/Space → InputHandler._input → build_manual_*
    → cmd_send.emit([manual_target], cmd)   # 无手动车则忽略

Goto（右键点地图）:
  右键 → AutoHandler._unhandled_input → game_to_tile → tile_to_real
    → build_auto_push_goto(x, y) → cmd_send.emit(selected_ids, cmd) + goto_issued

Circle（Z 键待命 + 左键点圆心）:
  Z → _pending_action = CIRCLE → 左键 → _execute_pending
    → build_auto_push_circle(x, y) → cmd_send.emit(selected_ids, cmd) + goto_issued

LLM（自然语言）:
  TextInput → command_requested → AutoHandler → util.llm.generate_cmds
    → cmds_generated → build_task_set(cmds) → cmd_send.emit(selected_ids, cmd)

下行:
  cmd_send → KernelBridge._on_cmd_send(targets, cmd)
    ├─ TASK_SET 且无 members → 按 targets 的 hex_decode 填 members
    ├─ OrionMessages.Build_Cmd(cmd) → 完整帧（空 sysid + compid=200）
    └─ for id in targets: kernel.send_command(id, frame)
```

### 车辆注册 / 注销

```
peer_connected → vehicle_registered(peer_id)
    ├─ Renderer2D: vehicle_2d.tscn 实例化 → add_child
    └─ VehiclePanelManager: vehicle_panel.tscn 实例化 → add_child

peer_disconnected → vehicle_unregistered(peer_id)
    ├─ Renderer2D / VehiclePanelManager: queue_free
    └─ Camera2D: 若跟随后断开 → IDLE
```

### Mode 状态机 / 选中车辆

- `app_state.mode`（NONE/FOLLOW/GOTO）setter → `mode_transited.emit`，**当前仅 Camera2D 响应**（FOLLOW→跟车，其它→IDLE）。⚠️ GOTO 模式无实际消费方——右键 Goto 由 AutoHandler 直接处理，不检查 `app_state.mode`。
- 选中：Ctrl+左键点面板（`panel_clicked`）增删 `selected_ids`；面板 Manual CheckButton（`mode_toggled`）维护 `manual_target`（至多 1 辆）+ 下发 manual/auto 切换。
- `selected_id` = `selected_ids[0]` 的只读计算属性（不 emit `selection_changed`）。

## 坐标系

| 项目 | 真实世界 | 游戏世界 (Godot 2D) |
|------|---------|---------------------|
| 单位 | 1 米 | 32 像素 |
| 1 tile | 0.5m × 0.5m | 16 像素 |
| Chunk | 256×256 tile = 128m×128m | — |

`CoordUtils`（`src/utils/coords.gd`）：`real_to_game` / `game_to_real` / `game_to_tile` / `tile_to_game` / `tile_to_real` / `real_to_game_3d`。

⚠️ 3D 渲染器硬编码 `SCALE := 16.0`，与 CoordUtils 的 `32.0` 不一致（3D 暂不可用）。

## 多车数据模型

| 组件 | 数据结构 | 说明 |
|------|---------|------|
| Renderer2D | `_vehicles: {vehicle_id → Node2D}` | 车辆 Sprite |
| VehiclePanelManager | `_panels: {vehicle_id → VehiclePanel}` | 车辆面板 |
| AppStateResource | `selected_ids: Array[String]`、`manual_target: String` | 选中列表 / 手动车 |
| KernelBridge | （无字典） | Peer 列表由 Rust libp2p swarm 维护 |

车辆生命周期：`peer_connected` → 创建 Sprite + Panel → 数据流转 → `peer_disconnected` → 清理全部资源。

## 已知问题

| 严重度 | 问题 | 位置 |
|--------|------|------|
| 🔴 | `zoom_changed`/`voxel_received`/`path_received` 信号引用但未定义 | zoom_slider.gd / renderer_3d.gd |
| 🔴 | DeepSeek API Key 明文硬编码 | src/util/llm.tscn |
| 🟡 | `map_delta_received` 无 vehicle_id（多车增量无法区分来源） | event_bus.gd / kernel_bridge.gd |
| 🟡 | `selection_changed` 孤儿信号（无收发） | event_bus.gd |
| 🟡 | renderer_3d 未接入 + SCALE=16 与 CoordUtils=32 不一致 | renderer_3d/ |
| 🟡 | ui.tscn/ui.gd 未使用（ZoomSlider/HelpLabel 永不实例化） | src/ui/ |
| 🟡 | Mode.GOTO 形同虚设（右键 Goto 不检查 mode） | auto_handler.gd |
| 🟡 | 地图持久化关闭（`_save_chunk` 注释，`load_chunk` 无调用者） | map_data_2d.gd |
| 🟡 | audio_input 写 `res://recordings/`（导出后只读，应 user://） | audio_input.gd |
| 🟡 | auto_handler `get_node("../../Util")` 直连（违反规范，应 @export/EventBus） | auto_handler.gd |
| 🟡 | `parse_json`/`MSG_HELLO` 死代码（JSON 握手整套残留） | message_parser.gd / protocol_def.gd |
| 🟢 | menu.gd 未接入；path_line_2d 未实例化 | src/main/、renderer_2d/ |
| 🟢 | main.tscn 残留 `.tmp` 编辑器临时文件 | src/main/ |
| 🟢 | kernel_test/pictor_kernel.gdextension.uid 孤儿 UID 文件 | kernel_test/ |
| 🟢 | help_label 文本过时（未提 Lock Camera/Goto/LLM/Circle） | help_label.gd |
| 🟢 | 文件头归属注释不统一（"Presented" vs "Present"） | 多处 |
| 🟢 | tool/gen_chunk_0_0.gd 内 1 处硬编码 `load("res://...")` | tool/ |
