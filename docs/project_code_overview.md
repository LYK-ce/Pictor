# Pictor 项目代码全景梳理报告

> 生成方式：逐文件人工阅读源码（50 个 GDScript + 1 个 Python 工具），对照 `Architecture/architecture.md` 与 `.github/instructions.md`。
> 说明：本报告以**实际代码为准**。架构文档多处已过时，差异点集中列于「第六节 差异清单」。

---

## 〇、统计速览

| 项目 | 数值 |
|------|------|
| GDScript 模块数（`.gd`） | **50** |
| Python 工具脚本（`.py`） | 1（`tool/tile_cut.py`） |
| EventBus 信号总数 | **18** |
| 架构文档差异清单条数 | **24** |
| 已知问题（严重 🔴） | 2 |
| 已知问题（中等 🟡） | 11 |
| 已知问题（轻微 🟢） | 16 |
| 已知问题合计 | **29** |

---

## 一、文件索引表（按目录组织）

### src/ 运行时源码

| 目录 | 文件 | 职责一句话 | 关键 class/signal/const |
|------|------|-----------|------------------------|
| `src/event_bus/` | `event_bus.gd` | Autoload 全局事件总线 | 18 个 signal |
| `src/app_state/` | `app_state.gd` | 全局共享状态 Resource | `AppStateResource`；`Mode{NONE,FOLLOW,GOTO}`；`selected_ids`/`manual_target`/`mode` |
| `src/main/` | `main.gd` | 入口节点（仅打印子节点数） | — |
| | `menu.gd` | 启动渲染模式菜单（⚠️未接入主场景） | `renderer_selected` 信号 |
| `src/camera/` | `camera_2d.gd` | 2D 相机（中键拖拽/边缘滚动/滚轮缩放/FOLLOW 跟车） | `State{IDLE,FOLLOW}` |
| `src/control/` | `input_handler.gd` | 手动控制：键盘 WASD/Space → manual cmd | `_KEY_MAP` |
| | `auto_handler.gd` | 自动编排：右键 Goto + LLM 指令下发 | `PendingAction{NONE,PATROL}` |
| | `audio_input.gd` | 麦克风录音节点（EventBus 控制起停，存 wav） | `RECORD_DIR` |
| `src/renderer_2d/` | `renderer_2d.gd` | 2D 渲染总管：车辆/地图信号分发 | — |
| | `map_data_2d.gd` | 地图数据层（Chunk 分块，log-odds 存储） | `CHUNK_SIZE=256` |
| | `chunk_data_2d.gd` | Chunk Resource 类型 + i8/u8 转换 | `ChunkData2D.to_i8/to_u8/to_state` |
| | `map_accumulator.gd` | 地图合并纯静态助手（多车聚合） | `MapAccumulator.add_full/apply_delta_bytes` |
| | `map_container_2d.gd` | 纯渲染层：TileMapLayer 重绘 | `TERRAIN_*` |
| | `input_indicator.gd` | Goto 目标点高亮框（淡出动画） | — |
| | `path_line_2d.gd` | 路径线条（⚠️未实例化） | `set_points` |
| | `Vehicle/vehicle_2d.gd` | 车辆 Sprite 节点（姿态应用） | `yaw_offset`、`apply_pose` |
| `src/renderer_3d/` | `renderer_3d.gd` | 3D 渲染总管（⚠️未接入，信号缺失） | — |
| | `map_container_3d.gd` | MultiMesh 体素渲染 | `set_cell/set_full/set_delta/get_cell` |
| | `vehicle_marker_3d.gd` | 3D 车辆标记（硬编码 SCALE=16） | `update_pose` |
| | `path_line_3d.gd` | 3D 路径线条（ImmediateMesh，SCALE=16） | `set_points` |
| `src/websocket/` | `websocket_client.gd` | 单车 WS 连接组件（hello 门控 + Orion 帧转发） | `State{DISCONNECTED,CONNECTING,CONNECTED}` |
| | `websocket_manager.gd` | 多连接总管（cmd 下发 + members 填充 + map 返还） | `_vehicles`/`_peer_ids` |
| `src/websocket/protocol/` | `protocol_def.gd` | Orion 协议常量集中管理 | `MSGID_*`/`ACTION_*`/`LOG_ODDS_*` |
| | `message_builder.gd` | 下行命令构造器（返回带 msgid 的 Dictionary） | `build_*` |
| | `message_parser.gd` | 上行解析（JSON hello + Orion 帧分发） | `parse_json`/`parse_orion_frame` |
| | `orion_frame.gd` | Orion 帧编解码（大端 helper） | `Encode_Frame`/`Decode_Frame` |
| | `orion_messages.gd` | 5 种消息 payload 编解码 + 下行组装 | `Encode_*/Decode_*`/`Build_Cmd` |
| `src/ui/` | `ui.gd` | UI 父容器（⚠️未接入主场景） | — |
| | `button_list.gd` | Lock Camera / Goto / 录音按钮 | — |
| | `help_label.gd` | 操作说明标签（⚠️未挂载，文本过时） | — |
| | `text_input.gd` | 自然语言指令输入框 → command_requested | — |
| `src/ui/WebSocket/` | `websocket_menu.gd` | Connect 按钮弹窗入口 | — |
| | `web_socket_creation_menu.gd` | 地址/端口输入弹窗 | — |
| | `vehicle_panel.gd` | 单车信息面板（Manual/断开/选中） | `PanelState`、`panel_clicked`/`mode_toggled` |
| | `vehicle_panel_manager.gd` | 多面板总管 + 选中/手动状态维护 | — |
| `src/ui/zoom_slider/` | `zoom_slider.gd` | 缩放滑块（⚠️引用不存在的 zoom_changed） | — |
| `src/ui/scaler/` | `scale.gd` | 坐标标尺总控（驱动 x/y 轴 + 状态栏） | `Scale` |
| | `axis_ruler.gd` | 单轴标尺条（_draw 绘制刻度） | `AxisRuler` |
| `src/util/` | `util.gd` | 工具箱容器（聚合 LLM 等工具） | `Util` |
| | `llm.gd` | 自然语言 → 指令序列（DeepSeek HTTP） | `LLM`；`cmds_generated`/`request_failed` |
| `src/utils/` | `coords.gd` | 坐标转换纯静态工具 | `CoordUtils.SCALE=32/TILE_SIZE=16` |
| `src/test/` | `test_ws_server.gd` | 模拟小车（TCPServer+WS，Orion 参考实现） | 运动/地图/任务模拟 |
| | `test_orion_protocol.gd` | Orion 协议 headless 单测（16 个测试函数） | — |
| | `test_e2e_orion.gd` | 单车全链路 headless e2e | — |
| | `test_e2e_multivehicle.gd` | 两车握手/聚合/群发 e2e | — |
| | `audio_record_test.gd` | 录音回放测试 | — |

