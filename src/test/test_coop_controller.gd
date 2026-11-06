extends SceneTree

## Presented by KeJi
## Created Date ： 2026-10-30
## Modified Date ： 2026-11-05
##
## CoopController 纯函数单测（headless，task_41 §5.5.11 / task_43 §七）
## 用法: godot --headless --path <项目> -s <本脚本路径>
## 覆盖：3 m 环 N 点等角 / N=1;2;8 边界 / N=4 四轴覆盖 / 3 点环（N=3，θ=2π·i/3）/
##       排除请求者（请求者不进 targets）/
##       两车与四车最近一对一（无重复）/ N! 最优性（2 车 + 3 车）/ N>6 贪心 / 参数不匹配
##       / 派车帧成对两条（Goto + Face，口径 #4）
##
## 用 preload 而不是全局类名：新 `class_name` 未进 `.godot/global_script_class_cache.cfg` 时
## 也能跑（headless 免 import）。

const Coop := preload("res://src/cooperation/coop_controller.gd")

const EPS := 1e-4

## 真机形态的 sysid（= 注册表键 = assist 帧的 sysid hex；格式取自 task_41 实跑日志）
const HEX_PREFIX := "002408011220"


## 假注册表（只提供 `vehicles` 字典；`-s` 模式没有真 VehicleRegistry 节点）
class FakeRegistry extends RefCounted:
	var vehicles: Dictionary = {}


## 假 EventBus（只提供 `cmd_send` 信号；`-s` 模式没有 autoload）
class FakeBus extends RefCounted:
	signal cmd_send(targets: Array, cmd: Dictionary)


func _init() -> void:
	var ok := true
	ok = ok and _test_ring_points_4()
	ok = ok and _test_ring_points_edges()
	ok = ok and _test_ring_points_3()
	ok = ok and _test_assist_excludes_requester()
	ok = ok and _test_ring_points_cover_axes()
	ok = ok and _test_assign_two_cars()
	ok = ok and _test_assign_four_no_duplicate()
	ok = ok and _test_assign_bruteforce_optimal()
	ok = ok and _test_assign_greedy_large()
	ok = ok and _test_assign_size_mismatch()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


