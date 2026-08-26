# Task 25: UAV 接入（POSE 扩展 z + 起飞/降落命令）

> 创建日期：2026-08-26
> 状态：✅ 方案定稿（下发目标 = manual_target，E/Q 键起飞/降落），待实施
> 范围：Pictor 适配 Orion `Universal-Robot` 分支（task_22_4 飞控接入）——① POSE 33→37B 加 `z`；② 新增 `takeoff`/`land` 手动命令（E/Q 键）；③ 速度 param 语义变化（知情项）。
> 依据：`Workspace/Orion/docs/design_doc/terminal_interface_diff.md`

---

## 一、背景

车端从 `Godot-Library` 分支迁到 `Universal-Robot` 分支（含 task_22_4 飞控接入），机器从纯小车扩展为「车 + 无人机」。线上（wire）协议对终端（Pictor）只有 **3 处差异**：

| # | 项 | 类型 | 影响 |
|---|---|---|---|
| 1 | `ORION_POSE`（msgid=1）`PoseData` 增加 `z: f32`，payload **33→37 字节** | 🔴 破坏性 | 旧终端解析会失败/错位 |
| 2 | `ORION_MANUAL_CONTROL`（msgid=4）`action` 新增 `takeoff=10` / `land=11` | 🟢 新增枚举 | 旧终端发 0~9 仍兼容 |
| 3 | `ORION_MANUAL_CONTROL` 的 `param`（速度档位）对 forward/backward/spin 被忽略，速度改由设备层 config 绑定 | 🟡 语义变化 | 不破坏字节布局，但地面站发速度不再生效 |

其余消息（`TASK_SET`、`MAP_FULL`、`MAP_DELTA`）与帧头（`Frame`）两分支完全一致，**无变化**。

---

## 二、改动点 A：POSE 33→37B 加 `z`（🔴 必须改）

### 2.1 字节布局

```
旧版（33B）：time_boot_ms u32 | x f32 | y f32 | vx f32 | vy f32 | yaw f32 | valid u8 | sub_gx i32 | sub_gy i32
新版（37B）：time_boot_ms u32 | x f32 | y f32 | z f32 | vx f32 | vy f32 | yaw f32 | valid u8 | sub_gx i32 | sub_gy i32
```

- `z`（f32，4B）插在 `y` 之后、`vx` 之前（offset 12）。
- 后续字段 `vx/vy/yaw/valid/sub_gx/sub_gy` 偏移全部 **+4**。
- 长度校验：`decode_pose` 校验 ==37（旧 33B 帧会被拒绝）。

字段语义：`z` = 垂直高度（米），车恒 0、机写飞控 EKF。

### 2.2 Pictor 侧改动

当前 `src/websocket/protocol/orion_messages.gd` 的 `Decode_Pose` 硬校验 `payload.size() != 33`，车端一发 37B 帧会直接 `_Fail("pose payload size mismatch")`，导致 `pose_received` 永不触发（Sprite 不渲染、面板不刷新、相机不跟随）。**这是必须先改的。**

| 文件 | 操作 | 说明 |
|---|---|---|
| `src/websocket/protocol/orion_messages.gd` | 改 | `Decode_Pose`：37B 校验 + offset 12 读 `z`，`vx/vy/yaw/valid/sub_gx/sub_gy` 后移 4 字节；`Encode_Pose` 加 `z` 参数保持对称 |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 改 | `_on_pose` 取 `z`，并入 position 字符串显示高度（见 §2.3） |
| `src/test/test_orion_protocol.gd` | 改 | pose 相关用例（build + roundtrip + 越界）按 37B 布局更新 |

下游消费方：`renderer_2d.gd` / `camera_2d.gd` **无需改动**（只用 `x/y/yaw`）；`vehicle_panel_manager.gd` 需加 `z` 显示（见 §2.3）。

### 2.3 定稿：面板显示高度 z

`vehicle_panel_manager.gd` 的 `_on_pose` 当前只显示 `x, y / yaw / vx, vy`。新增显示高度 `z`（**默认 0**，车恒 0、机写飞控 EKF）：把 `z` 并入 position 字符串，如 `"%.1f, %.1f, %.1f" % [x, y, z]`。

