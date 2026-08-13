# Task 22: Group Command 群发任务（Pictor 端同步 Orion task_14）

> 创建日期：2026-08-12
> 状态：✅ 已实施完毕（待人类评审 / 归档）
> 范围：hello peer_id 接入 + TASK_SET 群发编码 + cmd_send 路由重构 + 测试与文档

---

## 背景

- Orion task_14_group_goto 方案定稿：TASK_SET（msgid 5）扩展 members 群发，分布式散布分配在车端执行
- **车端 hello 已实施**（`server.rs` L139-146 已带 `peer_id` hex），Pictor 端未跟进
- ⚠️ 字节格式变更，**Pictor 与车端同批升级，无过渡期**（老 Pictor 发旧帧 → 车端全拒）

## 方案定稿摘要（2026-08-12 讨论收敛）

### ① 语义：无"旧单车任务"，全部统一多车命令

```
单车 Goto   → member_count=1, members=[该车 peer_id]   ← 1 个成员的群发
多车 Goto   → member_count=N, members=[N 车 peer_id]
取消任务    → member_count=0（missions 空）
```

- 编码层无兼容路径，Pictor 端直接全量新格式
- `build_auto_push_goto` / `build_task_set` 调用方无感（members 由发送层填充）

### ② cmd_send 信号签名重构：显式目标数组

```gdscript
# event_bus.gd
signal cmd_send(targets: Array[String], cmd: Dictionary)
```

- **收件人 = 选中的车辆列表**（不传空串、不靠反查）
- 单车也走数组（1 元素），统一一条路径
- **members 填充下沉 WebSocketManager**（发送唯一汇聚点）：

```gdscript
func _on_cmd_send(targets: Array[String], cmd: Dictionary) -> void:
    if cmd.msgid == ProtocolDef.MSGID_TASK_SET and not cmd.has("members"):
        cmd["members"] = targets.map(func(id): return _peer_id_bytes(id))  # 查 vehicle_peer_ids 表
    var frame := OrionMessages.Build_Cmd(cmd)
    for id in targets:
        _vehicles[id].send_binary(frame)
```

- MANUAL_CONTROL / MAP_FULL 等非 TASK_SET 命令：不填 members，按 targets 逐车发（行为不变）

### ③ hello peer_id：不动 vehicle_registered 信号签名

```
车端 hello(含 peer_id) → websocket_client 解析存 _peer_id
→ vehicle_registered(vehicle_id, url)【签名不变，Renderer2D / VehiclePanelManager 零改动】
→ WebSocketManager 从 client 取 _peer_id → 维护内部 _peer_ids 表（与 _vehicles 生命周期同步）
→ 群发时查表填 members；注销时同步删除
```

- **peer_id 表放 WebSocketManager 内部**（唯一消费者就是 manager 填 members，无跨组件共享需求，不上 AppState）
- `test_ws_server.gd` 模拟器 hello 补假 `peer_id`（76-hex 风格）

### ④ TASK_SET 编码新布局（msgid 5）

| 字段 | 类型 | 说明 |
|---|---|---|
| mission_count | u8 | 任务数（0 = 取消全部） |
| member_count | u8 | 成员数（0 = 取消 / 1 = 单车 / >1 = 群发） |
| members[] | len u8 + peer_id 变长 | 群发成员（字节序升序由车端排序，不信任帧序） |
| missions[] | 9B/条（type u8 + x f32 + y f32） | 任务队列 |

- `Encode_Task_Set` 重写：签名加 members 参数（读 `cmd.members`）
- `Decode_Task_Set` 同步重写：越界校验（payload<2 → None；members 越界 → None；missions 严格 9×mission_count）
- `build_auto_cancel`（missions=[]）→ mission_count=0 + member_count=0 → 天然命中取消语义 ✅

### ⑤ LLM 指令链路（2026-08-12 拍板：与右键 Goto 一致，对选中车群发）

- `command_requested` → `build_task_set` → `cmd_send.emit(selected_ids, task_set)`（单条群发帧）
- 与右键 Goto 统一走同一条群发路径，行为一致
- 空任务序列（LLM 返回 []）→ 不下发（现状保留）；未选中车 → 忽略

---

## 实施步骤（按依赖顺序，草案）

### Step 1: hello peer_id 接入
- `websocket_client.gd`：`_on_message` hello 分支解析 `peer_id` → `_peer_id` + getter
- `websocket_manager.gd`：`_peer_ids` 内部表（注册时从 client 取，注销/断开时删）
- `test_ws_server.gd`：`_Send_Hello` 加 `peer_id` 字段（固定假值，与帧头 sysid 一致的模拟）
- 验证：headless 跑 e2e，打印 hello 确认 peer_id 解析

