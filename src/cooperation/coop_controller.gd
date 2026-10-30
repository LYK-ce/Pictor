## Presented by KeJi
## Created Date ： 2026-10-30
## Modified Date ： 2026-10-30
##
## CoopController — 地面站协同控制（task_41 §二.10 / §5.5.11）
##
## 链路：UAV 树 InsideSquare → gossipsub `pleiades/robot/assist_request`（msgid 7）
##       → kernel robot_frame → MessageParser → kernel_bridge → EventBus.assist_request_received
##       → 本模块：取在线 UGV → N 个等角点（3 m 环）→ **最近一对一**分配 → 逐车一帧 Goto。
##
## 口径（不可自行改）：环半径 3 m；角度 θ_i = 2π·i/N（offset = 0）；N ≤ 6 全排列暴力取总距离
##   最小，N > 6 贪心；**每次给每辆车都发**（TASK_SET 整体替换，接受 reset 顿挫，不额外限流）。
## 坐标系：世界坐标（x 东 / y 南，单位米），直接在地面平面用 cos/sin 布点（与协议 §5 一致）。

class_name CoopController
extends Node

## 环半径（米）：人四周 3 m（task_41 §二.10）
const RING_RADIUS_M := 3.0
## 点位起始相位（弧度）：0 → N=4 时点落在 0°/90°/180°/270°（正好覆盖四象限，Step 4 Q4）
const RING_OFFSET_RAD := 0.0
## 暴力枚举上限：N ≤ 6（最多 720 个排列）；更大走贪心
const BRUTE_FORCE_MAX_N := 6

## VehicleRegistry 节点（main.tscn 里是同一层的兄弟节点）
## 不声明为 Node：`vehicles` 是脚本变量，静态类型 Node 上取不到（GDScript 会当解析错误）
@export var registry_path: NodePath = ^"../VehicleRegistry"

var _registry = null
## EventBus（Autoload）：用 `get_node_or_null` 动态取，**不写全局标识符**
## 原因：`godot --headless -s <脚本>` 单测模式下 autoload 名不进编译期作用域
## （全局标识符会报 `Identifier not found: EventBus`）；生产运行行为不变。
var _bus = null


func _ready() -> void:
	_registry = get_node_or_null(registry_path)
	if _registry == null:
		printerr("[Coop] 未找到 VehicleRegistry（path=", registry_path, "）→ 协同控制不可用")
	_bus = get_node_or_null("/root/EventBus")
	if _bus == null:
		printerr("[Coop] 未找到 EventBus（/root/EventBus）→ 协同控制不可用")
	else:
		_bus.assist_request_received.connect(_on_assist_request)


# ─── 纯函数（单测主战场：不碰场景树、不碰信号、不碰时钟）────────────

## N 个等角点：`p_i = center + R·(cos θ_i, sin θ_i)`，`θ_i = TAU·i/N + offset`
static func ring_points(center: Vector2, n: int, radius := RING_RADIUS_M,
		offset := RING_OFFSET_RAD) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if n <= 0:
		return out
	for i in range(n):
		var theta := TAU * float(i) / float(n) + offset
		out.append(center + Vector2(cos(theta), sin(theta)) * radius)
	return out


## 最近一对一分配：返回 `{car_id: point_index}`（两两不同）
## - `N <= BRUTE_FORCE_MAX_N`：**全排列**暴力取总距离最小；代价相同取字典序最小的排列（确定性）
## - `N > BRUTE_FORCE_MAX_N`：距离升序贪心（同距按 车下标、点下标 升序），车/点各只用一次
## - 车数 ≠ 点数 / 车数为 0 → `printerr` + `{}`（调用方据此不发帧）
static func assign_one_to_one(car_ids: Array[String], positions: Dictionary,
		points: Array[Vector2]) -> Dictionary:
	var n := car_ids.size()
	var out := {}
	if n == 0 or points.size() != n:
		printerr("[Coop] assign 参数不匹配：车=%d 点=%d" % [n, points.size()])
		return out
	var ids: Array[String] = car_ids.duplicate()
	ids.sort()                                  # 车序稳定（VehicleRegistry 的字典序不可依赖）
	var cost: Array = []                        # cost[i][j] = 第 i 车到第 j 点（米）
	for i in range(n):
		var p: Vector2 = positions.get(ids[i], Vector2.ZERO)
		var row: Array = []
		for j in range(n):
			row.append(p.distance_to(points[j]))
		cost.append(row)
	if n <= BRUTE_FORCE_MAX_N:
		var perm := _best_permutation(cost, n)
		for i in range(n):
			out[ids[i]] = int(perm[i])
		return out
	var pairs: Array = []
	for i in range(n):
		for j in range(n):
			pairs.append([float(cost[i][j]), i, j])
	pairs.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	var used_car := {}
	var used_pt := {}
	for pr in pairs:
		var ci: int = int(pr[1])
		var pj: int = int(pr[2])
		if used_car.has(ci) or used_pt.has(pj):
			continue
		used_car[ci] = true
		used_pt[pj] = true
		out[ids[ci]] = pj
	return out