### kernel_test/（Rust GDExtension 验证）

| 文件 | 职责 |
|------|------|
| `test_boot.gd` | 挂节点测试：验证 PleiadesKernel 的 ready + 后台 bootstrap + kernel_ready 信号 |
| `test_kernel.gd` | 最小测试：验证 libpictor_kernel.so 加载、PleiadesKernel 类注册与实例化 |
| `test_scene.gd` | 场景模式：验证类注册后退出 |
| `pictor_kernel.gdextension` | 扩展清单（linux x86_64 → `bin/libpictor_kernel.so`） |

### tool/

| 文件 | 职责 |
|------|------|
| `gen_chunk_0_0.gd` | 生成 `Assets/2D/map_chunk_0_0.tres`（确定性 log-odds 图） |
| `tile_cut.py` | PNG 网格切图工具（PIL） |

---

## 二、模块清单（关键符号 / 依赖 / 职责）

### 2.1 核心：EventBus 与 AppState

**`src/event_bus/event_bus.gd`** — `extends Node`，Autoload 单例（project.godot 中唯一 autoload）。
- 18 个信号（见第三节全景）。
- 无任何逻辑，纯信号容器。依赖：无。

**`src/app_state/app_state.gd`** — `class_name AppStateResource extends Resource`。
- `enum Mode { NONE, FOLLOW, GOTO }`
- `var selected_ids: Array[String] = []`（多选车辆列表，Goto/LLM 广播目标）
- `var selected_id: String`（**只读计算属性** = selected_ids[0] 或 ""，无 setter）
- `var manual_target: String = ""`（手动操控目标，至多 1 辆）
- `var mode := Mode.NONE`（setter 内 emit `EventBus.mode_transited`）
- 依赖：EventBus。
- 通过 `app_state.tres`（uid://lgqkjwhvgs1f）在 camera/input_handler/auto_handler/button_list/vehicle_panel_manager 间共享。

### 2.2 协议层（`src/websocket/protocol/`）

**`protocol_def.gd`** — `class_name ProtocolDef extends RefCounted`，全部为 `const`：
- `MSG_HELLO="hello"`；`MSGID_POSE=1 / MAP_FULL=2 / MAP_DELTA=3 / MANUAL_CONTROL=4 / TASK_SET=5`
- `ACTION_FORWARD=0 … ACTION_SWITCH_TO_AUTO=9`；`MANUAL_DEFAULT_SPEED=50`
- `MISSION_TYPE_GOTO=0`
- `CELL_FREE=0 / CELL_OCCUPIED=100 / CELL_UNKNOWN=255`（显示层派生三态，线上不传输）
- `LOG_ODDS_CLAMP=8 / LOG_ODDS_THRESHOLD=6`（车端 grid.rs 对齐）
- `SYSID_LEN_MAX=255 / COMPID_VEHICLE=1 / COMPID_TERMINAL=200`
- `MAP_RESOLUTION=0.5 / MAP_WIDTH=256 / MAP_HEIGHT=256 / CHUNK_SIZE=256`

**`orion_frame.gd`** — `class_name OrionFrame extends RefCounted`。MAVLink 风格帧（全大端）：
- 帧布局：`magic(0x4F) + len(u32) + seq(u8) + sysid_len(u8) + sysid(N) + compid(u8) + msgid(u16) + payload(M) + checksum(u16)`；`FIXED_HEADER_SIZE=10`，总开销 12+N。
- 大端 helper：`Write/Read_U16_BE、S16、U32、S32、F32`。
- `Encode_Frame(msgid, sysid, compid, payload)`、`Decode_Frame(pkt) → {ok,msgid,sysid,compid,payload,error}`。
- 注释明确：sysid = 发送方 libp2p PeerId；终端上行空 sysid + compid=200；seq/checksum 恒 0。

**`orion_messages.gd`** — `class_name OrionMessages extends RefCounted`。5 种消息 payload 编解码：
- POSE 33B（u32 time + 5×f32 + valid u8 + sub_gx i32 + sub_gy i32）
- MAP_FULL 20B 头 + data（log-odds i8）
- MAP_DELTA 6B + 9B/entry（delta i8 差分累加式）
- MANUAL_CONTROL 3B（u8 action + i16 param）
- TASK_SET 2B + members[]（len u8+变长）+ 9B/mission（群发扩展）
- `Build_Cmd(cmd: Dictionary) → PackedByteArray`：按 msgid 组装完整帧（空 sysid + COMPID_TERMINAL）。

**`message_builder.gd`** — `class_name MessageBuilder extends RefCounted`，下行构造（返回带 `msgid` 的 Dictionary）：
- `build_mode_switch_to_manual/auto()`、`build_manual_forward/backward/spin_left/spin_right/action/stop()`
- `build_auto_push_goto(x,y)`、`build_task_set(missions)`（type 归一化）、`build_auto_cancel()`
- `build_map_full(cells, origin_gx, origin_gy, width, height, resolution)`
- 依赖：ProtocolDef。

**`message_parser.gd`** — `class_name MessageParser extends RefCounted`：
- `parse_json(text) → {ok,type,data,error}`：**仅** hello 使用；其余 JSON 类型被客户端忽略。
- `parse_orion_frame(pkt) → {ok,msgid,data,error}`：Decode_Frame 后按 msgid 分发到 5 种 Decode_*；MAP_FULL 把 origin 换算为 chunk 坐标（floori(origin/256)）。
- 依赖：OrionFrame、OrionMessages、ProtocolDef。

### 2.3 连接层（`src/websocket/`）

