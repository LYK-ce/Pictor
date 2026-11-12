## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## VehicleApi — 车辆状态查询层（task_51 Step 1 §2.3-2）：agent 的「查车」工具
## 纯静态（同 TargetAlloc / MapAccumulator 的风格）：无节点、无 Autoload、不 import 场景，
## 可在 headless 下 `-s` 直测。唯一入参是 `registry`（有 `vehicles: Dictionary` 的对象，
## 生产环境就是 VehicleRegistry，单测可传假注册表）。
##
## 数据来源：VehicleRegistry.vehicles 是**单一数据源**。本层只读、不写、不缓存，
## 每次调用都现算（`pose_age_ms` 依赖调用时刻，缓存必然过期）。
##
## ⚠️ 语义边界（必读，否则会把「正在跟人」当「空闲可派」）：
##   `busy` 直接取 POSE 帧的 `valid`，而车端 `valid = ExecuteState.sub_target.is_some()`。
##   车端 `ExecuteState.sub_target = out.next_cell`，只有 **Goto / Containment**/*出队瞬间*
##   这类走 D\* 的树才写 `next_cell`；`Follow` / `Face` / `Guard` 三类树写的是
##   `target_point` / `face_point`（`MotionOut.target_point`），`next_cell = None` ⇒ 这些车的
##   `valid` **恒 false**、`state` 显示 `"idle"`、`sub_target` 为 null。
##   即：**`state == "idle"` 不等于「空闲可派」**，正在跟人 / 值守的车也是 idle。
##   本层不做任务类型推断（那要改协议，另开 step）；上层要么接受这个误差，
##   要么自己另查任务队列。
##   同理 `sub_gx/sub_gy` 在非 Goto 任务下被车端填 0 —— `sub_target` 只在 `busy == true` 时有意义。
##
## 另两条口径：
##   * `pose_age_ms` 用**本地**接收时刻（`VehicleRegistry.last_pose_ms` = `Time.get_ticks_msec()`）
##     与**本地**当前时刻相减，与车端 `time_boot_ms`（开机毫秒）不同源、不可比；
##     `-1` = 从未收到过 POSE。
##   * 单位换算一律走 CoordUtils（`tile_to_real` = 格中心 = Rust `cell_center`），不在这里写公式。

class_name VehicleApi
extends RefCounted

## 陈旧阈值（毫秒）：车端 POSE 广播周期 100 ms（`pleiades-base/src/Robot/core/robot.rs:243` 的
## `state_notifier`），连续 10 帧没到即视为陈旧。只用于 `Summary.stale`；`Query` 的新鲜度过滤
## 由调用方的 `max_pose_age_ms` 决定，不用这个值。
const STALE_MS := 1000

const STATE_NO_POSE := "no_pose"
const STATE_BUSY := "busy"
const STATE_IDLE := "idle"

## `Query(filter)` 支持的键（都可缺省；**未知键忽略**——模型可能多给字段，不该整条失败）
const FILTER_KEYS := ["vid", "name", "node_type", "busy", "has_pose", "max_pose_age_ms"]