## 全排列暴力：`perm[i]` = 第 i 车分到的点下标（cost 最小；同代价保留字典序最小）
static func _best_permutation(cost: Array, n: int) -> Array:
	var perm: Array = []
	for j in range(n):
		perm.append(j)
	var best: Array = perm.duplicate()
	var best_cost := _total_cost(cost, perm, n)
	while _next_permutation(perm):
		var c := _total_cost(cost, perm, n)
		if c < best_cost:
			best_cost = c
			best = perm.duplicate()
	return best


static func _total_cost(cost: Array, perm: Array, n: int) -> float:
	var s := 0.0
	for i in range(n):
		s += float(cost[i][int(perm[i])])
	return s


## 标准 next_permutation（原地；false = 已到最后一个排列）
static func _next_permutation(a: Array) -> bool:
	var i := a.size() - 2
	while i >= 0 and int(a[i]) >= int(a[i + 1]):
		i -= 1
	if i < 0:
		return false
	var j := a.size() - 1
	while int(a[j]) <= int(a[i]):
		j -= 1
	var t = a[i]
	a[i] = a[j]
	a[j] = t
	var lo := i + 1
	var hi := a.size() - 1
	while lo < hi:
		var t2 = a[lo]
		a[lo] = a[hi]
		a[hi] = t2
		lo += 1
		hi -= 1
	return true


# ─── 在线车 / 事件入口 ────────────────────────────────────────

## 在线 UGV：`node_type == "car"` 且有位姿（(0,0) 视为还没收到首帧 POSE，与 TargetAlloc 同口径）
## 返回 `{vehicle_id: Vector2(x, y)}`
func _online_cars() -> Dictionary:
	var out := {}
	if _registry == null or not ("vehicles" in _registry):
		return out
	var vehicles: Dictionary = _registry.vehicles
	for id in vehicles:
		var v = vehicles[id]
		if not (v is Dictionary):
			continue
		if str(v.get("node_type", "")) != "car":
			continue
		var px := float(v.get("x", 0.0))
		var py := float(v.get("y", 0.0))
		if absf(px) < TargetAlloc.POS_EPS and absf(py) < TargetAlloc.POS_EPS:
			continue
		out[str(id)] = Vector2(px, py)
	return out


func _on_assist_request(requester_id: String, x: float, y: float) -> void:
	var center := Vector2(x, y)
	if _bus == null:
		printerr("[Coop] EventBus 未就绪，丢弃派发（requester=%s 目标=(%.2f,%.2f)）" % [requester_id, x, y])
		return
	var cars := _online_cars()
	if cars.is_empty():
		print("[Coop] 协助请求 requester=%s 目标=(%.2f,%.2f) 无在线车 → 忽略" % [requester_id, x, y])
		return
	var ids: Array[String] = []
	for id in cars:
		ids.append(str(id))
	ids.sort()
	var points := ring_points(center, ids.size(), RING_RADIUS_M, RING_OFFSET_RAD)
	var assign := assign_one_to_one(ids, cars, points)
	var parts: Array = []
	for id in ids:
		if not assign.has(id):
			continue
		var idx: int = int(assign[id])
		var p: Vector2 = points[idx]
		parts.append("%s→#%d(%.2f,%.2f)" % [id, idx, p.x, p.y])
	print("[Coop] 协助请求 requester=%s 目标=(%.2f,%.2f) 车数=%d 半径=%.1fm 分配=%s"
			% [requester_id, x, y, ids.size(), RING_RADIUS_M, " ".join(parts)])
	for id in ids:
		if not assign.has(id):
			continue
		var idx2: int = int(assign[id])
		var p2: Vector2 = points[idx2]
		print("[Coop] 指派 车=%s 点#%d 目标=(%.2f,%.2f) 当前距=%.2f m"
				% [id, idx2, p2.x, p2.y, (cars[id] as Vector2).distance_to(p2)])
		# **一帧一车**（task_36 §十一 #27 / §5.5.11）
		_bus.cmd_send.emit([id] as Array[String], MessageBuilder.build_auto_push_goto(p2.x, p2.y))
