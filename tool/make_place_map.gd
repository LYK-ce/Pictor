extends SceneTree
## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## 地名表样例生成器（task_51 Step 6 §7.2 / §7.4-0）：**手动录入的辅助**，不是 GUI 入口
## 用法（cwd = Pictor）：godot --headless -s tool/make_place_map.gd [-- --reset]
##   只写 `user://place_map.json`（不碰 res://、不碰 .config/、不联网）
## 期望：5 行 `[OK]`，末行 `[DONE] ok=true`；`南门` = (64.25, 40.25)（格 (128,80) 的中心）
##
## ⚠️ 坐标口径（与 place_map.gd / executor.rs 一致，本文件不写公式）：
##   条目只给 gx/gy，x/y 一律由 PlaceMap 用 Cell_Center 派生（(g + 0.5) × 0.5）。
##   gx/gy 必须落在 [0, 256)，x/y 必须 < 128 m（TaskApi.WORLD_SIZE_M 的 `_In_World` 才放行）。
## ⚠️ 5 条样例的作用：`南门` 是 §7.4 主用例（离出生点 (64.25,64.25) 24 m）；
##   `南门内侧` 是 R9 的兜底（8.75 m，15 s 内必到）；其余三条只为证明地名表不是单条特例。

const PlaceScript := preload("res://src/map/place_map.gd")

const PATH := "user://place_map.json"

## id / name / aliases / 格号。aliases 可省（缺省 = 空数组）
const PLACES := [
	{"id": "south_gate", "name": "南门", "aliases": ["南大门"], "gx": 128, "gy": 80},
	{"id": "south_inner", "name": "南门内侧", "gx": 128, "gy": 110},
	{"id": "north_gate", "name": "北门", "gx": 128, "gy": 176},
	{"id": "east_yard", "name": "东库", "gx": 176, "gy": 128},
	{"id": "west_yard", "name": "西仓", "gx": 80, "gy": 128},
]


func _initialize() -> void:
	_Run.call_deferred()


func _Run() -> void:
	# `--reset`：先删掉旧文件（避免上次留下的脏条目混进证据；不加则原地覆盖同 id）
	if OS.get_cmdline_user_args().has("--reset") and FileAccess.file_exists(PATH):
		var abs_path := ProjectSettings.globalize_path(PATH)
		print("[RESET] remove ", abs_path, " → ", DirAccess.remove_absolute(abs_path))
	var pm = PlaceScript.new(PATH)
	var ok := true
	for p: Variant in PLACES:
		var r: Dictionary = pm.Set(p)          # Set 内部已 Save()（place_map.gd:181-188）
		if not bool(r.get("ok", false)):
			print("[FAIL] Set(", str((p as Dictionary).get("id", "")), ") → ", str(r.get("error", "")))
			ok = false
			continue
		var e: Dictionary = r["entry"]
		print("[OK] %-12s %-8s (%.2f, %.2f)  gx/gy=%d/%d" % [
			str(e["id"]), str(e["name"]), float(e["x"]), float(e["y"]),
			int(e["gx"]), int(e["gy"])])
	var lr: Dictionary = pm.Load()             # 重新读盘：证明落盘可用（不是只看内存）
	print("[LOAD] ok=", bool(lr.get("ok", false)), " count=", int(lr.get("count", 0)),
		" skipped=", int(lr.get("skipped", 0)),
		" path=", ProjectSettings.globalize_path(PATH))
	# 解析自检：主用例的两个名字必须能查回格中心坐标
	var gate: Dictionary = pm.Resolve("南门")
	var inner: Dictionary = pm.Resolve("南门内侧")
	print("[RESOLVE] 南门 ok=%s → (%.2f, %.2f) id=%s" % [
		bool(gate.get("ok", false)), float(gate.get("x", 0.0)), float(gate.get("y", 0.0)),
		str(gate.get("id", ""))])
	print("[RESOLVE] 南门内侧 ok=%s → (%.2f, %.2f) id=%s" % [
		bool(inner.get("ok", false)), float(inner.get("x", 0.0)), float(inner.get("y", 0.0)),
		str(inner.get("id", ""))])
	ok = ok and bool(lr.get("ok", false)) and int(lr.get("count", 0)) == PLACES.size()
	ok = ok and bool(gate.get("ok", false)) and bool(inner.get("ok", false))
	ok = ok and absf(float(gate.get("x", 0.0)) - 64.25) < 0.001 \
		and absf(float(gate.get("y", 0.0)) - 40.25) < 0.001
	print("[DONE] ok=", ok)
	quit(0 if ok else 1)
