# Task 21: Map Log-Odds 协议升级（Pictor 终端对齐）

> 📦 **已归档（2026-08-12）**：阶段 1（单车 log-odds 语义替换）与阶段 2（多车终端聚合 + 返还全量）全部完成并推送（631dff3 + a520f4c）。仅剩真车联调未执行（车端 WS 可用时）。

## 目标

按车端设计文档 `docs/multi_robot_map.md` §6.7，将 Pictor 的地图协议从**三态（0/100/255）**升级为 **log-odds i8（−8~+8）** 语义。**单车协议语义替换**（多车对账/终端聚合不在本任务范围，车端尚未实现）。

- MAP_FULL（msgid=2）：data 语义从三态字节 → **own 表的 log-odds i8**（u8 位模式直传），显示时按阈值 ±6 派生三态
- MAP_DELTA（msgid=3）：entry 从覆盖式三态 → **差分 Δ 累加式**，Pictor 维护本地 log-odds 缓冲表（65536×i8），**先加后 clamp ±8**
- 与车端**同批发布**（复用 msgid，无兼容过渡期）

## 状态

- 范围已确认（2026-08-11 用户澄清：车端三步**全部完成**，已核实代码；对账与多车未做，不在本任务）
- 修改方案已完成（2026-08-11 子 agent 调研：车端语义核实 + Pictor 逐文件方案）
- 参考：`docs/multi_robot_map.md`（§6.7 Pictor 对齐清单）

## 车端协议语义（子 agent 从车端代码核实，Pictor 必须精确匹配）

| 项 | 值 | 说明 |
|---|---|---|
| clamp | **±8** | 命中 +3 / 掠过 −1（不对称 3:1） |
| 阈值 | **±6** | **严格**：`>+6` Occupied / `<−6` Free / 恰好 ±6 为 Unknown |
| Δ 编码 | i8 位模式直传 | Rust `as u8` 保留位模式（−8→0xF8，−1→0xFF）；**无符号位特殊处理** |
| Δ 聚合 | 5 帧净变化 | **不预 clamp**（窗口净变化上界 ±16 在 i8 内）；Δ≠0 才发；净 0 不发 |
| 接收方 | **先加后 clamp** | `new = clampi(old + Δ, −8, +8)`；单条 Δ 可能超 ±8（正常，非错误） |
| FULL 数据源 | own 表 `log_odds_bytes()` | 连接后 hello 之后发**一次**，无周期重发；width=height=256，origin=(0,0)，res=0.5 |
| DELTA 频率 | 1s/次 | 车端 SLAM 200ms/帧，模 5 聚合；WS 与 gossip 两条链路一致 |
| 255 语义 | **不再是 Unknown 标记** | 0xFF 只是 log-odds −1；所有 `match 255` 逻辑需重写 |
| hello 门控 | 不影响地图消息 | map_full 在 hello 之后到达，Pictor `_identified` 逻辑无需改 |

## 设计决策

| 项 | 决定 |
|------|------|
| 数据语义 | log-odds i8，clamp ±8，阈值 ±6（严格） |
| DELTA 频率 | 车端模 5 聚合 → 1s/次 |
| msgid | 复用 2/3，同批升级无兼容期 |
| 多车/对账 | **不在本任务范围**（车端未实现） |
| get_cell 语义 | 返回 i8 log-odds（已核实无外部调用者，auto_handler/input_handler 走坐标转换不读 cell） |

## 子任务（实施顺序 = 依赖关系）