## 浮点比较（Vector2 没有带容差的相等，自己写；**不用** Dictionary/Array 的 ==）
func _approx(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= EPS and absf(a.y - b.y) <= EPS


## ① N=4：4 点、都在 3 m 环上、坐标就是 (67,64)/(64,67)/(60,64)/(64,61)
func _test_ring_points_4() -> bool:
	if not (Coop.RING_RADIUS_M == 3.0):
		print("FAIL RING_RADIUS_M != 3.0: ", Coop.RING_RADIUS_M); return false
	var center := Vector2(64.0, 64.0)
	var pts := Coop.ring_points(center, 4)
	if pts.size() != 4:
		print("FAIL ring_points(4) size: ", pts.size()); return false
	var expect: Array[Vector2] = [
		Vector2(67.0, 64.0), Vector2(64.0, 67.0), Vector2(61.0, 64.0), Vector2(64.0, 61.0),
	]
	for i in range(4):
		if absf(pts[i].distance_to(center) - 3.0) > EPS:
			print("FAIL ring radius i=%d: %f" % [i, pts[i].distance_to(center)]); return false
		if not _approx(pts[i], expect[i]):
			print("FAIL ring point i=%d: %s expect %s" % [i, pts[i], expect[i]]); return false
	print("PASS ring_points_4"); return true


## ② 边界：N=0 空 / N=1 一个点 = center+(3,0) / N=2 相距 6 m / N=8 半径全 3 m 且无重复
func _test_ring_points_edges() -> bool:
	var center := Vector2(64.0, 64.0)
	if not Coop.ring_points(center, 0).is_empty():
		print("FAIL ring_points(0) not empty"); return false
	var one := Coop.ring_points(center, 1)
	if one.size() != 1 or not _approx(one[0], Vector2(67.0, 64.0)):
		print("FAIL ring_points(1): ", one); return false
	var two := Coop.ring_points(center, 2)
	if two.size() != 2 or absf(two[0].distance_to(two[1]) - 6.0) > EPS:
		print("FAIL ring_points(2) diameter: ", two); return false
	var eight := Coop.ring_points(center, 8)
	if eight.size() != 8:
		print("FAIL ring_points(8) size: ", eight.size()); return false
	for i in range(8):
		if absf(eight[i].distance_to(center) - 3.0) > EPS:
			print("FAIL ring_points(8) radius i=%d" % i); return false
		for j in range(i + 1, 8):
			if _approx(eight[i], eight[j]):
				print("FAIL ring_points(8) duplicate %d/%d" % [i, j]); return false
	print("PASS ring_points_edges"); return true


## ③ N=4 时 offset=0 → 四点分别落在 +x / +y / −x / −y 四条轴上（各一次）
## （Step 4 Q4 的前置证据：四个方向都被占住，人两侧都有人）
## task_43 §七：生产路径现在是 N=3（4 车 − 请求者），N=4 只剩纯函数覆盖
func _test_ring_points_cover_axes() -> bool:
	var center := Vector2(64.0, 64.0)
	var pts := Coop.ring_points(center, 4)
	var seen := {}
	for i in range(4):
		var d := pts[i] - center
		var sx := 0
		if absf(d.x) > 1e-3:
			sx = 1 if d.x > 0.0 else -1
		var sy := 0
		if absf(d.y) > 1e-3:
			sy = 1 if d.y > 0.0 else -1
		var key := "%d/%d" % [sx, sy]
		if seen.has(key):
			print("FAIL ring_points(4) direction %s repeated" % key); return false
		seen[key] = true
	if seen.size() != 4:
		print("FAIL ring_points(4) directions = ", seen.keys()); return false
	for k in ["1/0", "-1/0", "0/1", "0/-1"]:
		if not seen.has(k):
			print("FAIL ring_points(4) missing %s: %s" % [k, seen.keys()]); return false
	print("PASS ring_points_cover_axes"); return true


## ④ 两车：a 在 +x、b 在 −x，点 (3,0)/(−3,0) → 各就最近（总 14 m；交换是 26 m）
func _test_assign_two_cars() -> bool:
	var ids: Array[String] = ["a", "b"]
	var pos := {"a": Vector2(10.0, 0.0), "b": Vector2(-10.0, 0.0)}
	var points: Array[Vector2] = [Vector2(3.0, 0.0), Vector2(-3.0, 0.0)]
	var assign := Coop.assign_one_to_one(ids, pos, points)
	if assign.size() != 2:
		print("FAIL assign(2) size: ", assign); return false
	if int(assign["a"]) != 0:
		print("FAIL assign a -> ", assign["a"]); return false
	if int(assign["b"]) != 1:
		print("FAIL assign b -> ", assign["b"]); return false
	print("PASS assign_two_cars"); return true


## ⑤ 四车：4 个值两两不同、且正好用上 0..3（最近一对一不漏不重）
func _test_assign_four_no_duplicate() -> bool:
	var ids: Array[String] = ["a", "b", "c", "d"]
	var pos := {
		"a": Vector2(0.0, 0.0), "b": Vector2(10.0, 0.0),
		"c": Vector2(0.0, 10.0), "d": Vector2(10.0, 10.0),
	}
	var points := Coop.ring_points(Vector2(5.0, 5.0), 4)
	var assign := Coop.assign_one_to_one(ids, pos, points)
	if assign.size() != 4:
		print("FAIL assign(4) size: ", assign); return false
	var got: Array = []
	for id in ids:
		got.append(int(assign[id]))
	got.sort()
	if got != [0, 1, 2, 3]:
		print("FAIL assign(4) points used: ", got); return false
	print("PASS assign_four_no_duplicate"); return true


## ⑥ N! 最优性：构造「恒等分配很差、换一下最优」的两个例子
func _test_assign_bruteforce_optimal() -> bool:
	if not (Coop.BRUTE_FORCE_MAX_N == 6):
		print("FAIL BRUTE_FORCE_MAX_N != 6: ", Coop.BRUTE_FORCE_MAX_N); return false
	# 2 车：恒等 200 m，最优 0 m
	var ids2: Array[String] = ["a", "b"]
	var pos2 := {"a": Vector2(100.0, 0.0), "b": Vector2(0.0, 0.0)}
	var pts2: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(100.0, 0.0)]
	var a2 := Coop.assign_one_to_one(ids2, pos2, pts2)
	if int(a2["a"]) != 1 or int(a2["b"]) != 0:
		print("FAIL assign optimal 2-car: ", a2); return false
	# 3 车：不劣于恒等分配
	var ids3: Array[String] = ["a", "b", "c"]
	var pos3 := {
		"a": Vector2(3.0, 0.1), "b": Vector2(-1.5, 2.6), "c": Vector2(-20.0, -20.0),
	}
	var pts3 := Coop.ring_points(Vector2(0.0, 0.0), 3)
	var a3 := Coop.assign_one_to_one(ids3, pos3, pts3)
	if a3.size() != 3:
		print("FAIL assign(3) size: ", a3); return false
	var cost_best := 0.0
	var cost_identity := 0.0
	for i in range(3):
		var id: String = ids3[i]
		cost_best += pos3[id].distance_to(pts3[int(a3[id])])
		cost_identity += pos3[id].distance_to(pts3[i])
	if cost_best > cost_identity + EPS:
		print("FAIL brute force not optimal: best=%f identity=%f" % [cost_best, cost_identity])
		return false
	print("PASS assign_bruteforce_optimal"); return true