**`websocket_client.gd`** — `extends Node`，每车一个实例。
- `enum State { DISCONNECTED, CONNECTING, CONNECTED }`；信号 `connected`/`disconnected`。
- 状态：`_ws/_state/_url/_vehicle_id/_peer_id/_identified/_reconnect_*`。
- `init(url)` → `_ready()` → `_connect()`（缓冲区 4MB）。
- `_process`：poll + 状态提升 + `_read_packets()`。
- 文本帧 → `parse_json`：hello 设 `_vehicle_id/_peer_id/_identified`，emit `vehicle_registered`；hello 前消息丢弃；其余 JSON 忽略（日志提示 legacy）。
- 二进制帧 → `_identified` 后 `parse_orion_frame` → `_match_orion_msg`：POSE→`pose_received`；MAP_FULL→统计 DEBUG + `map_full_received`；MAP_DELTA→`map_delta_received`。
- `send(text)` / `send_binary(pkt)` / getter 若干。
- 依赖：MessageParser、ProtocolDef、ChunkData2D（DEBUG 统计用）、EventBus。

**`websocket_manager.gd`** — `extends Node`，多连接总管。
- `@export var ws_client_scene: PackedScene`；`_vehicles{id→client}`、`_peer_ids{id→hex}`。
- `_ready` 连接：`ws_connect_requested`→`create_connection`；`ws_disconnect_requested`→`close_connection`；`vehicle_registered`→`_on_vehicle_registered`；`cmd_send`→`_on_cmd_send`；`map_merged`→`_on_map_merged`。
- `create_connection(url)`：实例化 client，url 为临时 key；`_on_vehicle_registered` 做 key 替换并登记 peer_id。
- `_on_cmd_send(targets, cmd)`：TASK_SET 且未带 members 时按 targets 查 `_peer_ids` 填 members；`OrionMessages.Build_Cmd` → 逐车 `send_binary`。
- `_on_map_merged(vehicle_id, cx, cy, cells)`：向该车返还合并全量（`build_map_full` → 再走 cmd_send）。
- `_on_client_disconnected` / `close_connection`：清理并 emit `vehicle_unregistered`。
- 依赖：ws_client_scene、MessageBuilder、OrionMessages、ProtocolDef、EventBus。

### 2.4 控制层（`src/control/`）

**`input_handler.gd`** — `extends Node`（类注释自称 "ManualHandler"）。
- `@export var app_state`；`const _KEY_MAP = {KEY_W:"forward", KEY_S:"backward", KEY_A:"spin_left", KEY_D:"spin_right", KEY_SPACE:"stop"}`。
- `_input`：按键非 echo → 无 manual_target 则忽略 → `build_manual_action/stop` → `EventBus.cmd_send.emit([manual_target], cmd)`。
- 依赖：MessageBuilder、EventBus、app_state。

**`auto_handler.gd`** — `extends Node2D`，自动控制编排。
- `@export var app_state`；`@onready var util := get_node("../../Util") as Util`（⚠️相对路径跨节点引用）。
- `enum PendingAction { NONE, PATROL }`；`_pending_action`。
- `_ready`：`command_requested`→`_on_command_requested`；延迟连接 `util.llm.cmds_generated/request_failed`。
- `_unhandled_input`：右键 → 未选车则忽略 → `game_to_tile`→`tile_to_real` → `build_auto_push_goto` → `cmd_send.emit(selected_ids, …)` + `goto_issued.emit`。
- `_on_cmds_generated(cmds)`：非空且已选车 → `build_task_set` → `cmd_send.emit(selected_ids, …)`。
- `_execute_pending` 为**空函数**（PATROL 扩展点，从未被赋值，死代码）。
- 依赖：Util、LLM、MessageBuilder、CoordUtils、EventBus、app_state。

**`audio_input.gd`** — `extends AudioStreamPlayer`。
- `const RECORD_DIR := "res://recordings/"`；`var record_effect: AudioEffectRecord`。
- `_ready`：取 "Record" bus 上第 0 个 effect；`audio_record_started`→`_On_Record_Started`；`audio_record_finished`→`_On_Record_Finished`（保存 wav，时间戳命名，保持原始格式）。
- 依赖：default_bus_layout.tres（Record bus）、EventBus。

### 2.5 渲染层（`src/renderer_2d/`、`src/renderer_3d/`、`src/camera/`）

**`map_data_2d.gd`** — `extends Node`（unique_name_in_owner，`%MapData2D`）。
- `CHUNK_SIZE=256`、`SAVE_DIR="user://map_data_2d/"`；`_chunks{Vector2i→ChunkData2D}`。
- `_ready`：`map_full_received`→`accumulate_full`；`map_delta_received`→`set_delta`。
- `accumulate_full`：incoming clamp ±8 → `MapAccumulator.add_full` 累加 → `chunk_updated.emit` + `map_merged.emit`。
- `set_delta`/`_group_by_chunk`/`set_chunk_delta`：按 chunk 分组，先加后 clamp ±8，`cells_changed.emit(changed)`；`_save_chunk` 调用被注释。
- 查询：`get_cell`（⚠️无调用者）、`get_chunk_cells`、`load_chunk`（⚠️无调用者）、`_count_states`（DEBUG）。
- 依赖：MapAccumulator、ChunkData2D、ProtocolDef、EventBus。

**`chunk_data_2d.gd`** — `class_name ChunkData2D extends Resource`。
- `@export var cells: PackedByteArray`；静态 `to_i8/to_u8/to_state`（阈值 ±6 派生三态）。

**`map_accumulator.gd`** — `class_name MapAccumulator extends RefCounted`（纯静态，无 Node 依赖，可 headless 单测）。
- `CLAMP=8/W=256/H=256`；`add_full(dst,src)`、`apply_delta_bytes(dst,voxels)`（先加后 clamp，越界忽略）。

**`map_container_2d.gd`** — `extends Node2D`，纯渲染层。
- `@onready _ground_layer/_wall_layer`；`render_chunk`（按阈值派生：>+6 墙 / <−6 地 / 其余不渲染）；`update_cells`（增量 erase+set）。
- 依赖：ChunkData2D、ProtocolDef。

**`renderer_2d.gd`** — `extends Node2D`。
- `@export var vehicle_scene`；`@onready _map/$MapContainer2D`、`_vehicle_container/$VehicleContainer`；`_vehicles{id→Node2D}`。
- 连接 `pose_received/chunk_updated/cells_changed/vehicle_registered/vehicle_unregistered`。
- `_on_pose`：`CoordUtils.real_to_game` + `apply_pose`（yaw 校准）；`_on_chunk_updated`：`%MapData2D.get_chunk_cells` → `_map.render_chunk`。
- 依赖：CoordUtils、EventBus、%MapData2D、vehicle_scene。

