## Presented by KeJi
## Date ： 2026-08-07
##
## ProtocolDef — Orion 统一协议常量定义
## 规范文档：docs/orion_protocol.md
## 所有协议相关的魔法数字集中管理，避免散落各处。

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


# ─── ORION_MANUAL_CONTROL action 枚举 ────────────────────────

const ACTION_FORWARD := 0
const ACTION_BACKWARD := 1
const ACTION_SPIN_LEFT := 2
const ACTION_SPIN_RIGHT := 3
const ACTION_STOP := 4
const ACTION_BEEP := 5
const ACTION_START_LIDAR := 6
const ACTION_STOP_LIDAR := 7
const ACTION_SWITCH_TO_MANUAL := 8
const ACTION_SWITCH_TO_AUTO := 9

const MANUAL_DEFAULT_SPEED := 50


# ─── ORION_TASK_SET mission type ─────────────────────────────

const MISSION_TYPE_GOTO := 0


# ─── cell 状态（内部存储与线上编码统一，零映射直传）────────────

const CELL_FREE := 0
const CELL_OCCUPIED := 100
const CELL_UNKNOWN := 255


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