---

## 三、改动点 B：takeoff/land 起飞降落（🟢 新增枚举，E/Q 键）

### 3.1 协议语义

- `action=10` = `takeoff`（起飞，**固定 1.8m**，param 忽略）
- `action=11` = `land`（降落，param 忽略）
- 车端映射：`10 → Command::Manual(ManualCmd::Takeoff)`，`11 → Command::Manual(ManualCmd::Land)`。
- 常量：`protocol/messages.rs` `ACTION_TAKEOFF=10` / `ACTION_LAND=11`。

> ⚠️ 语义注意：takeoff/land 走 **`Command::Manual`** 通道（非 Mode 通道），即与 WASD 手动控制同类。

### 3.2 触发方式（用户定稿）

- **E 键** = 发起飞命令（takeoff）
- **Q 键** = 发降落命令（land）
- 按键占用检查：E/Q 当前空闲（已占用：W/A/S/D/Space 手动、Z Circle 待命、Esc 取消）。✅ 无冲突。

### 3.3 下发目标（✅ 定稿：路线 A = manual_target）

takeoff/land 是 Manual 命令，与 WASD 同类 → **发给 `app_state.manual_target`（当前手动模式车辆）**，放 `input_handler.gd` 与 WASD 同层。

> 车端已实现（task_22_4）：takeoff/land 归 `Command::Manual`，**车收到后不响应，仅飞机响应**。终端侧无需做车/机判断，直接对 manual_target 下发即可；即使 manual_target 是车，按 E/Q 也无副作用（车端忽略）。

操作流程：面板勾选目标无人机为 Manual（`manual_target` + 发 `switch_to_manual`）→ 按 **E** 起飞 / **Q** 降落。

### 3.4 涉及文件

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `src/websocket/protocol/protocol_def.gd` | 改 | 加 `ACTION_TAKEOFF := 10` / `ACTION_LAND := 11` |
| 2 | `src/websocket/protocol/message_builder.gd` | 改 | `_ACTION_STR_TO_ENUM` 加 `"takeoff"` / `"land"` 映射（走 `build_manual_action` 同构，不单独加 build 函数） |
| 3 | `src/control/input_handler.gd` | 改 | `_KEY_MAP` 加 `KEY_E: "takeoff"` / `KEY_Q: "land"`（与 WASD 同构，走 `build_manual_action`） |
| 4 | `src/test/test_orion_protocol.gd` | 改 | 新增 takeoff/land 编码 + roundtrip 单测 |

---

## 四、改动点 C：速度 param 语义变化（🟡 知情项，无需改码）

- 帧里 `param`（i16 速度档位）仍编码/解码，但车端 `dispatch` 对 Forward/Backward/SpinLeft/SpinRight 调无参 `move_*()`，**忽略 param**；速度由设备层 config 绑定（车 `chassis.forward_speed`/`turn_speed`，机 `flight_ctrl.vel_fwd`/`yaw_rate_deg`）。
- 含义：地面站按旧协议发 param 不会报错，但速度不再由该字段决定；仅 `beep` 的时长 param 仍生效。
- Pictor 侧处置（✅ 已定）：保留 `MANUAL_DEFAULT_SPEED := 50` 常量，加一行注释说明「车端已忽略速度档位（forward/backward/spin），仅 beep 时长 param 生效」。

---

## 五、待拍板项（与用户讨论）

1. ~~起飞/降落下发目标~~ ✅ **已定**：路线 A（`manual_target`，放 `input_handler.gd`，与 WASD 同层）。（§3.3）
2. ~~面板是否显示高度 `z`~~ ✅ **已定**：显示高度 `z`（默认 0），并入 position 字符串。（§2.3）
3. ~~`MANUAL_DEFAULT_SPEED` 常量处置~~ ✅ **已定**：保留常量 + 加注释说明车端已忽略。（§四）
4. ~~是否需要先切 Manual 再起飞~~ ✅ **已明确**：与 WASD 一致，先面板勾选 Manual（`switch_to_manual`）；车端对 takeoff/land 不响应（仅飞机响应），终端侧无需区分车/机。
