## Presented by KeJi
## Created Date ： 2026-08-07
## Modified Date ： 2026-11-01
##
## ProtocolDef — Orion 统一协议常量定义
## 规范文档：docs/orion_protocol.md
## 所有协议相关的魔法数字集中管理，避免散落各处。
## task_44 §1.2 #3/#4/#11：msgid 4 改「运动 8B / 事件 3B」，模式切换独立为 msgid 8，
## 手动量级定值 v=0.45 m/s、|omega|=0.5 rad/s（**不做**比例换算）。

class_name ProtocolDef
extends RefCounted


# ─── 过渡期 JSON 消息（WS 链路保留；Orion 协议无此消息）──────

const MSG_HELLO := "hello"


# ─── msgid（ORION_* 消息 ID）────────────────────────────────

const MSGID_POSE := 1
const MSGID_MAP_FULL := 2
const MSGID_MAP_DELTA := 3
const MSGID_MANUAL_CONTROL := 4
const MSGID_TASK_SET := 5
## UAV → 地面站的协助请求（task_41 §5.3）：payload = x f32 BE | y f32 BE（严格 8 B）
## 单向：只有地面站订阅（Kernel 侧 [Network].subscribe_topics），车/机不发也不订阅。
const MSGID_ASSIST_REQUEST := 7
## 模式切换（task_44 §1.2 #4）：payload = mode u8（0 = 手动 / 1 = 自动），严格 1 B。
## **不再**走 msgid 4 的 action 8/9（那两个枚举已删）。
const MSGID_MODE := 8


# ─── ORION_MANUAL_CONTROL 事件 action 枚举（task_44 §1.2 #3：重排为 1..5）─────
## 运动（前进/后退/左转/右转/停车）已不再是 action：改用 8 B 的 (v, omega) 连续量，
## 停车 = 全零运动帧。本枚举只剩**事件类**动作，payload 走 3 B（action u8 + param i16 BE）。

const ACTION_BEEP := 1
const ACTION_START_LIDAR := 2
const ACTION_STOP_LIDAR := 3
const ACTION_TAKEOFF := 4    # 起飞（无人机，param 忽略，固定 1.8m）
const ACTION_LAND := 5       # 降落（无人机，param 忽略）


# ─── ORION_MODE (msgid 8) mode 枚举（task_44 §1.2 #4）──────────

const MODE_MANUAL := 0
const MODE_AUTO := 1


# ─── 手动量级定值（task_44 §1.2 #11 / §1.4）────────────────────
## v = 0.45 m/s、|omega| = 0.5 rad/s；ω > 0 = 左转。执行器内**不做任何比例换算**、
## 不读百分比。`input_handler`（发帧）、`ws_command_server`（`manual` 指令的越界门控）
## 与单测共用这一份，禁止在别处再写一份字面量。
const MANUAL_V_MAX := 0.45
const MANUAL_OMEGA_MAX := 0.5


# ─── ORION_TASK_SET mission type ─────────────────────────────

## 车端 `command_decode` 认的 type：0 = Goto、2 = Follow（task_37 §五.2）、
## 3 = Containment 封控（task_41 §3.2：x/y = 正方形中心，half_side = 半边长 m）。
## TASK_SET 记录**按 type 变长**（0/2 = 9 B、3 = 13 B）。不在 {0,2,3} 的条目由
## `Encode_Task_Set` 报错并**返回空数组（整帧不发）**，不再降级成 Goto；
## 旧值 1（Circle）已随 task_36 §十一 #27 废弃，常量删除、不得复用。
## Containment 只有 sim 机栈真实现；真车 / 真机 / sim 车栈建平凡树（一拍 Success + warn）。
const MISSION_TYPE_GOTO := 0
const MISSION_TYPE_FOLLOW := 2
const MISSION_TYPE_CONTAINMENT := 3

## 字符串/数字 → mission type 整数（"goto"/未知字符串 → 0；"follow" → 2；"containment"/"contain" → 3；
## 数字原样返回 —— 数字的合法性由 `Encode_Task_Set` 门控，本函数不造白名单）
## "circle" 的环形几何已上移到地面站（TargetAlloc.compute_targets 的 shape 参数），不进协议
static func Mission_Type_From(t) -> int:
	if t is String:
		match str(t).strip_edges().to_lower():
			"follow":
				return MISSION_TYPE_FOLLOW
			"containment", "contain":
				return MISSION_TYPE_CONTAINMENT
			_:
				return MISSION_TYPE_GOTO
	return int(t)


# ─── cell 三态（仅显示层阈值派生结果与旧测试比对用）────────────
# Task 21：线上已不再传输三态（MAP_FULL/MAP_DELTA 改传 log-odds i8）

const CELL_FREE := 0
const CELL_OCCUPIED := 100
const CELL_UNKNOWN := 255


# ─── log-odds 常量（Task 21：车端 grid.rs 对齐）─────────────────

const LOG_ODDS_CLAMP := 8          # clamp ±8（车端 OCCUPIED_CLAMP / FREE_CLAMP）
const LOG_ODDS_THRESHOLD := 6      # >+6 Occupied / <−6 Free（严格，恰好 ±6 为 Unknown）


# ─── sysid / compid 约定 ────────────────────────────────────

# v2：终端上行身份 = 空 sysid（sysid_len=0）+ compid=200，不再使用固定 sysid 值
const SYSID_LEN_MAX := 255        # sysid 字节数上限（u8）
const COMPID_VEHICLE := 1
const COMPID_TERMINAL := 200


# ─── 地图常量 ────────────────────────────────────────────────

const MAP_RESOLUTION := 0.5      # 米/cell
const MAP_WIDTH := 256           # cell 数
const MAP_HEIGHT := 256          # cell 数
const CHUNK_SIZE := 256