**`input_indicator.gd`** — `extends Node2D`；`goto_issued`→高亮框显示 + 0.2s 保持 + 0.4s 淡出。

**`vehicle_2d.gd`** — `extends Node2D`；`@export var yaw_offset = -PI/2`；`apply_pose(game_pos, yaw)`（position + rotation）。

**`path_line_2d.gd`** — `extends Node2D`；`set_points` 用 `real_to_game(x,z)` 画 Line2D。⚠️ 未被 renderer_2d.tscn 实例化，无调用者。

**`camera_2d.gd`** — `extends Camera2D`。
- `@export app_state/edge_margin/edge_speed/zoom_step/zoom_min/zoom_max`；`State{IDLE,FOLLOW}`。
- `_ready`：`mode_transited`→`_on_mode_transited`；`pose_received`→`_on_pose`；`vehicle_unregistered`→`_on_vehicle_unregistered`。
- `_process`：FOLLOW 时 lerp 跟车；否则边缘滚动。
- `_unhandled_input`：中键拖拽 + 滚轮缩放（以鼠标为中心）。
- `_on_pose`：仅 FOLLOW 且 `vehicle_id == app_state.selected_id` 时更新目标。
- 依赖：CoordUtils、EventBus、app_state。

**3D 渲染器（`src/renderer_3d/`）** — 整体未被 main.tscn 挂载；`renderer_3d.gd` 连接了**不存在的** `voxel_received`/`path_received`；`vehicle_marker_3d.gd` 与 `path_line_3d.gd` 内硬编码 `const SCALE := 16.0`（与 CoordUtils.SCALE=32 不一致）。

### 2.6 UI 层（`src/ui/`）

- **`ui.gd`**（`extends CanvasLayer`）：`@export zoom_slider_scene/help_label_scene`，`_ready` 实例化二者。⚠️ main.tscn 未使用 ui.tscn，故 ZoomSlider/HelpLabel 实际不创建。
- **`button_list.gd`**（`extends PanelContainer`）：Lock Camera 切换 `mode`（FOLLOW/NONE）、Goto 切换 `mode`（GOTO/NONE）、录音按钮按下/松开 emit `audio_record_started/finished`。依赖 app_state、EventBus。
- **`help_label.gd`**（`extends Label`）：文本 "W/S 前进/后退…"（未提 Lock Camera/Goto/LLM，过时）。
- **`text_input.gd`**（`extends Control`）：发送按钮 → `command_requested.emit(text)` + 清空。
- **`websocket_menu.gd`**：Connect 按钮 → 实例化 creation_menu_scene。
- **`web_socket_creation_menu.gd`**：地址/端口 → `ws_connect_requested.emit("ws://ip:port")` + 关闭。
- **`vehicle_panel.gd`**（`extends PanelContainer`）：`PanelState{NORMAL,MANUAL,AUTO}`；信号 `panel_clicked(vehicle_id, ctrl_held)`、`mode_toggled(vehicle_id, to_manual)`；`Update(id,pos,yaw,vel)` 更新 4 个 Label；`_on_disconnect_pressed`→`ws_disconnect_requested`；Ctrl+左键→`panel_clicked`；Manual CheckButton→`mode_toggled`；`set_panel_state/set_manual_checked/set_mode_label`。⚠️ 场景里有 `Address` Label 但脚本从不更新。
- **`vehicle_panel_manager.gd`**（`extends VBoxContainer`）：`@export vehicle_panel_scene/app_state`；`_panels{id→panel}`；连接注册/位姿/注销信号；`_on_panel_clicked`（Ctrl+点：手动车切回 auto、普通车 toggle 选中）；`_on_mode_toggled`（手动/自动切换 + `build_mode_switch_*` 下发 + selected_ids/manual_target 维护）；`_update_selection`（面板边框色/模式标签）。⚠️ 节点内联在 websocket_menu.tscn，无独立 .tscn。
- **`zoom_slider.gd`**（`extends Control`）：`EventBus.zoom_changed.connect/emit`——信号**不存在**。
- **`scale.gd`**（`class_name Scale extends Control`）：相机变换驱动两轴重绘 + 状态栏显示格子/世界坐标；`_inject_camera` 注入 AxisRuler。
- **`axis_ruler.gd`**（`class_name AxisRuler extends Control`）：`_draw` 绘制刻度（8/16/32 密度自适应）。

### 2.7 工具层（`src/util/`、`src/utils/`）

