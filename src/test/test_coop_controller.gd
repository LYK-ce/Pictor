extends SceneTree

## Presented by KeJi
## Created Date ： 2026-10-30
## Modified Date ： 2026-10-30
##
## CoopController 纯函数单测（headless，task_41 §5.5.11）
## 用法: godot --headless --path <项目> -s <本脚本路径>
## 覆盖：3 m 环 N 点等角 / N=1;2;8 边界 / N=4 四轴覆盖 /
##       两车与四车最近一对一（无重复）/ N! 最优性（2 车 + 3 车）/ N>6 贪心 / 参数不匹配
##
## 用 preload 而不是全局类名：新 `class_name` 未进 `.godot/global_script_class_cache.cfg` 时
## 也能跑（headless 免 import）。

const Coop := preload("res://src/cooperation/coop_controller.gd")

const EPS := 1e-4


func _init() -> void:
	var ok := true
	ok = ok and _test_ring_points_4()
	ok = ok and _test_ring_points_edges()
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
