## Presented by KeJi
## Created Date ： 2026-09-01
## Modified Date ： 2026-11-12
##
## VehicleRegistry — 车辆注册表（单一数据源）
## 订阅 EventBus 车辆信号，维护 {vehicle_id → 15 键记录}，供 LLM 编排 / VehicleApi 读取上下文。

class_name VehicleRegistry
extends Node

## {vehicle_id → 15 键记录}：name, node_type, x, y, z, yaw, vx, vy, valid, sub_gx, sub_gy,
## rtk_fixed, time_boot_ms, has_pose, last_pose_ms
## 模板**只有一份**（`_on_vehicle_registered`，与 `add_mock_vehicle` 同键集）：POSE 帧里已带的字段
## 一个都不许再丢（task_51 Step 1）。缺键时 `VehicleApi._record` 会退化成默认值，不等于对。
var vehicles: Dictionary = {}

## 编队 id 字符集/长度上限（唯一真源，WS 与 Coop 都问这里；task_50 §7.2）
const FORMATION_ID_MAX_LEN := 32

## vid → formation_id（不存在 = 无编队）。**独立于 vehicles**：`_on_vehicle_unregistered`
## 只擦 vehicles，本字典按 vid 保留 ⇒ 重连后按原编队恢复（task_50 §7.6 F4）。
var formations: Dictionary = {}


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	EventBus.peer_info_updated.connect(_on_peer_info_updated)
	EventBus.pose_received.connect(_on_pose)

	


func _on_vehicle_registered(vehicle_id: String) -> void:
	# 编队按 vid 恢复：`formations` 独立于 `vehicles`，这里**不需要**额外广播（task_50 §7.2）。
	if vehicles.has(vehicle_id):
		return
	vehicles[vehicle_id] = {
		"name": "", "node_type": "",
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "vx": 0.0, "vy": 0.0,
		"valid": false, "sub_gx": 0, "sub_gy": 0, "rtk_fixed": false,
		"time_boot_ms": 0,
		"has_pose": false,
		"last_pose_ms": -1,
	}


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	# **只擦 vehicles，不擦 formations**（断线重连保留编队；task_50 §7.6 F4）。
	vehicles.erase(vehicle_id)


func _on_peer_info_updated(vehicle_id: String, peer_name: String, node_type: String) -> void:
	if not vehicles.has(vehicle_id):
		return
	if not peer_name.is_empty():
		vehicles[vehicle_id]["name"] = peer_name
	if not node_type.is_empty():
		vehicles[vehicle_id]["node_type"] = node_type


## ORION_POSE（38 B）落库：除了 x/y/yaw，把 z / vx / vy / valid / sub_gx / sub_gy / rtk_fixed /
## time_boot_ms 一起存下，并置 `has_pose = true`、`last_pose_ms = Time.get_ticks_msec()`
## （本地单调接收时刻，供 VehicleApi 算新鲜度；车端 time_boot_ms 是开机毫秒，不可比）。
## ⚠️ `valid` = 车端「有子目标」标志（`valid = ExecuteState.sub_target.is_some()`）：Follow / Face /
##    Guard 的车 `next_cell = None` ⇒ `valid` 恒 false，**不代表空闲可派**（详见 VehicleApi 头注释）。
func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	if not vehicles.has(vehicle_id):
		return
	var rec: Dictionary = vehicles[vehicle_id]
	rec["x"] = float(pose.get("x", 0.0))
	rec["y"] = float(pose.get("y", 0.0))
	rec["z"] = float(pose.get("z", 0.0))
	rec["yaw"] = float(pose.get("yaw", 0.0))
	rec["vx"] = float(pose.get("vx", 0.0))
	rec["vy"] = float(pose.get("vy", 0.0))
	rec["valid"] = bool(pose.get("valid", false))
	rec["sub_gx"] = int(pose.get("sub_gx", 0))
	rec["sub_gy"] = int(pose.get("sub_gy", 0))
	rec["rtk_fixed"] = bool(pose.get("rtk_fixed", false))
	rec["time_boot_ms"] = int(pose.get("time_boot_ms", 0))
	rec["has_pose"] = true
	rec["last_pose_ms"] = Time.get_ticks_msec()


