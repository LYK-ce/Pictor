# WebSocket 通信协议

> ⚠️ **已废弃（2026-08-11）**：本文件描述的是旧 JSON 文本协议（`hello/pose/map_delta/cmd`）。自 task_20 起 WebSocket 链路已迁移为 **Orion 二进制帧**（以 `docs/orion_protocol.md` 为准）；task_21 起地图消息数据语义为 **log-odds i8**。本文档仅作历史参考，不再维护。

> **代码实现**: 协议定义/构造/解析统一在 `src/websocket/protocol/` 目录。
> - `ProtocolDef` — 所有魔法字符串常量
> - `MessageBuilder` — 下行消息构造（PC → 小车）
> - `MessageParser` — 上行消息解析（小车 → PC）

## 基本信息

| 项目 | 值 |
|------|------|
| 传输协议 | WebSocket |
| 数据格式 | JSON 文本消息 |
| 编码 | UTF-8 |
| 角色 | 小车 = Server，PC = Client |
| 默认端口 | 9001 |

每条消息为单行 JSON，顶层必有 `type` 字段。

## 坐标系

| 项目 | 值 |
|------|------|
| 1 cell | 0.5m × 0.5m |
| Godot 缩放 | 1m = 32px |
| 2D 轴 | `x`（东/右）, `y`（南/下） |
| 3D 轴 | 高度用 `z` |
| 网格坐标 | `gx = floor(x / 0.5)`, `gy = floor(y / 0.5)` |

Chunk 大小：256×256 cell = 128m×128m。

---

## 连接流程

| 阶段 | 触发条件 | 含义 |
|------|---------|------|
| WebSocket 握手完成 | TCP 升级为 WS | 物理通道建立 |
| `hello` 包收到 | 小车发送身份 | **正式建立连接** |

`hello` 之前收到的任何消息将被丢弃。

```
小车 ── TCP 握手 ──→ PC
小车 ── hello ──→ PC          ← 必须第一帧
小车 ── map_full ──→ PC       ← 可选
小车 ── pose ──→ PC
```

---

## 上行：小车 → PC

### hello — 注册身份

```json
{
    "type": "hello",
    "vehicle_id": "car_0",
    "address": "ws://192.168.1.10:9090"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `vehicle_id` | string | 车辆唯一标识 |
| `address` | string | 本连接地址 |

### pose — 车辆位姿

实时发送车辆位置、朝向和速度。

```json
{
    "type": "pose",
    "ts": 1717800000.123,
    "x": 1.5,
    "y": 3.2,
    "z": 0.0,
    "yaw": 0.785,
    "vx": 0.5,
    "vy": 0.0
}
```

| 字段 | 类型 | 单位 | 说明 |
|------|------|------|------|
| `ts` | f64 | 秒 | Unix 时间戳 |
| `x`, `y` | f32 | 米 | 2D 世界坐标 |
| `z` | f32 | 米 | 高度 |
| `yaw` | f32 | 弧度 | 偏航角 |
| `vx`, `vy` | f32 | 米/秒 | 2D 速度分量 |

### map_full — 全量地图（二进制帧）

连接建立后发送完整 Chunk。**使用 WebSocket 二进制帧**，不走 JSON。

```
字节布局:
  [0]      type:    u8 = 0 (map_full)
  [1..4]   chunk_x: int32 (big-endian)
  [5..8]   chunk_y: int32 (big-endian)
  [9..]    cells:   PackedByteArray, 65536 bytes (256×256)

  总大小: 65545 bytes
```

每个 cell: 0=可通行, 1=不可通行, 2=未知，行优先 `index = y * 256 + x`。

### map_delta — 增量地图（文本帧）

仅发送变化的格子，JSON 格式。

```json
{
    "type": "map_delta",
    "voxels": [
        {"gx": 2, "gy": 1, "state": 1},
        {"gx": 3, "gy": 2, "state": 0}
    ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `voxels` | array | 变化的格子列表 |
| `gx`, `gy` | i32 | 网格坐标 |
| `state` | u8 | 0=可通行, 1=不可通行, 2=未知 |

---

## 下行：PC → 小车

下行命令分三层：`mode` 控制模式切换，`manual` 在手动模式下控制，`auto` 在自动模式下下发任务。

### mode — 模式控制

```json
{"cmd": "mode", "action": "switch_to_auto"}
```

| action | 说明 |
|------|------|
| `switch_to_manual` | 切换到手动模式 |
| `switch_to_auto` | 切换到自动模式 |

模式切换时小车自动停车。

### manual — 手动控制命令

```json
{"cmd": "manual", "action": "forward", "speed": 50}
```

| action | speed | 说明 |
|------|------|------|
| `forward` | 0-100 | 前进 |
| `backward` | 0-100 | 后退 |
| `spin_left` | 0-100 | 左旋 |
| `spin_right` | 0-100 | 右旋 |
| `stop` | — | 停车 |
| `beep` | duration (ms) | 蜂鸣 |

仅在 Manual 模式下有效，Auto 模式下忽略。

### auto — 自动任务

```json
{"cmd": "auto", "action": "push", "missions": [
    {"type": "goto", "x": 10.5, "y": 3.2}
]}
```

| action | 说明 |
|------|------|
| `push` | 追加任务到队列 |
| `cancel` | 清空队列并停车 |

| mission type | 字段 | 说明 |
|------|------|------|
| `goto` | `x`, `y` (f32, 米) | 导航到目标点 |

仅在 Auto 模式下有效。

---

## 消息一览

```
上行 (小车 → PC)          下行 (PC → 小车)
─────────────────         ─────────────────
hello                      mode
pose                       manual
map_full                   auto
map_delta
```