- **`util.gd`**（`class_name Util extends Node`）：`@onready var llm := $LLM`。
- **`llm.gd`**（`class_name LLM extends Node`）：DeepSeek OpenAI 兼容 API；`@export api_url/api_key/model/timeout`；`SYSTEM_PROMPT` 约束输出 missions JSON 数组；`generate_cmds(text)` 异步请求；`_on_request_completed` 解析 → `cmds_generated.emit(cmds)` / `request_failed.emit(msg)`；`_parse_cmds`（直接 JSON，失败提取 ```json 代码块）。⚠️ api_key 在 llm.tscn 中**明文硬编码**。
- **`coords.gd`**（`class_name CoordUtils extends RefCounted`）：`SCALE=32.0`（1 米=32px）、`TILE_SIZE=16.0`；`real_to_game/game_to_real（未用）/real_to_game_3d（未用）/game_to_tile/tile_to_game/tile_to_real`。

---

## 三、EventBus 信号全景（18 个）

### 3.1 全信号表

| # | 信号 | 参数 | 发送者（emit） | 接收者（connect） | 状态 |
|---|------|------|---------------|------------------|------|
| 1 | `pose_received` | vehicle_id:String, pose:Dictionary | websocket_client.gd | renderer_2d、camera_2d、vehicle_panel_manager、（renderer_3d 若挂载） | ✅ 正常 |
| 2 | `map_full_received` | vehicle_id, chunk_x:int, chunk_y:int, cells:PackedByteArray | websocket_client.gd | map_data_2d（accumulate_full） | ✅ 正常 |
| 3 | `map_delta_received` | voxels:Array | websocket_client.gd | map_data_2d（set_delta） | ⚠️ 无 vehicle_id，多车无法溯源 |
| 4 | `map_merged` | vehicle_id, chunk_x, chunk_y, cells | map_data_2d.gd | websocket_manager（_on_map_merged） | ✅ 正常（返还链路） |
| 5 | `chunk_updated` | chunk_x:int, chunk_y:int | map_data_2d.gd | renderer_2d（_on_chunk_updated） | ✅ 正常 |
| 6 | `cells_changed` | updates:Array | map_data_2d.gd | renderer_2d（_on_cells_changed） | ✅ 正常 |
| 7 | `ws_connected` | — | websocket_client.gd | （无） | 🟡 无人监听 |
| 8 | `ws_connect_requested` | url:String | web_socket_creation_menu、test_e2e_multivehicle | websocket_manager（create_connection） | ✅ 正常 |
| 9 | `ws_disconnect_requested` | vehicle_id:String | vehicle_panel.gd | websocket_manager（close_connection） | ✅ 正常 |
| 10 | `vehicle_registered` | vehicle_id, url | websocket_client.gd | websocket_manager、renderer_2d、vehicle_panel_manager | ✅ 正常 |
| 11 | `vehicle_unregistered` | vehicle_id | websocket_manager.gd | renderer_2d、vehicle_panel_manager、camera_2d | ✅ 正常 |
| 12 | `selection_changed` | id:String | （无） | （无） | 🔴 完全孤儿 |
| 13 | `cmd_send` | targets:Array[String], cmd:Dictionary | input_handler、auto_handler、vehicle_panel_manager、websocket_manager（返还路径再 emit） | websocket_manager（_on_cmd_send） | ✅ 正常（签名已变） |
| 14 | `goto_issued` | x:float, y:float | auto_handler.gd | input_indicator.gd | ✅ 正常 |
| 15 | `mode_transited` | mode:int | app_state.gd（mode setter） | camera_2d（_on_mode_transited） | ⚠️ 接收者少于文档所述 |
| 16 | `audio_record_started` | — | button_list.gd | audio_input.gd | ✅ 正常 |
| 17 | `audio_record_finished` | — | button_list.gd | audio_input.gd | ✅ 正常 |
| 18 | `command_requested` | text:String | text_input.gd | auto_handler.gd | ✅ 正常 |

### 3.2 与架构文档信号表对照

- 文档列 16 个信号 + 3 个「待修复」；实际定义 **18** 个。
- **文档未提及的新增信号（5）**：`map_merged`、`goto_issued`、`audio_record_started`、`audio_record_finished`、`command_requested`。
- **签名变更（2）**：`cmd_send(vehicle_id,cmd)` → `cmd_send(targets:Array[String],cmd)`；`map_full_received(chunk_x,chunk_y,cells)` → `map_full_received(vehicle_id,chunk_x,chunk_y,cells)`。
- **文档说「未定义待修复」实际仍缺失（3）**：`zoom_changed`（zoom_slider.gd 引用）、`voxel_received`、`path_received`（renderer_3d.gd 引用）——event_bus.gd 中均不存在。
- **文档说「无人监听」仍成立（2）**：`ws_connected`、`selection_changed`；且 `selection_changed` 现在**连发送者也没有**（app_state 不再 emit）。
- **接收者变化（1）**：文档称 `mode_transited` 接收者为 Camera/ControlMaster/InputIndicator；实际仅 Camera。

---

## 四、数据流（真实代码路径）

### 4.1 hello 握手（车辆注册）
```
web_socket_creation_menu._on_button_pressed
  → EventBus.ws_connect_requested.emit("ws://ip:port")
  → WebSocketManager.create_connection(url)
      实例化 ws_client_scene，name=url，init(url)，连接 disconnected 信号，add_child，
      _vehicles[url] = ws（url 为临时 key）
  → WebSocketClient._ready → _connect()（缓冲区 1<<22 = 4MB）
  → _process: poll，STATE_OPEN → connected.emit() + EventBus.ws_connected.emit()（无人监听）
  小车发 hello（JSON 文本）→ _on_message → MessageParser.parse_json → type=="hello"
  → _vehicle_id/_peer_id 记录，_identified=true
  → EventBus.vehicle_registered.emit(_vehicle_id, _url)
      ├─ WebSocketManager._on_vehicle_registered: _vehicles[url]→_vehicles[vehicle_id]，
      │    _peer_ids[vehicle_id] = ws.get_peer_id()
      ├─ Renderer2D._on_vehicle_registered: vehicle_scene.instantiate → VehicleContainer.add_child
      └─ VehiclePanelManager._on_vehicle_registered: vehicle_panel_scene.instantiate → add_child
```

### 4.2 pose（Orion 二进制帧 msgid=1）
```
小车 ──binary──→ WebSocketClient._read_packets（_identified 后）
  → MessageParser.parse_orion_frame → MSGID_POSE → OrionMessages.Decode_Pose
    data = {time_boot_ms, x, y, vx, vy, yaw, valid, sub_gx, sub_gy}
  → EventBus.pose_received.emit(_vehicle_id, data)
      ├─ Renderer2D._on_pose: CoordUtils.real_to_game(x,y)→position；rotation=yaw+yaw_offset（apply_pose）
      ├─ Camera._on_pose（仅 FOLLOW 且 vehicle_id==selected_id）: 更新 lerp 目标
      └─ VehiclePanelManager._on_pose: panel.Update(id, "x, y", "yaw°", "vx, vy")
```

### 4.3 map_full（Orion 二进制帧 msgid=2，多车聚合 + 返还）
```
小车 ──binary──→ WebSocketClient → parse_orion_frame → MSGID_MAP_FULL
  → origin 换算 chunk 坐标（floori(origin/256)）→ data{cells:65536B log-odds}
  → DEBUG 三态统计 → EventBus.map_full_received.emit(vehicle_id, chunk_x, chunk_y, cells)
  → MapData2D.accumulate_full(vehicle_id, cx, cy, cells)
        incoming clamp ±8 → MapAccumulator.add_full(合并表, incoming)（整表累加）
        ├─ EventBus.chunk_updated.emit(cx, cy)
        │     └─ Renderer2D._on_chunk_updated → %MapData2D.get_chunk_cells → MapContainer2D.render_chunk
        │           阈值派生：lg>+6→WallLayer；lg<−6→GroundLayer；否则不渲染
        └─ EventBus.map_merged.emit(vehicle_id, cx, cy, cells)
              └─ WebSocketManager._on_map_merged: 该车仍在线 → cmd_send.emit([vehicle_id],
                   MessageBuilder.build_map_full(cells)) → _on_cmd_send → OrionMessages.Build_Cmd
                   → 二进制帧返还（车端 handle_map_full 替换 merged 表）