## 按车名反查 vehicle_id（未找到返回 ""）
func get_id_by_name(vehicle_name: String) -> String:
	for id: String in vehicles:
		if str(vehicles[id].get("name", "")) == vehicle_name:
			return id
	return ""


# ─── 编队（task_50 Step 6 §7.2）：唯一的编队数据源 ──────────────────────
# 口径：`formation_id` strip_edges() 后非空、长度 ≤ FORMATION_ID_MAX_LEN、字符集 [a-z0-9_-]
# （**不折大小写**；非法由调用方拒绝，Join_Formation 也自己兜一层）。一个 vid 只属一个编队。

## 归一化：只去首尾空白（不折大小写）。
func Normalize_Formation_Id(raw: String) -> String:
	return raw.strip_edges()


## 合法 formation id：归一后非空、长度 ≤ 32、每个码位 ∈ [a-z0-9_-]。
func Is_Valid_Formation_Id(fid: String) -> bool:
	var text := Normalize_Formation_Id(fid)
	if text.is_empty() or text.length() > FORMATION_ID_MAX_LEN:
		return false
	for i in range(text.length()):
		var c := text.unicode_at(i)
		var ok := (c >= 97 and c <= 122) \
				or (c >= 48 and c <= 57) \
				or c == 95 or c == 45
		if not ok:
			return false
	return true


## 加入编队：vid 空 → false；fid 非法 → false 且**不改**；已在该编队 → true（幂等）。
## 已在别的编队 → 覆盖（一个 vid 只属一个编队）。**不要求** vid 已注册（formations 独立于 vehicles）。
func Join_Formation(vehicle_id: String, formation_id: String) -> bool:
	if vehicle_id.strip_edges().is_empty():
		return false
	var fid := Normalize_Formation_Id(formation_id)
	if not Is_Valid_Formation_Id(fid):
		return false
	if str(formations.get(vehicle_id, "")) == fid:
		return true
	formations[vehicle_id] = fid
	return true


## 离开当前编队：任何情况下都 true（幂等），只有 vid 空 → false（防御）。
func Leave_Formation(vehicle_id: String) -> bool:
	if vehicle_id.strip_edges().is_empty():
		return false
	formations.erase(vehicle_id)
	return true


## 当前编队 id；未注册 / 无编队 → ""。
func Get_Formation(vehicle_id: String) -> String:
	return str(formations.get(vehicle_id, ""))


## 某编队的成员 vid（**排序**，确定性，供断言与环点计算）；fid 空 → []。
func Get_Formation_Members(formation_id: String) -> Array[String]:
	var out: Array[String] = []
	var fid := Normalize_Formation_Id(formation_id)
	if fid.is_empty():
		return out
	for vid in formations:
		if str(formations[vid]) == fid:
			out.append(str(vid))
	out.sort()
	return out


## 全编队快照 `{fid → Array[String] 成员}`；fid 键按字典序插入（JSON 输出稳定）。
func Get_Formation_Table() -> Dictionary:
	var out := {}
	var fids: Array = []
	for vid in formations:
		var fid := str(formations[vid])
		if not fids.has(fid):
			fids.append(fid)
	fids.sort()
	for fid: String in fids:
		out[fid] = Get_Formation_Members(fid)
	return out



## mock 车辆接口（测试用）：手动塞一辆假车进注册表，供 STT/LLM 无真车联调。
## 注意：不在 _ready 里调用，需要时由外部（测试脚本/调试）手动调用。
func add_mock_vehicle(vehicle_id: String, vehicle_name: String) -> void:
	vehicles[vehicle_id] = {
		"name": vehicle_name, "node_type": "",
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "vx": 0.0, "vy": 0.0,
		"valid": false, "sub_gx": 0, "sub_gy": 0, "rtk_fixed": false,
		"time_boot_ms": 0,
		"has_pose": false,
		"last_pose_ms": -1,
	}
