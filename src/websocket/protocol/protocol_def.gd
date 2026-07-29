## Presented by KeJi
## Date: 2026-07-29
##
## ProtocolDef — 协议枚举与常量定义
## 所有协议相关的魔法字符串/数字集中管理，避免散落各处。

class_name ProtocolDef
extends RefCounted


# ─── 上行消息类型 (小车 → PC) ──────────────────────────────

const MSG_HELLO     := "hello"
const MSG_POSE      := "pose"
const MSG_MAP_DELTA := "map_delta"


# ─── 下行命令类型 (PC → 小车) ──────────────────────────────

const CMD_MODE   := "mode"
const CMD_MANUAL := "manual"
const CMD_AUTO   := "auto"


# ─── mode action ───────────────────────────────────────────

const MODE_SWITCH_TO_MANUAL := "switch_to_manual"
const MODE_SWITCH_TO_AUTO   := "switch_to_auto"


# ─── manual action ─────────────────────────────────────────

const MANUAL_FORWARD    := "forward"
const MANUAL_BACKWARD   := "backward"
const MANUAL_SPIN_LEFT  := "spin_left"
const MANUAL_SPIN_RIGHT := "spin_right"
const MANUAL_STOP       := "stop"
const MANUAL_BEEP       := "beep"

const MANUAL_DEFAULT_SPEED := 50


# ─── auto action ───────────────────────────────────────────

const AUTO_PUSH   := "push"
const AUTO_CANCEL := "cancel"


# ─── mission type ──────────────────────────────────────────

const MISSION_GOTO := "goto"


# ─── cell state ────────────────────────────────────────────

const CELL_FREE    := 0  # 可通行
const CELL_WALL    := 1  # 不可通行
const CELL_UNKNOWN := 2  # 未知


# ─── 二进制帧 (map_full) ───────────────────────────────────

const BIN_TYPE_OFFSET   := 0
const BIN_CHUNK_X_OFFSET := 1
const BIN_CHUNK_Y_OFFSET := 5
const BIN_CELLS_OFFSET  := 9
const BIN_CELLS_SIZE    := 65536   # 256 × 256
const BIN_FRAME_SIZE    := 65545   # 1 + 4 + 4 + 65536
const BIN_MAP_FULL_TYPE := 0