```

### 4.4 map_delta（Orion 二进制帧 msgid=3，累加式）
```
小车 ──binary──→ WebSocketClient → MSGID_MAP_DELTA → data{voxels:[{gx,gy,delta:i8}]}
  → EventBus.map_delta_received.emit(voxels)   ⚠️ 无 vehicle_id
  → MapData2D.set_delta(voxels)
       _group_by_chunk（按 256 分块，转局部 lx/ly）→ set_chunk_delta
       每格：new = clamp(old + delta, −8, +8)，写入合并表
       → EventBus.cells_changed.emit(changed[{gx,gy,log_odds}])
            └─ Renderer2D._on_cells_changed → MapContainer2D.update_cells（增量 erase+set tile）
```

### 4.5 cmd 下行（统一走 cmd_send → Build_Cmd 二进制帧）
```
Manual:  input_handler._input（W/A/S/D/Space）
         → MessageBuilder.build_manual_action/stop
         → EventBus.cmd_send.emit([app_state.manual_target], cmd)

Goto:    auto_handler._unhandled_input（右键）
         → game_to_tile → tile_to_real → build_auto_push_goto(x,y)
         → EventBus.cmd_send.emit(app_state.selected_ids, cmd)
         + EventBus.goto_issued.emit(x,y) → InputIndicator 高亮

LLM:     text_input._on_send_pressed → command_requested.emit(text)
         → auto_handler._on_command_requested → util.llm.generate_cmds(text)
         → HTTP → llm._on_request_completed → cmds_generated.emit(cmds)
         → auto_handler._on_cmds_generated → build_task_set(cmds)
         → EventBus.cmd_send.emit(app_state.selected_ids, task_set)

模式切换: vehicle_panel_manager（Manual 勾选 / Ctrl+点击）
         → build_mode_switch_to_manual/auto → cmd_send.emit

汇聚:    websocket_manager._on_cmd_send(targets, cmd)
         TASK_SET 且未带 members → 按 targets 查 _peer_ids 填 members（群发）
         → OrionMessages.Build_Cmd(cmd) → 帧 → 对每个 target 的 ws.send_binary
```

### 4.6 车辆注销
```
路径 A（远端断开）: WebSocketClient._disconnect → disconnected.emit
  → WebSocketManager._on_client_disconnected → _vehicles/_peer_ids.erase → vehicle_unregistered.emit
路径 B（UI 断开）: VehiclePanel._on_disconnect_pressed → ws_disconnect_requested.emit
  → WebSocketManager.close_connection → queue_free + erase → vehicle_unregistered.emit
清理: Renderer2D（queue_free Sprite）、VehiclePanelManager（queue_free 面板 + 从
      selected_ids/manual_target 移除 + FOLLOW 退出）、Camera（跟随中断开→IDLE）
```

### 4.7 音频录音链路
```
button_list 按下 → EventBus.audio_record_started.emit()
  → audio_input._On_Record_Started → Record bus AudioEffectRecord.set_recording_active(true)
button_list 松开 → EventBus.audio_record_finished.emit()
  → audio_input._On_Record_Finished → set_recording_active(false) → get_recording()
  → 保存 res://recordings/record_<timestamp>.wav（保持原始格式）
```

### 4.8 Mode 状态机（现状）
```
button_list Lock Camera 切换 → app_state.mode = FOLLOW / NONE
button_list Goto 切换      → app_state.mode = GOTO / NONE（⚠️无实际消费方）
app_state.mode setter → EventBus.mode_transited.emit(mode)
  → 仅 camera_2d 响应：FOLLOW→State.FOLLOW；其他→State.IDLE
```
⚠️ 右键 Goto 由 AutoHandler 直接处理，**不检查 app_state.mode**；Mode.GOTO 与 InputIndicator 均已与 Goto 流程解耦。

---

## 五、已知问题与隐患（按严重度分级，共 29 条）

### 🔴 严重（2 条）

1. **EventBus 缺失 3 个被引用信号**：`zoom_changed`（src/ui/zoom_slider/zoom_slider.gd:20/25）、`voxel_received`、`path_received`（src/renderer_3d/renderer_3d.gd:14/15）在 event_bus.gd 中均未定义。这些组件一旦被挂载，`_ready` 即抛「信号不存在」错误。当前因 ZoomSlider（ui.tscn 未使用）与 Renderer3D（未挂载）都不在默认运行路径而暂不触发。
2. **API Key 明文硬编码**：`src/util/llm.tscn` 中 `api_key = "sk-c2398eab213a4e668b8d71cf109e5002"`。密钥已提交进场景文件，存在泄露风险；应改由环境变量/用户配置注入。

### 🟡 中等（11 条）

3. `map_delta_received(voxels: Array)` **无 vehicle_id 参数**，多车并发上报 DELTA 时无法区分来源，全部直接累加进共享合并表，多车增量语义不成立（阶段 2 多车聚合仅 FULL 路径完整）。
4. `selection_changed(id)` **完全孤儿**（无 emit、无 connect）；app_state 的 `selected_id` 已改为只读计算属性，选中变化不再广播，依赖方只能读 `selected_ids`。
5. `ws_connected` 无人监听（连接成功无消费方）。
6. **renderer_3d 未接入且坐标不一致**：全套 3D 场景未被任何场景引用；`vehicle_marker_3d.gd` 与 `path_line_3d.gd` 内硬编码 `SCALE := 16.0` 与 `CoordUtils.SCALE=32.0` 不一致；3D 渲染不可用。
7. **ui.tscn/ui.gd 未被使用**：main.tscn 的 UI 是内联 CanvasLayer，导致 ZoomSlider、HelpLabel 永不实例化（也掩盖了 zoom_changed 的缺失问题）。
8. **Mode.GOTO 形同虚设**：右键 Goto 由 AutoHandler 处理，与 `app_state.mode` 无关、不自动退出 GOTO；ControlMaster 节点无脚本；InputIndicator 只监听 `goto_issued`，不再响应 `mode_transited`。
9. **地图持久化被关闭**：`map_data_2d.gd:set_chunk_delta` 中 `_save_chunk` 调用被注释；`load_chunk` 亦无调用者（历史遗留 API）。
10. **audio_input 写 `res://recordings/`**：导出后 res:// 只读，录音文件无法落盘；应改用 user://。
11. **auto_handler 跨节点引用违规**：`@onready var util := get_node("../../Util")` 使用相对路径跨组件引用（规范要求 `@export` 注入或 EventBus 通信）。
12. **websocket_manager.get_state() 类型语义不一致**：client.get_state() 返回自定义 `State{DISCONNECTED=0,CONNECTING=1,CONNECTED=2}`，而 manager.get_state 在未找到时返回 `WebSocketPeer.STATE_CLOSED`（Godot 枚举），两套枚举混用。
13. `cmd_send` 信号签名已从 `(vehicle_id, cmd)` 变为 `(targets:Array[String], cmd)`，旧文档与潜在旧调用方需同步。

