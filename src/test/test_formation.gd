extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-08
##
## VehicleRegistry 编队数据层单测（task_50 Step 6 §7.2 / §7.5 判据 3）
## 用法: godot --headless --path <项目> -s res://src/test/test_formation.gd
## 覆盖：默认无编队 / join 幂等 / members 排序 / leave 幂等 / 非法 id 全拒且不改 /
##       断线重连保留（§7.6 F4）/ 多编队 / 全表快照 / 覆盖语义 / 与 vehicles 解耦
##
## 用**运行期 `load()`**（不是 `preload`）：`vehicle_registry.gd` 的 `_ready` 里直写 autoload
## 标识符 `EventBus`，`preload` 会在 `-s` 脚本编译期把它当依赖一起编译 → `Identifier not found`。
## 运行期 `load()` 时 autoload 已注册（与 `tool/check_ws_command_server.gd` 同做法），`new()` 后
## **不进树** ⇒ `_ready` 不跑，`_on_vehicle_registered` 等普通方法可直接调用。

const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"

var _registry_script: Script = null


func _initialize() -> void:
	_registry_script = load(REGISTRY_SCRIPT) as Script
	if _registry_script == null:
		print("FAIL load registry script")
		print("=== ALL PASS: false ===")
		quit(1)
		return
	var ok := true
	ok = ok and _test_default_empty()
	ok = ok and _test_join_idempotent()
	ok = ok and _test_members_sorted()
	ok = ok and _test_leave_idempotent()
	ok = ok and _test_invalid_ids_rejected()
	ok = ok and _test_reconnect_keeps_formation()
	ok = ok and _test_multi_formation()
	ok = ok and _test_formation_table()
	ok = ok and _test_join_overwrites()
	ok = ok and _test_decoupled_from_vehicles()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


func _new_reg():
	return _registry_script.new()


## 字符串数组比较（不依赖 `Array[String] == Array` 的类型细节）
func _eq_str(arr, want: Array) -> bool:
	if arr.size() != want.size():
		return false
	for i in range(want.size()):
		if str(arr[i]) != str(want[i]):
			return false
	return true


## F1 默认无编队：新注册车 Get_Formation == ""，members 为空
func _test_default_empty() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("a")
	if str(reg.Get_Formation("a")) != "":
		print("FAIL formation_default_empty: Get_Formation=", reg.Get_Formation("a"))
		reg.free(); return false
	if not reg.Get_Formation_Members("containment").is_empty():
		print("FAIL formation_default_empty: members 非空")
		reg.free(); return false
	if not reg.formations.is_empty():
		print("FAIL formation_default_empty: formations 默认非空 ", reg.formations)
		reg.free(); return false
	reg.free()
	print("PASS formation_default_empty"); return true


## F2 join 生效 + 幂等
func _test_join_idempotent() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("a")
	if not reg.Join_Formation("a", "containment"):
		print("FAIL formation_join: 首次 join 返回 false"); reg.free(); return false
	if not reg.Join_Formation("a", "containment"):
		print("FAIL formation_join: 二次 join（幂等）返回 false"); reg.free(); return false
	if str(reg.Get_Formation("a")) != "containment":
		print("FAIL formation_join: Get_Formation=", reg.Get_Formation("a")); reg.free(); return false
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a"]):
		print("FAIL formation_join: members=", reg.Get_Formation_Members("containment"))
		reg.free(); return false
	reg.free()
	print("PASS formation_join"); return true


## F3 members 排序：依次 join b,a,c → ["a","b","c"]
func _test_members_sorted() -> bool:
	var reg = _new_reg()
	for vid: String in ["b", "a", "c"]:
		reg.Join_Formation(vid, "containment")
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a", "b", "c"]):
		print("FAIL formation_members_sorted: ", reg.Get_Formation_Members("containment"))
		reg.free(); return false
	reg.free()
	print("PASS formation_members_sorted"); return true


## F4 leave 幂等：在 → 擦；不在 → true；未知 vid → true
func _test_leave_idempotent() -> bool:
	var reg = _new_reg()
	reg.Join_Formation("a", "containment")
	if not reg.Leave_Formation("a"):
		print("FAIL formation_leave: 首次 leave 返回 false"); reg.free(); return false
	if str(reg.Get_Formation("a")) != "":
		print("FAIL formation_leave: 仍在编队 ", reg.Get_Formation("a")); reg.free(); return false
	if not reg.Leave_Formation("a"):
		print("FAIL formation_leave: 二次 leave（幂等）返回 false"); reg.free(); return false
	if not reg.Leave_Formation("never_seen"):
		print("FAIL formation_leave: 未知 vid leave 返回 false"); reg.free(); return false
	reg.free()
	print("PASS formation_leave"); return true