1. **常量地基**：`protocol_def.gd` 新增 `LOG_ODDS_CLAMP=8` / `LOG_ODDS_THRESHOLD=6`；CELL_* 三态常量保留并标注「仅显示层派生/测试用」 ✅ 2026-08-11
2. **协议层**：`orion_messages.gd` — `Encode_Map_Delta`/`Decode_Map_Delta` 的 `state`→`delta` i8（编码 `& 0xFF`，解码 `b>127 ? b−256 : b`）；FULL data 语义注释 ✅ 2026-08-11
3. **协议层核对**：`message_parser.gd` — 结构不变，注释更新（`voxels: [{gx, gy, delta}]`）；`message_builder.gd` 确认零改动 ✅ 2026-08-11
4. **数据层**：`chunk_data_2d.gd` — 加静态 `to_i8(u)` / `to_u8(i)` 辅助（供全项目共用）+ `to_state(log)` 阈值派生，存储语义注释 ✅ 2026-08-11
5. **数据层核心**：`map_data_2d.gd` — `set_full` 防御 clamp 后初始化整表；`set_delta`/`set_chunk_delta` 改**累加式先加后 clamp**；`_group_by_chunk` 读 `delta`；`get_cell` 返回 i8；DEBUG 统计改派生三态；`cells_changed` 载荷 `state`→`log_odds`；删除无调用者 `_dict_to_packed` ✅ 2026-08-11
6. **渲染层**：`map_container_2d.gd` — `render_chunk`/`update_cells` 由 0/100/255 判断改为阈值 ±6 派生三态 ✅ 2026-08-11
7. **DEBUG 统计**：`renderer_2d.gd` + `websocket_client.gd` 两处 0/100/255 计数改派生三态 ✅ 2026-08-11
8. **测试资源**：改造 `tool/gen_chunk_0_0.gd`（确定性 log-odds 图）→ 重新生成 `Assets/2D/map_chunk_0_0.tres`（值域 {0, 8, 248} 已验证） ✅ 2026-08-11
9. **模拟车端**：`test_ws_server.gd` — `_Send_Map` 发确定性 log-odds FULL；新增 1Hz DELTA 模拟（`_log_map`+`_pending` 5 帧聚合 + Δ≠0 才发 + 覆盖单条超 ±8/+15 场景） ✅ 2026-08-11
10. **单元测试**：`test_orion_protocol.gd` — map_delta 负数位模式断言、map_full log-odds data、新增 3 用例（signed/clamp/threshold） ✅ **13/13 PASS**
11. **端到端测试**：`test_e2e_orion.gd` — log-odds FULL 断言（第一行 8）+ DELTA 到达断言 ✅ **PASS**（delta #1 max|Δ|=15 验证聚合语义）
12. **文档同步**：`docs/orion_protocol.md` §3 频率 / §3.2 data 语义 / §3.3 delta 语义 + 同批发布警告；`docs/websocket_protocol.md` 废弃头注；`docs/multi_robot_map.md` §6.7 标注 ✅ 2026-08-11
13. **验证**：单元 13/13 PASS → e2e PASS → 主场景 headless 90 帧冒烟无脚本错误 ✅；与车端联调 ⬜（待真车/车端 WS 服务可用时执行）

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/websocket/protocol/protocol_def.gd` | 修改 | 新增 log-odds 常量（CLAMP=8 / 阈值=6） |
| `src/websocket/protocol/orion_messages.gd` | 修改 | Delta 有符号编解码（state→delta） |
| `src/websocket/protocol/message_parser.gd` | 修改 | 仅注释更新 |
| `src/websocket/protocol/message_builder.gd` | 不涉及 | 确认零改动 |
| `src/renderer_2d/chunk_data_2d.gd` | 修改 | to_i8/to_u8 辅助 + 语义注释 |
| `src/renderer_2d/map_data_2d.gd` | 修改 | FULL 初始化 / DELTA 累加 clamp / get_cell i8 |
| `src/renderer_2d/map_container_2d.gd` | 修改 | 阈值 ±6 派生三态 |
| `src/renderer_2d/renderer_2d.gd` | 修改 | DEBUG 统计派生三态 |
| `src/websocket/websocket_client.gd` | 修改 | DEBUG 统计派生三态 |
| `src/test/test_ws_server.gd` | 修改 | 模拟车端：log-odds FULL + 1Hz DELTA 聚合 |
| `src/test/test_orion_protocol.gd` | 修改 | 字节级断言 + 新增边界用例 |
| `src/test/test_e2e_orion.gd` | 修改 | e2e 断言改 log-odds 特征 |
| `Assets/2D/map_chunk_0_0.tres` | 重新生成 | 存量含 0/100 非法数据（已核实） |
| `tool/gen_chunk_0_0.gd` | 修改 | 生成 log-odds 语义值 |
| `docs/orion_protocol.md` | 修改 | §3/§3.2/§3.3 同步 |
| `docs/websocket_protocol.md` | 修改（可选） | 废弃头注 |
| `docs/multi_robot_map.md` | 修改（可选） | §6.7 标注已实施 |

## 关键风险（子 agent 调研发现）

1. **0/100/255 残留点**：protocol_def / orion_messages / map_container_2d / map_data_2d / renderer_2d / websocket_client / test_e2e 共 7 处，逐处排查
2. **存量 .tres 含三态数据（0/100）**：必须重新生成，否则 main.tscn 测试 server 与 load_chunk 回退资源显示怪图
3. **先加后 clamp**：车端聚合不预 clamp（净变化可达 ±15/+16），Pictor 若先 clamp 增量再相加会累积偏差
4. **PackedByteArray 有符号解释**：读出 0~255，负 i8 需 `b>127 ? b−256 : b`；写入负数 `& 0xFF`
5. **get_cell 语义变化**：0/100/255 → i8，当前无调用者，需注释声明防未来误用
6. **多车覆盖**：MapData2D 全局单表，多车 FULL 互相覆盖（本任务范围外，联调注意）
7. **同批发布**：无兼容期，合入前确保车端新版已部署

## 验证方法

- 单元：`godot --headless -s src/test/test_orion_protocol.gd`
- 端到端：`godot --headless -s src/test/test_e2e_orion.gd`
- 联调：连车端 WS 服务确认 FULL/DELTA 端到端一致

## 详细实施步骤（2026-08-11 定稿）

### 步骤 1：`protocol_def.gd` — log-odds 常量（地基，下游全部引用）

改前：仅 `CELL_FREE=0 / CELL_OCCUPIED=100 / CELL_UNKNOWN=255`。
改后：在「cell 状态」段后新增：

```gdscript
# ─── log-odds 常量（Task 21：车端 grid.rs 对齐）─────────────────
const LOG_ODDS_CLAMP := 8          # clamp ±8（车端 OCCUPIED_CLAMP/FREE_CLAMP）
const LOG_ODDS_THRESHOLD := 6      # >+6 Occupied / <−6 Free（严格，边界=Unknown）
```

同时把 CELL_* 三态注释改为：`仅用于显示层阈值派生结果与旧测试比对；线上已不再传输三态`。
验证：headless 加载不报错。

### 步骤 2：`chunk_data_2d.gd` — 存储语义 + 有符号转换辅助

改前：`cells[index] = 0 → 可通行, 100 → 不可通行, 255 → 未知`。
改后：

```gdscript
## cells 存 u8（log-odds i8 的位模式）；解释为有符号 i8：>127 减 256
@export var cells: PackedByteArray