### 🟢 轻微（16 条）

14. `menu.gd`/`menu.tscn` 未接入主场景，`renderer_selected` 信号无人连接（渲染模式选择菜单为死代码）。
15. `path_line_2d.gd`/`.tscn` 未被 renderer_2d.tscn 实例化，`set_points` 无调用者。
16. `coords.gd` 的 `game_to_real`、`real_to_game_3d` 未使用（注释自标「预留」）。
17. `map_data_2d.get_cell`、`load_chunk` 无调用者。
18. `map_container_3d.get_cell`、`get_all_cells` 无调用者；`_set_instance` 的 `state` 参数未使用（颜色统一白色）。
19. `auto_handler._execute_pending` 为空函数，`PendingAction`/`_pending_action` 机制为死代码（PATROL 从未赋值）。
20. `button_list.gd:26` `print(self.name,'goto button pressed')` 用逗号拼接（应为字符串格式化）。
21. `vehicle_panel.tscn` 存在 `Address` 标签，但 `vehicle_panel.gd` 从不更新它。
22. `src/main/` 下残留 `main.tscn1970204676.tmp`、`main.tscn24281829.tmp` 编辑器临时文件。
23. `input_handler.gd` 类注释自称 "ManualHandler"，与文件名/实际类名不符。
24. `websocket_client.gd`、`map_data_2d.gd`、`renderer_2d.gd` 三处重复的 cell 三态统计 DEBUG 代码（架构文档已提）。
25. `help_label.gd` 文本过时（未提及 Lock Camera / Goto / LLM），且因 ui.tscn 未使用而不显示。
26. 文件头归属注释不统一：多数为 `Presented by KeJi`，`main.gd`、`websocket_client.gd` 等为 `Present by KeJi`。
27. 大量信号回调用 `_on_xxx`（lower_snake_case），违反「函数 PascalCase」命名规范（属 Godot 连接惯例，普遍存在：camera_2d、renderer_2d、auto_handler、vehicle_panel* 等）。
28. `web_socket_creation_menu.gd:9` `@onready var address =$Panel/...` 缺类型注解且 `=$` 无空格；第 10 行同。
29. `test_e2e_orion.gd:41,45` 与 `tool/gen_chunk_0_0.gd:15` 存在硬编码 `load("res://...")`（仅测试/工具脚本，规范禁止对象是运行时代码，属边界情况）。

### 硬编码 / 规范符合度专项检查
- `get_node("/root/...")`：**0 处**（符合规范；EventBus 直接以 Autoload 全局名引用）。
- `load("res://...")`：3 处（见上，均在 test/tool）。
- 场景引用：运行时组件（websocket_manager.ws_client_scene、renderer_2d.vehicle_scene、websocket_menu.creation_menu_scene/vehicle_panel_scene、vehicle_panel_manager.vehicle_panel_scene、ui.zoom_slider_scene/help_label_scene）均用 `@export … PackedScene`，**符合规范**。
- 子节点引用：普遍 `@onready var x := $Node`，符合规范；例外为 auto_handler 的 `get_node("../../Util")`。

---

## 六、与架构文档差异清单（24 条）

> 格式：「文档说 X → 实际 Y」。