## F5 非法 fid 全拒且不改：空 / 空白 / 大写 / 空格 / 标点 / 33 字符 / 中文
func _test_invalid_ids_rejected() -> bool:
	var reg = _new_reg()
	reg.Join_Formation("a", "containment")
	var bad := [
		"", "  ", "Containment", "a b", "wall!", "a".repeat(33), "围控",
	]
	for fid: String in bad:
		if reg.Join_Formation("a", fid):
			print("FAIL formation_invalid_id: 非法 id 被接受 ", fid); reg.free(); return false
		if str(reg.Get_Formation("a")) != "containment":
			print("FAIL formation_invalid_id: 非法 id 改写了注册表 ", fid)
			reg.free(); return false
	if reg.Join_Formation("", "containment"):
		print("FAIL formation_invalid_id: 空 vid 被接受"); reg.free(); return false
	reg.free()
	print("PASS formation_invalid_id"); return true


## F6 断线重连保留（§7.6 F4）：unregister 只擦 vehicles，formations 不动
func _test_reconnect_keeps_formation() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("a")
	reg.Join_Formation("a", "containment")
	reg._on_vehicle_unregistered("a")
	if reg.vehicles.has("a"):
		print("FAIL formation_reconnect: vehicles 未擦除"); reg.free(); return false
	if str(reg.Get_Formation("a")) != "containment":
		print("FAIL formation_reconnect: 断线后编队丢失 ", reg.Get_Formation("a"))
		reg.free(); return false
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a"]):
		print("FAIL formation_reconnect: 断线后 members 丢失")
		reg.free(); return false
	reg._on_vehicle_registered("a")
	if str(reg.Get_Formation("a")) != "containment":
		print("FAIL formation_reconnect: 重连后编队丢失"); reg.free(); return false
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a"]):
		print("FAIL formation_reconnect: 重连后 members 不一致"); reg.free(); return false
	reg.free()
	print("PASS formation_reconnect"); return true


## F7 多编队：containment / wall / 未使用的 keep_out
func _test_multi_formation() -> bool:
	var reg = _new_reg()
	reg.Join_Formation("a", "containment")
	reg.Join_Formation("b", "containment")
	reg.Join_Formation("c", "wall")
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a", "b"]):
		print("FAIL formation_multi: containment=", reg.Get_Formation_Members("containment"))
		reg.free(); return false
	if not _eq_str(reg.Get_Formation_Members("wall"), ["c"]):
		print("FAIL formation_multi: wall=", reg.Get_Formation_Members("wall"))
		reg.free(); return false
	if not reg.Get_Formation_Members("keep_out").is_empty():
		print("FAIL formation_multi: keep_out 应为空"); reg.free(); return false
	reg.free()
	print("PASS formation_multi"); return true


## F8 全表快照：{containment:[a,b], wall:[c]}，fid 键字典序
func _test_formation_table() -> bool:
	var reg = _new_reg()
	reg.Join_Formation("a", "containment")
	reg.Join_Formation("b", "containment")
	reg.Join_Formation("c", "wall")
	var table: Dictionary = reg.Get_Formation_Table()
	var keys: Array = table.keys()
	keys.sort()
	if not _eq_str(keys, ["containment", "wall"]):
		print("FAIL formation_table: keys=", keys); reg.free(); return false
	if not _eq_str(table["containment"], ["a", "b"]):
		print("FAIL formation_table: containment=", table["containment"]); reg.free(); return false
	if not _eq_str(table["wall"], ["c"]):
		print("FAIL formation_table: wall=", table["wall"]); reg.free(); return false
	reg.free()
	print("PASS formation_table"); return true


## F9 覆盖语义：a 先 wall 再 containment → wall 空、containment 含 a
func _test_join_overwrites() -> bool:
	var reg = _new_reg()
	reg.Join_Formation("a", "wall")
	reg.Join_Formation("a", "containment")
	if not reg.Get_Formation_Members("wall").is_empty():
		print("FAIL formation_overwrite: wall 仍含 a"); reg.free(); return false
	if not _eq_str(reg.Get_Formation_Members("containment"), ["a"]):
		print("FAIL formation_overwrite: containment=", reg.Get_Formation_Members("containment"))
		reg.free(); return false
	reg.free()
	print("PASS formation_overwrite"); return true


## F10 与 vehicles 解耦：未注册 vid 也能记录编队（不影响派发）
func _test_decoupled_from_vehicles() -> bool:
	var reg = _new_reg()
	if not reg.Join_Formation("ghost", "x"):
		print("FAIL formation_decoupled: 未注册 vid join 返回 false"); reg.free(); return false
	if str(reg.Get_Formation("ghost")) != "x":
		print("FAIL formation_decoupled: Get_Formation=", reg.Get_Formation("ghost"))
		reg.free(); return false
	if not reg.vehicles.is_empty():
		print("FAIL formation_decoupled: join 不应写 vehicles"); reg.free(); return false
	reg.free()
	print("PASS formation_decoupled"); return true