### Step 2: TASK_SET 编解码重写 + 单测
- `orion_messages.gd`：`Encode_Task_Set(missions, members)` / `Decode_Task_Set` 新布局
- 防御：mission_count/member_count ≤ 255、member len ≤ 255、members 越界 → fail
- 单测：单车往返 / 多车往返 / 取消帧（member_count=0 → Set([])）/ 长度越界 → fail
- `test_orion_protocol.gd`：现有 task_set 往返断言同步重写

### Step 3: cmd_send 签名重构
- `event_bus.gd`：`signal cmd_send(targets: Array[String], cmd: Dictionary)`
- 调用点（机械改动）：
  - `auto_handler.gd` ×2 → `emit(selected_ids, cmd)`
  - `input_handler.gd` → `emit([manual_target], cmd)`
  - `vehicle_panel_manager.gd` ×4 → `emit([vehicle_id], cmd)`
  - `websocket_manager.gd` map_full 返还 → `emit([vehicle_id], ...)`
- `websocket_manager.gd`：`_on_cmd_send(targets, cmd)` 新签名 + members 填充逻辑

### Step 4: auto_handler 群发接线
- 右键 Goto：`selected_ids` → 一次 `cmd_send.emit(selected_ids, task_set)`（替代现逐车循环）
- 群发帧 = 单条 TASK_SET（members 全选中车），车端自行散布

### Step 5: LLM 指令链路（定稿：群发）
- `command_requested` → `build_task_set` → `cmd_send.emit(selected_ids, task_set)`（与右键 Goto 同路径）
- 空任务序列 / 未选中车 → 不下发（现状保留）


### Step 6: 测试
- `test_e2e_multivehicle.gd` 扩展：群发 TASK_SET → 模拟器按 members 各自分配
- 模拟器侧需实现：收到群发帧 → 解析 members → 判断自己是否在列 →（散布分配在车端，模拟器可仅验证"收到且成员含自己"）

### Step 7: 文档同步
- `docs/orion_protocol.md` §3.5（payload 布局 + 三分支语义 + 同批升级）、§1.5（hello peer_id 字段表）

---

## 设计决策记录

| 项 | 决定 |
|------|------|
| 单车任务编码 | ✅ 统一多车格式，member_count=1（无旧路径） |
| cmd_send 目标 | ✅ 显式 `targets: Array[String]`（选中车辆列表） |
| members 填充 | ✅ WebSocketManager 查 `vehicle_peer_ids` 表自动填 |
| hello peer_id 传递 | ✅ 不动 `vehicle_registered` 签名，client→manager 内部 `_peer_ids` 表 |
| Renderer2D / VehiclePanelManager | ✅ 零改动（不展示 peer_id） |
| 取消任务 | ✅ `build_auto_cancel` 天然兼容（member_count=0） |
| LLM 指令链路 | ✅ 对选中车群发（与右键 Goto 一致，2026-08-12 拍板） |

## 待办

- [x] LLM 链路拍板（Step 5）：✅ 对选中车群发
- [x] 实施顺序确认（hello → 编码 → 路由 → 接线 → 测试 → 文档）
- [x] 写入 workbook（wb_22_group_command.md）
- [x] Step 1: hello peer_id 接入 ✅
- [x] Step 2: TASK_SET 编解码新布局 + 单测 ✅（16/16 PASS）
- [x] Step 3: cmd_send 签名重构 ✅
- [x] Step 4/5: auto_handler 右键 Goto + LLM 群发 ✅
- [x] Step 6: 测试 ✅（协议单测 + e2e 群发/单车 PASS）
- [x] Step 7: 文档同步 ✅（docs/orion_protocol.md §1.5/§3.5）

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/event_bus/event_bus.gd` | 改 | cmd_send 签名重构 |
| `src/websocket/websocket_client.gd` | 改 | hello peer_id 解析 |
| `src/websocket/websocket_manager.gd` | 改 | members 填充 + `_peer_ids` 表维护 + 路由 |
| `src/websocket/protocol/orion_messages.gd` | 改 | Encode/Decode_Task_Set 新布局 |
| `src/control/auto_handler.gd` | 改 | 右键 Goto 群发接线 |
| `src/control/input_handler.gd` | 改 | emit 签名适配 |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 改 | emit 签名适配 |
| `src/test/test_ws_server.gd` | 改 | hello 补 peer_id + 群发接收 |
| `src/test/test_orion_protocol.gd` | 改 | 往返断言重写 |
| `src/test/test_e2e_multivehicle.gd` | 改 | 群发 e2e |
| `docs/orion_protocol.md` | 改 | §3.5 / §1.5 同步 |

## 依赖

- Orion task_14（车端已实施 hello peer_id，TASK_SET 车端编解码待车端实施）
- 同批上线：Pictor 发新帧 ↔ 车端收新帧，无过渡期