## ⑦ N=7（> 6）：走贪心，逐个对上自己的点（无重复、全覆盖）
func _test_assign_greedy_large() -> bool:
	var ids: Array[String] = []
	var pos := {}
	var pts: Array[Vector2] = []
	for i in range(7):
		var id := "c_%d" % i
		ids.append(id)
		pos[id] = Vector2(float(i) * 10.0, 0.0)
		pts.append(Vector2(float(i) * 10.0, 0.0))
	var assign := Coop.assign_one_to_one(ids, pos, pts)
	if assign.size() != 7:
		print("FAIL greedy size: ", assign); return false
	var used := {}
	for i in range(7):
		var id2: String = ids[i]
		if int(assign[id2]) != i:
			print("FAIL greedy %s -> %d (expect %d)" % [id2, int(assign[id2]), i]); return false
		used[int(assign[id2])] = true
	if used.size() != 7:
		print("FAIL greedy duplicates: ", used.keys()); return false
	print("PASS assign_greedy_large"); return true


## ⑧ 车数 ≠ 点数 / 车为 0 → 空字典（`printerr` 是预期输出）
func _test_assign_size_mismatch() -> bool:
	var ids: Array[String] = ["a", "b"]
	var pos := {"a": Vector2(0.0, 0.0), "b": Vector2(1.0, 0.0)}
	var pts: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(2.0, 0.0)]
	if not Coop.assign_one_to_one(ids, pos, pts).is_empty():
		print("FAIL assign car2/point3 not empty"); return false
	var empty_ids: Array[String] = []
	var empty_pts: Array[Vector2] = []
	if not Coop.assign_one_to_one(empty_ids, {}, empty_pts).is_empty():
		print("FAIL assign 0/0 not empty"); return false
	print("PASS assign_size_mismatch"); return true


## ⑨ 3 点环（task_43 §七）：`ring_points(center, 3)` → size 3、每点在 R = 3.0 m 环上、
##    下标 0 = (67,64)（offset = 0 → θ = 0°）、三点两两夹角 120°（θ = 2π·i/3）、相邻弦长 3√3
func _test_ring_points_3() -> bool:
	var center := Vector2(64.0, 64.0)
	var pts := Coop.ring_points(center, 3)
	if pts.size() != 3:
		print("FAIL ring_points(3) size: ", pts.size()); return false
	for i in range(3):
		if absf(pts[i].distance_to(center) - 3.0) > EPS:
			print("FAIL ring_points(3) radius i=%d: %f" % [i, pts[i].distance_to(center)]); return false
	if not _approx(pts[0], Vector2(67.0, 64.0)):
		print("FAIL ring_points(3) point0: ", pts[0]); return false
	var expect_chord := 3.0 * sqrt(3.0)                    # 3√3 ≈ 5.196 m
	for i in range(3):
		var a := pts[i] - center
		var b := pts[(i + 1) % 3] - center
		var cos_theta := a.dot(b) / (3.0 * 3.0)
		var theta := acos(clampf(cos_theta, -1.0, 1.0))
		if absf(theta - TAU / 3.0) > 1e-3:
			print("FAIL ring_points(3) angle i=%d: %f rad" % [i, theta]); return false
		if absf(pts[i].distance_to(pts[(i + 1) % 3]) - expect_chord) > EPS:
			print("FAIL ring_points(3) chord i=%d" % i); return false
	print("PASS ring_points_3"); return true