1. 目录树未覆盖大量新文件：`control/audio_input.gd`、`control/auto_handler.gd`、`renderer_2d/map_accumulator.gd`、`ui/scaler/*`、`ui/text_input.gd`、`util/llm.gd`、`util/util.gd`、`websocket/protocol/orion_frame.gd`、`orion_messages.gd`、`test/test_orion_protocol.gd`、`test_e2e_orion.gd`、`test_e2e_multivehicle.gd`、`test/audio_record_test.gd`、`kernel_test/*`、`tool/*` → 实际均存在。
2. 文档称 `control/control_master.gd` 为「控制总管 (Goto + Manual)」→ 实际该文件**已删除**，ControlMaster 节点无脚本；Goto/LLM 移至 `auto_handler.gd`，Manual 保留在 `input_handler.gd`。
3. main.tscn 节点树不符：文档称 UI 为 ui.tscn 实例且含 ZoomSlider/ButtonList、Renderer3D 可选 → 实际 UI 为**内联 CanvasLayer**（挂 WebSocketMenu、Button(button_list)、TextInput、Scale），无 ZoomSlider、无 HelpLabel、无 Renderer3D；Camera2D 直接挂 Main 下。
4. 文档称 Renderer2D 树下有 `PathLine2D` → 实际 renderer_2d.tscn **无** PathLine2D（path_line_2d.tscn 存在但未实例化）。
5. 文档称 `vehicle_panel_manager.tscn` 独立场景 → 实际不存在，Vehicle_Panel_Manager 节点内联在 websocket_menu.tscn。
6. 协议层整体迁移：文档称 pose/map_full/map_delta 走 JSON 文本 → 实际全部走 **Orion 二进制帧**；JSON 仅保留过渡期 hello。
7. map_full 帧格式：文档称 65545 字节（1+4+4+65536，type=0）→ 实际为 Orion 帧（map_full 整帧 65568B：10B 头 + 20B payload 头 + 65536 data + 2B checksum）。
8. ProtocolDef 内容：文档称含 `CMD_MANUAL`、`BIN_CELLS_OFFSET` 等 → 实际已改为 Orion 常量（MSGID_*/ACTION_*/MISSION_TYPE_*/LOG_ODDS_*/SYSID/COMPID/MAP_*）。
9. MessageBuilder：文档仅列 build_manual_*/build_auto_push_goto → 实际新增 `build_mode_switch_to_manual/auto`、`build_task_set`、`build_auto_cancel`、`build_map_full`，返回带 msgid 的 Dictionary。
10. MessageParser：文档称 parse_json 解析 pose/map_delta → 实际 `parse_json` 仅处理 hello，其余 JSON 忽略；新增 `parse_orion_frame` 分发 5 种 msgid。
11. `cmd_send(vehicle_id:String, cmd)` → 实际 `cmd_send(targets:Array[String], cmd)`。
12. `map_full_received(chunk_x,chunk_y,cells)` → 实际 `map_full_received(vehicle_id,chunk_x,chunk_y,cells)`。
13. 新增 5 个信号：`map_merged`、`goto_issued`、`audio_record_started`、`audio_record_finished`、`command_requested`。
14. AppState：文档称 `selected_id` 有 setter 并 emit `selection_changed` → 实际为 `selected_ids` 数组 + `manual_target` + `mode`；`selected_id` 是只读计算属性；`selection_changed` 已无发送者。
15. `mode_transited` 接收者：文档称 Camera/ControlMaster/InputIndicator → 实际仅 Camera。
16. GOTO 流程：文档称「点击地图进入/自动退出 GOTO」由 ControlMaster._input 实现 → 实际右键 Goto 由 AutoHandler._unhandled_input 直接处理，与 Mode.GOTO 无关。
17. VehiclePanel：文档称 `TakeControl` 按钮 + `take_control_toggled` 信号 → 实际为 `Manual` CheckButton（mode_toggled）+ Ctrl+左键（panel_clicked）+ `Disconnect` 按钮。
18. 地图 cell 编码：文档称 0=可通行/1=不可通行/2=未知 → 实际存储 **log-odds i8**（−8~+8，u8 位模式），三态由显示层按阈值 ±6 派生。
19. `set_full` → 实际已改为 `accumulate_full`（MapAccumulator.add_full 累加语义，多车聚合），并新增 `map_merged` 触发终端返还下发。
20. WebSocketManager 新增 `_peer_ids` 表 + TASK_SET 自动按 targets 填 members（Task 22 群发）。
21. WebSocketClient 的 hello 新增携带 `peer_id`（hex）；hello 前二进制帧丢弃。
22. 新增音频/LLM 链路：button_list 录音按钮 + audio_input 录音；text_input + util/llm + auto_handler 的 LLM 指令编排。
23. map_delta 语义：文档称增量按 cell 写入 → 实际为**累加式**（先加后 clamp ±8），与车端 grid.rs 对齐。
24. 文档「已知问题」中 `zoom_changed`/`voxel_received`/`path_received` 三个缺失信号 → 实际**仍未修复**，且因 ZoomSlider/Renderer3D 未挂载而被掩盖。

---

## 七、测试与工具

### 7.1 src/test/（GDScript 测试，5 个）

| 文件 | 运行方式 | 覆盖范围 |
|------|---------|---------|
| `test_orion_protocol.gd` | `godot --headless --path . -s …` | Orion 协议 v2 单测：帧/5 种消息 roundtrip、大端字节序（与 Rust 端字节逐一比对）、log-odds i8 位模式、clamp、阈值边界、MapAccumulator、返还帧大小（65568B>默认 buffer）。共 16 个测试函数。 |
| `test_e2e_orion.gd` | `godot --headless --path . -s …` | 单车全链路 e2e：hello→pose→map_full(log-odds)→map_delta(1Hz)→manual_control→task_set 队列顺序→cancel。 |
| `test_e2e_multivehicle.gd` | 场景模式 `res://src/test/test_e2e_multivehicle.tscn` | 两车接入握手 e2e：own 上报→聚合→返还；断言 clamp(8+8)=8、MapData2D 表与返还一致；群发/单车 TASK_SET 的成员过滤。 |
| `test_ws_server.gd` | 场景/挂载使用 | 模拟小车（Robot Controller 参考实现）：TCPServer + WebSocketPeer；hello/pose/map_full/map_delta 上行；manual_control/task_set 下行；Turning→Moving 闭环；确定性 log-odds 图（variant 0/1）；1Hz delta 聚合。也是 main.tscn 中的内置测试车。 |
| `audio_record_test.gd` | 场景模式 | 录音→停止→回放测试，依赖 Record bus。 |

### 7.2 kernel_test/（Rust GDExtension 验证，3 个）

- 验证 `libpictor_kernel.so`（GDExtension）加载与 `PleiadesKernel` 类注册。
- `test_kernel.gd`：最小类注册/实例化测试（headless `-s`）。
- `test_boot.gd`：挂节点测试——`kernel_ready` 信号 + `poll()` + 40s 超时。
- `test_scene.gd`：场景模式类存在性测试。

### 7.3 tool/

- `gen_chunk_0_0.gd`：生成 `Assets/2D/map_chunk_0_0.tres`（确定性 log-odds 图，与 test_ws_server 变体 0 一致）。
- `tile_cut.py`：PNG 按网格切图（PIL），用于 tileset 素材切分。

---

## 八、命名与引用规范符合度总结

| 规则 | 符合度 | 说明 |
|------|--------|------|
| 中文思考/注释 | 基本符合 | 代码注释以中文为主 |
| 变量 lower_snake_case | 基本符合 | `_vehicles`、`_pending_action` 等 |
| 函数 PascalCase | **部分违反** | 大量 `_on_xxx` 回调为 lower_snake（Godot 惯例）；PascalCase 例：`_On_Record_Started`、`_Peer_Id_Bytes`、`_Normalize_Mission_Type`、`Update`、`apply_pose`（后两者为小写开头 public 方法，也偏离 PascalCase） |
| 常量 UPPER_SNAKE_CASE | 符合 | `CHUNK_SIZE`、`RECORD_DIR`、`SYSTEM_PROMPT` 等 |
| 场景引用 @export PackedScene | 符合 | 运行时组件均合规 |
| 子节点 @onready $Node | 基本符合 | 例外：auto_handler 的 `get_node("../../Util")` |
| 禁止 get_node("/root/...") | 符合 | 0 处 |
| 组件间 EventBus 通信 | 基本符合 | 例外：auto_handler 直调 `util.llm.generate_cmds`（经 Util 容器，属工具调用）；manager↔client、manager↔panel 为父子节点方法调用 |
| 禁止 .gd 硬编码 load("res://") | 边界违反 | 仅 test_e2e_orion.gd、tool/gen_chunk_0_0.gd（测试/工具） |

---

*（报告完）*