## 查车：返回按 `vid` 字典序排序的**新**数组，每车一条记录（不返回注册表内部 Dictionary）。
## filter 键见 FILTER_KEYS：
##   vid / name / node_type  —— 精确相等
##   busy / has_pose         —— bool 相等
##   max_pose_age_ms         —— int，保留 `0 <= pose_age_ms <= 该值`；**从未收到位姿（-1）一律排除**
## 返回记录键：vid, name, node_type, online, has_pose, pose_age_ms, x, y, z, yaw, vx, vy,
##             rtk_fixed, busy, state, sub_target
static func Query(registry, filter: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vehicles := _vehicles(registry)
	var ids: Array = vehicles.keys()
	ids.sort()
	for vid in ids:
		var rec = vehicles[vid]
		if not (rec is Dictionary):
			continue
		var row := _record(str(vid), rec)
		if _match(row, filter):
			out.append(row)
	return out


## 按车名反查（未找到返回空 `{}`，**不返回 null**，调用方不必判 null）。
## 重名时取 vid 字典序最小的一条（确定行为，不随机）。
static func Get_By_Name(registry, name: String) -> Dictionary:
	var vehicles := _vehicles(registry)
	var ids: Array = vehicles.keys()
	ids.sort()
	var want := str(name)
	for vid in ids:
		var rec = vehicles[vid]
		if not (rec is Dictionary):
			continue
		if str(rec.get("name", "")) != want:
			continue
		return _record(str(vid), rec)
	return {}


## 全局面板：一次拿到「多少在线 / 几车几机 / 忙闲 / 无位姿 / 陈旧」。
## 返回 {online, cars, uavs, idle, busy, no_pose, stale}；语义见各键注释：
##   online  — 出现在注册表里的条目数（断连由 vehicle_unregistered 擦除，故等价"在线"）
##   cars/uavs — node_type == "car" / "uav" 的条数（未知类型两边都不计）
##   idle/busy/no_pose — state 三态各自的条数（**idle 不含 no_pose**）
##   stale   — 收到过位姿且 pose_age_ms > STALE_MS 的条数（no_pose 不计入）
static func Summary(registry) -> Dictionary:
	var sum := {
		"online": 0, "cars": 0, "uavs": 0,
		"idle": 0, "busy": 0, "no_pose": 0, "stale": 0,
	}
	var vehicles := _vehicles(registry)
	for vid in vehicles.keys():
		var rec = vehicles[vid]
		if not (rec is Dictionary):
			continue
		var row := _record(str(vid), rec)
		sum["online"] += 1
		match str(row["node_type"]):
			"car":
				sum["cars"] += 1
			"uav":
				sum["uavs"] += 1
		match str(row["state"]):
			STATE_IDLE:
				sum["idle"] += 1
			STATE_BUSY:
				sum["busy"] += 1
			STATE_NO_POSE:
				sum["no_pose"] += 1
		if int(row["pose_age_ms"]) > STALE_MS:
			sum["stale"] += 1
	return sum


# ─── 内部 ──────────────────────────────────────────────────────

## 取注册表里的 vehicles 字典；传 null / 传错类型 / 没有该属性 → 空字典（不报错）。
static func _vehicles(registry) -> Dictionary:
	if registry == null:
		return {}
	var v = registry.get("vehicles")
	if v is Dictionary:
		return v
	return {}


## 注册表内部记录 → 对外记录（**新建 Dictionary，不改内部那条**）
static func _record(vid: String, rec: Dictionary) -> Dictionary:
	var has_pose := bool(rec.get("has_pose", false))
	var busy := has_pose and bool(rec.get("valid", false))
	var pose_age_ms := -1                    # -1 = 从未收到 POSE（has_pose=false）
	if has_pose:
		pose_age_ms = maxi(0, Time.get_ticks_msec() - int(rec.get("last_pose_ms", 0)))
	# 三态：没位姿 → "no_pose"；valid=true → "busy"；其余 → "idle"。
	# ⚠️ "idle" 里混着**正在 Follow / Face / Guard 的车**（它们的 next_cell=None ⇒ valid 恒 false），
	#    所以 idle **不等于**「空闲可派」——见文件头「语义边界」。
	var state := STATE_NO_POSE
	if has_pose:
		state = STATE_BUSY if busy else STATE_IDLE
	var sub_target = null
	if busy:
		# 格坐标 → 世界米（取格中心）：世界点 64.0 是格 128 的**左下角**，格中心 64.25。
		# 与车端 `cell_center = (g + 0.5) * 0.5` 同口径，故直接复用 CoordUtils。
		var p := CoordUtils.tile_to_real(int(rec.get("sub_gx", 0)), int(rec.get("sub_gy", 0)))
		sub_target = {"x": p.x, "y": p.y}
	return {
		"vid": vid,
		"name": str(rec.get("name", "")),
		"node_type": str(rec.get("node_type", "")),
		"online": true,
		"has_pose": has_pose,
		"pose_age_ms": pose_age_ms,
		"x": float(rec.get("x", 0.0)),
		"y": float(rec.get("y", 0.0)),
		"z": float(rec.get("z", 0.0)),
		"yaw": float(rec.get("yaw", 0.0)),
		"vx": float(rec.get("vx", 0.0)),
		"vy": float(rec.get("vy", 0.0)),
		"rtk_fixed": bool(rec.get("rtk_fixed", false)),
		"busy": busy,
		"state": state,
		"sub_target": sub_target,
	}


## filter 判定（未知键忽略；`max_pose_age_ms` 见 Query 注释）
static func _match(row: Dictionary, filter: Dictionary) -> bool:
	if filter.is_empty():
		return true
	if filter.has("vid") and str(filter["vid"]) != str(row["vid"]):
		return false
	if filter.has("name") and str(filter["name"]) != str(row["name"]):
		return false
	if filter.has("node_type") and str(filter["node_type"]) != str(row["node_type"]):
		return false
	if filter.has("busy") and bool(filter["busy"]) != bool(row["busy"]):
		return false
	if filter.has("has_pose") and bool(filter["has_pose"]) != bool(row["has_pose"]):
		return false
	if filter.has("max_pose_age_ms"):
		var cap := int(filter["max_pose_age_ms"])
		var age := int(row["pose_age_ms"])
		if age < 0 or age > cap:
			return false
	return true