## ⑩ 排除请求者（task_43 §七 / 口径 #9）：4 车里有 1 台是请求者 → 只给另外 3 台各发一条 Goto，
##    请求者不出现在任何 targets 里，且环上正好 3 个点（θ = 2π·i/3，R = 3.0）。
func _test_assist_excludes_requester() -> bool:
	var requester := HEX_PREFIX + "8a9796f5850976924958893f249d21081aeed5d224a044a835a5e1c833bcb859"
	var others := [
		HEX_PREFIX + "6f528fe271a08e87f3479b97b7b3b2b246ece0789fa61f15f0f679a3164967c1",
		HEX_PREFIX + "a8ec6a9bbc3a517300fb071809279b2a325c6d69822903f29dcb042610ec7ab5",
		HEX_PREFIX + "ba26c91230c14a1bd37cd61a25f7276e8eb9265be3fc18f0409b6a1738877ebb",
	]
	var reg := FakeRegistry.new()
	reg.vehicles[requester] = {"name": "c1", "x": 64.0, "y": 60.0, "yaw": 0.0, "node_type": "car"}
	reg.vehicles[others[0]] = {"name": "c2", "x": 60.0, "y": 64.0, "yaw": 0.0, "node_type": "car"}
	reg.vehicles[others[1]] = {"name": "c3", "x": 68.0, "y": 64.0, "yaw": 0.0, "node_type": "car"}
	reg.vehicles[others[2]] = {"name": "c4", "x": 64.0, "y": 68.0, "yaw": 0.0, "node_type": "car"}
	var bus := FakeBus.new()
	var sent: Array = []
	bus.cmd_send.connect(func(t, c): sent.append([t, c]))
	var coop = Coop.new()          # 不 add_child：避免 _ready 里解析 EventBus（-s 模式无 autoload）
	coop._registry = reg
	coop._bus = bus
	coop._on_assist_request(requester, 64.0, 64.0)
	# ① 只发 3 条（4 车 − 请求者）
	if sent.size() != 3:
		print("FAIL excludes_requester: sent=%d（应 3）" % sent.size()); coop.free(); return false
	# ② 请求者不在任何 targets 里（本步的核心断言）
	for e in sent:
		var targets: Array = e[0]
		if targets.has(requester):
			print("FAIL excludes_requester: 请求者仍被指派 targets=", targets); coop.free(); return false
	# ③ 恰好覆盖另外 3 台车、一车一条
	var got: Array = []
	for e in sent:
		got.append_array(e[0])
	got.sort()
	var want: Array = others.duplicate(); want.sort()
	if got != want:
		print("FAIL excludes_requester: ids=%s want %s" % [got, want]); coop.free(); return false
	# ④ 三条 Goto 的目标坐标两两不同、都在 3 m 环上、且正好等于 ring_points(center,3)
	var ring := Coop.ring_points(Vector2(64.0, 64.0), 3)
	var seen: Array = []
	for e in sent:
		var m: Dictionary = e[1].missions[0]
		var p := Vector2(float(m.x), float(m.y))
		if absf(p.distance_to(Vector2(64.0, 64.0)) - 3.0) > EPS:
			print("FAIL excludes_requester: 不在 3 m 环上 ", p); coop.free(); return false
		var hit := false
		for r in ring:
			if _approx(p, r): hit = true
		if not hit:
			print("FAIL excludes_requester: 目标不在 ring_points(center,3) 上 ", p); coop.free(); return false
		seen.append(p)
	if seen.size() != 3 or seen[0] == seen[1] or seen[1] == seen[2] or seen[0] == seen[2]:
		print("FAIL excludes_requester: 目标点重复 ", seen); coop.free(); return false
	# ⑤ 派车帧**成对两条**（task_48 §2.4 / 口径 #4）：每条都是 [Goto(环点), Face(人)]，
	#    Face 的 (x, y) = 请求里的 (x, y)（人 / 入侵者世界坐标），且不带 half_side/fx/fy
	#    （type=4 在字节层只有两个 f32，朝向点用 x/y 键承载）
	var pair_frames := 0
	for e in sent:
		var pair_missions: Array = e[1].missions
		if pair_missions.size() != 2:
			print("FAIL excludes_requester: 帧内应为 2 条任务，实际 %d" % pair_missions.size())
			coop.free(); return false
		if int(pair_missions[0].type) != ProtocolDef.MISSION_TYPE_GOTO:
			print("FAIL excludes_requester: missions[0] 应为 Goto ", pair_missions[0])
			coop.free(); return false
		var face_m: Dictionary = pair_missions[1]
		if int(face_m.type) != ProtocolDef.MISSION_TYPE_FACE:
			print("FAIL excludes_requester: missions[1] 应为 Face ", face_m)
			coop.free(); return false
		if face_m.has("half_side") or face_m.has("fx") or face_m.has("fy"):
			print("FAIL excludes_requester: Face 条目不应带 half_side/fx/fy ", face_m)
			coop.free(); return false
		if absf(float(face_m.x) - 64.0) > EPS or absf(float(face_m.y) - 64.0) > EPS:
			print("FAIL excludes_requester: Face 朝向点应为人的坐标 (64,64) ", face_m)
			coop.free(); return false
		pair_frames += 1
	if pair_frames != 3:
		print("FAIL excludes_requester: 成对帧数 = %d（应 3）" % pair_frames)
		coop.free(); return false
	coop.free()
	print("PASS assist_excludes_requester"); return true