static func to_i8(b: int) -> int:      # u8 → i8
	return b if b <= 127 else b - 256

static func to_u8(v: int) -> int:      # i8 → u8（位模式，−8 → 0xF8）
	return v & 0xFF
```

验证：`to_i8(0xF8) == -8`、`to_i8(0xFF) == -1`、`to_u8(-8) == 248`。

### 步骤 3：`orion_messages.gd` — Delta 有符号编解码

**Encode_Map_Delta**（改前：`buf[off + 8] = e.get("state", CELL_FREE)`）：

```gdscript
var delta: int = e.get("delta", 0)
delta = clampi(delta, -127, 127)       # 防御：i8 范围
buf[off + 8] = delta & 0xFF            # i8 → u8 位模式（−8 → 0xF8，−1 → 0xFF）
```

**Decode_Map_Delta**（改前：`"state": payload[off + 8]`）：

```gdscript
var b: int = payload[off + 8]
entries.append({"gx": …, "gy": …, "delta": b if b <= 127 else b - 256})  # u8→i8
```

**Encode/Decode_Map_Full**：逻辑零改动，仅更新注释：`data = width×height 字节的 log-odds i8（−8~+8，u8 位模式直传）`。
验证：后续单测步骤覆盖。

### 步骤 4：`message_parser.gd` — 注释核对（零逻辑改动）

- 更新头注释与 docstring：`MSGID_MAP_DELTA → { voxels: [{gx, gy, delta}] }`（delta 已为 i8 解码值）。
- 核对 `chunk_x = floori(origin_gx / 256)`：origin=(0,0) → chunk(0,0)，单 chunk 覆盖整图，成立。

### 步骤 5：`map_data_2d.gd` — 本地 log-odds 缓冲表（核心）

**set_full**（改前：直接 `chunk.cells = cells`）：

```gdscript
func set_full(chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void:
	var chunk := _get_or_create_chunk(chunk_x, chunk_y)
	# 防御：越界字节 clamp 到 [−8, +8]（车端正常只发 [−8,8]）
	var out := PackedByteArray()
	out.resize(cells.size())
	for i in range(cells.size()):
		var v := ChunkData2D.to_i8(cells[i])
		out[i] = ChunkData2D.to_u8(clampi(v, -ProtocolDef.LOG_ODDS_CLAMP, ProtocolDef.LOG_ODDS_CLAMP))
	chunk.cells = out
	# DEBUG 统计改派生三态（见步骤 7 的 to_state 逻辑）
	EventBus.chunk_updated.emit(chunk_x, chunk_y)
```

**set_delta 链路**：`_group_by_chunk` 读 `v.get("delta", 0)`（不再读 state）；`set_chunk_delta` 改累加式：

```gdscript
func set_chunk_delta(chunk_x: int, chunk_y: int, updates: Array) -> void:
	var chunk := _get_or_create_chunk(chunk_x, chunk_y)
	var changed: Array = []
	for u in updates:
		var lx: int = u.get("lx", 0)
		var ly: int = u.get("ly", 0)
		var delta: int = u.get("delta", 0)
		var idx: int = ly * CHUNK_SIZE + lx
		if idx >= 0 and idx < chunk.cells.size():
			var old := ChunkData2D.to_i8(chunk.cells[idx])
			var new := clampi(old + delta, -ProtocolDef.LOG_ODDS_CLAMP, ProtocolDef.LOG_ODDS_CLAMP)  # 先加后 clamp
			chunk.cells[idx] = ChunkData2D.to_u8(new)
			changed.append({"gx": chunk_x * CHUNK_SIZE + lx, "gy": chunk_y * CHUNK_SIZE + ly, "log_odds": new})
	EventBus.cells_changed.emit(changed)
```

⚠️ `cells_changed` 载荷字段 `state` → `log_odds`（渲染层同步改）。
**get_cell**：`return ChunkData2D.to_i8(chunk.cells[...])`（i8 语义），注释声明「已核实无外部调用者」。

### 步骤 6：`map_container_2d.gd` — 渲染阈值派生

**render_chunk**（改前：`cells[idx]==100→wall / ==0→ground / 255 不渲染`）：

```gdscript
const TH := ProtocolDef.LOG_ODDS_THRESHOLD
# 循环内：
var log := ChunkData2D.to_i8(cells[idx])
if log > TH:            # >+6 Occupied（+6 本身 Unknown）
	wall_cells.append(pos)
elif log < -TH:         # <−6 Free（−6 本身 Unknown）
	ground_cells.append(pos)
# 其余 → Unknown 不渲染
```

**update_cells**（改前：`match state: 0/100/_`）：读 `u.get("log_odds", 0)`，同样阈值派生三态（>+6 设 wall / <−6 设 ground / 其余擦除两层）。

### 步骤 7：DEBUG 统计两处（`renderer_2d.gd` `_on_chunk_updated` + `websocket_client.gd` map_full 分支）

改前：`match cells[i]: 0/100/255 计数`。改后：按阈值派生计数（可在 `ChunkData2D` 加静态 `to_state(log) -> int` 返回 CELL_* 供两处复用）：

```gdscript
# 伪代码（两文件同款）
for i in range(cells.size()):
	var log := ChunkData2D.to_i8(cells[i])
	if log > TH: c_occ += 1
	elif log < -TH: c_free += 1
	else: c_unk += 1
```

### 步骤 8：测试资源 — `tool/gen_chunk_0_0.gd` + `Assets/2D/map_chunk_0_0.tres`

- 改 `gen_chunk_0_0.gd`：`cells[i] = randi() % 2` → 从 `[0, 8, -8, 3, -3]` 抽样（log-odds 语义），注释同步。
- **重新生成 `Assets/2D/map_chunk_0_0.tres`**：存量含 0/100（32834/32702）非法。可用 Godot headless 跑脚本写 `res://Assets/2D/map_chunk_0_0.tres`（脚本内路径改 res://），或复用确定性图（边界 +8 / 中央 16×16 块 −8 / 其余 0，与 test_ws_server 一致）。
- 验证：`.tres` 内 cells 值域 ∈ {0, ±3, ±8}。

### 步骤 9：`test_ws_server.gd` — 模拟车端升级

**FULL**：`_Send_Map()` 改用确定性 log-odds 图（不再直接发 `map_chunk.cells`）：

```gdscript
func _Build_LogOdds_Map() -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(CHUNK_SIZE * CHUNK_SIZE)   # 全 0 = Unknown
	for gx in range(CHUNK_SIZE):            # 上/下边界墙 +8
		cells[gx] = 8
		cells[(CHUNK_SIZE-1) * CHUNK_SIZE + gx] = 8
	for gy in range(CHUNK_SIZE):            # 左/右边界墙 +8
		cells[gy * CHUNK_SIZE] = 8
		cells[gy * CHUNK_SIZE + CHUNK_SIZE - 1] = 8
	for gy in range(120, 136):              # 中央 16×16 空地 −8
		for gx in range(120, 136):
			cells[gy * CHUNK_SIZE + gx] = -8
	return cells
```

**新增 1Hz DELTA 模拟**（对齐车端 robot.rs 语义）：成员 `_log_map: PackedByteArray`（65536，初始 = FULL 数据）、`_pending: Dictionary`（{idx: net_delta}）、`_frame := 0`；每帧做变化（如某区域 +3 / 另一区域 −1，对 `_log_map` saturating 更新并把真实 Δ 累加进 `_pending`，**不预 clamp**）；`_frame % 5 == 0` 时 drain：只发 Δ≠0 的 entries（`Encode_Map_Delta` + `Encode_Frame(MSGID_MAP_DELTA, …, COMPID_VEHICLE, …)`），随后清空 `_pending`。覆盖场景：正 Δ、负 Δ、窗口净变化超 ±8（如 −8 处 5 帧命中 → 单条 +15）。

### 步骤 10：`test_orion_protocol.gd` — 单元测试

- `_test_map_full`：data 改为 log-odds 值（如 `data[i] = [0, 8, -8, 3][i % 4] & 0xFF`），断言 `dec.data` 逐字节一致（去掉 `[4]==100 / [5]==200` 旧断言）。
- `_test_map_delta`：entries 字段 `state` → `delta`；断言负数位模式：`{"delta":-8}` → 线上 `0xF8`、`{"delta":-1}` → `0xFF`、`{"delta":15}`（聚合超 ±8）→ `0x0F` 且 decode 回 15。
- 新增用例：`_test_log_odds_signed`（`ChunkData2D.to_i8/to_u8` 往返 + `0x80→−128`）；`_test_clamp`（`clampi(6+2,-8,8)=8`、`clampi(-8-3,-8,8)=-8`、`clampi(8+1,-8,8)=8`）；`_test_threshold`（6→Unknown、7→Occupied、−6→Unknown、−7→Free、0→Unknown、±8→边界态）。
- 保留：帧/pose/manual/task_set 用例不动。

### 步骤 11：`test_e2e_orion.gd` — 端到端

- map_full 分支（L115-123）：`has_100` 改为「第一行存在 8」（匹配 `_Build_LogOdds_Map` 上边界墙）：

```gdscript
var has_wall_log := false
for i in range(256):
	if r.data.cells[i] == 8: has_wall_log = true; break
_map_ok = has_wall_log
```

- 新增：`_map_delta_count` 计数，断言 ≥1 条 DELTA 到达（e2e 等待时间需覆盖 1Hz 节奏，如 ≥2s）。
- 其余（hello/pose/manual/task_set/cancel 顺序）不动。

### 步骤 12：文档同步

- `docs/orion_protocol.md`：§3 总览表 MAP_DELTA 频率（≤5Hz → **1s 一次（车端 5 帧聚合）**）；§3.2 data 语义（三态 → log-odds i8，own 表数据源，连接时一次）；§3.3 delta 语义（覆盖式 state → 差分 Δ，接收方 `clampi(old+Δ, −8, +8)` 先加后 clamp）；补「同批发布无兼容期」附注。
- （可选）`docs/websocket_protocol.md` 加废弃头注；`docs/multi_robot_map.md` §6.7 标注已实施。

### 步骤 13：验证

1. 单元：`godot --headless -s src/test/test_orion_protocol.gd`（全 PASS，含新增 3 用例）
2. 端到端：`godot --headless -s src/test/test_e2e_orion.gd`（PASS，含 DELTA 到达断言）
3. 主场景冒烟：headless 跑 main.tscn 60 帧无脚本错误（注意 main.tscn 挂 3 个测试 server，多车覆盖仅影响测试展示）
4. 联调（可选）：连车端 WS 服务，确认 FULL 初始化 + DELTA 累加后显示与车端一致

## 多车终端聚合 + 返还全量（阶段 2，2026-08-12 方案定稿）

> 车端对应：`Workspace/Orion/Task/task_13_2_crdt_map.md`（方案 C 终端聚合 + 方案二新车初始化=终端下发全量；车端步骤 4 已实施）。
> 调研：2026-08-12 子 agent 只读梳理（方案定稿，未实施）。

### 设计决策（已与人类确认）

| 项 | 决定 |
|---|---|
| 聚合存储 | **单表直接累加**（不做 per-vehicle 槽）：接入 own FULL → 表 += own（clamp ±8）；平时 Δ → 表 += Δ。流式 Σ ≡ 方案 C 的 Σ 函数 |
| set_full 语义 | 替换 → **累加**（`accumulate_full`）；表初始全 0，首车累加 ≡ 替换，单车零影响 |
| 返还触发 | **收到该车 own FULL 聚合完成后**（非 vehicle_registered，避免首车空表覆盖） |
| 返还内容 | Pictor 当前本地合并表（Σ 各车 own 的流式结果），只发给刚接入的车 |
| 重连/重复接入 | **当新车处理**（2026-08-12 人类决定：整表累加，重复计数不处理） |

### EventBus 信号方案

| 信号 | 签名 | 发送方 → 接收方 | 说明 |
|---|---|---|---|
| `map_full_received`（**改签名**） | `(vehicle_id, chunk_x, chunk_y, cells)` | websocket_client → map_data_2d | 加 vehicle_id 用于路由返还 |
| `map_merged`（**新增**） | `(vehicle_id, chunk_x, chunk_y, cells)` | map_data_2d（聚合完成） → websocket_manager | 载荷 = 合并表快照；驱动返还下发 |
| `cmd_send`（复用） | `(vehicle_id, cmd)` | websocket_manager._on_map_merged → _on_cmd_send | 经 `Build_Cmd(msgid=2)` 编码下发 |

### 接入握手时序

```
车A ──hello──▶ Pictor（_identified=true, vehicle_registered）
车A ──MAP_FULL(ownA)──▶ websocket_client ──map_full_received(A,0,0,ownA)──▶ map_data_2d
    map_data_2d.accumulate_full：表 += ownA（clamp）→ chunk_updated（显示）→ map_merged(A,表)
    websocket_manager._on_map_merged：cmd_send(A, build_map_full(表))
Pictor ──MAP_FULL(mergedA)──▶ 车A（车端 set_log_odds 替换 merged，own 保留）
之后：车A 1s/次 MAP_DELTA ──▶ set_delta 累加；B 接入走同链路，返还 clamp(ownA+ownB)
```

### 涉及文件（12 项）

| 文件 | 操作 | 说明 |
|---|---|---|
| `src/event_bus/event_bus.gd` | 修改 | `map_full_received` 加 vehicle_id；新增 `map_merged`（P0） |
| `src/websocket/websocket_client.gd` | 修改 | emit 带 vehicle_id；**`_connect` 补 outbound_buffer_size=1<<22**（返还 65KB 帧 > 默认 65535，硬缺口）（P0） |
| `src/renderer_2d/map_data_2d.gd` | 修改 | `set_full`→`accumulate_full`（累加 clamp）；聚合后 emit `map_merged`；删 `set_chunk_full`（P0） |
| `src/websocket/protocol/orion_messages.gd` | 修改 | `Build_Cmd` 增 msgid=2 分支（调 `Encode_Map_Full`）（P0） |
| `src/websocket/protocol/message_builder.gd` | 新增 | `build_map_full(cells, origin=0, 256×256, 0.5)`（P0） |
| `src/websocket/websocket_manager.gd` | 修改 | 订阅 `map_merged` → `build_map_full` → `cmd_send`（P1） |
| `src/test/test_ws_server.gd` | 修改 | `_Read_Incoming` 加 MAP_FULL 入站（替换 merged、own 保留）；`inbound_buffer_size=1<<22`；`@export send_delta`/`map_variant`（P1） |
| `src/test/test_orion_protocol.gd` | 修改 | 新增 `_test_accumulate_full` / `_test_build_cmd_map_full` / `_test_return_frame_size`（P1） |
| `src/test/test_e2e_multivehicle.gd` | **新增** | 两车接入握手 e2e（A→ownA→返还；B→ownB→返还 Σ，重叠 clamp 断言）（P1） |
| `docs/orion_protocol.md` | 修改 | §3.2 方向语义（车→终端 own 上报 / 终端→车 下发合并全量）+ 时序红线 + 返还帧大小警告（P2） |
| `docs/multi_robot_map.md` | 修改（可选） | §6.7 标注多车聚合已实施（P2） |
| 本任务文档 | 修改 | 阶段 2 章节（P2） |

**零改动**：`chunk_data_2d.gd`、`map_container_2d.gd`、`renderer_2d.gd`、`renderer_3d.gd`、`test_e2e_orion.gd`。

### 边界与风险（首版接受项标注）

| # | 场景 | 处置 |
|---|---|---|
| 1 | 重连/车重启重复计数（own 双倍） | **当新车处理**（人类决定：重复计数接受，不做去重） |
| 2 | **返还 65KB 帧超默认 buffer** | **必改**：Pictor client outbound + TestWSServer inbound 均 `1<<22` |
| 3 | 多车同时接入 | 单线程同步链逐车处理，无冲突 |
| 4 | Pictor 重启 | 表清空 → 首车从 0 累加，语义正确（保持 save 禁用） |
| 5 | FULL 替换吞在途 Δ | 首版接受（边界 #5） |
| 6 | 存量车 gossip 贡献暂缺 | 首版接受（B 接入后 Δ 流补回） |
| 7 | own FULL 后返还前断链 | manager `_vehicles.has()` 守卫跳过，无害 |
| 8 | 信号签名破坏性变更 | 全项目仅 2 处引用（已核实），同批修改 |

### 实施状态（2026-08-12 全部完成）

1. ✅ EventBus 信号变更（`map_full_received` 加 vehicle_id + 新增 `map_merged`）
2. ✅ `Build_Cmd` msgid=2 + `message_builder.build_map_full`（含元数据硬约束注释）
3. ✅ `map_accumulator.gd` 纯静态类（add_full / apply_delta_bytes，可 -s 单测）
4. ✅ `map_data_2d.accumulate_full`（累加 clamp + emit map_merged；删 set_chunk_full）
5. ✅ `websocket_client`（emit 带 vehicle_id + outbound buffer 1<<22）
6. ✅ `websocket_manager._on_map_merged` 订阅下发（复用 cmd_send 路径，_vehicles 守卫）
7. ✅ `test_ws_server` 升级（入站 MAP_FULL 替换 merged/own 保留 + inbound buffer + send_delta/map_variant + get_merged_cells/get_full_rx_count；顺带修复 review 🟡-1 map_chunk 门控）
8. ✅ 单测 16/16 PASS（新增 build_cmd_map_full / return_frame_size 65568B / map_accumulator）
9. ✅ `test_e2e_multivehicle` 场景式两车 e2e PASS（Phase A merged==ownA；Phase B 重叠 clamp(8+8)=8、A-only/B-only 区分、终端表==返还逐字节一致）
10. ✅ 回归：单车 e2e PASS + 主场景冒烟无脚本错误
11. ⬜ 联调（真车/车端 WS 服务，待可用）

## 遗留事项

- ~~对账（终端聚合 Σ + 整图下发替换）→ 多车阶段再做~~ → **阶段 2 已立项**（方案定稿，待实施）
- ~~多车 per-vehicle 地图表~~ → **已否决**（2026-08-12 人类确认：单表直接累加即可）
- 重连/重复接入 → **当新车处理**（整表累加，重复计数接受）
- 动态障碍不进共享图（另行设计）
