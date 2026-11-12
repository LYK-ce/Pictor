extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## VehicleApi 单测（task_51 Step 1 §2.3-5 / §2.4）
## 用法: godot --headless --path <项目> -s res://src/test/test_vehicle_api.gd
## 覆盖：空表 / 15 键记录模板 / 未收到位姿 / valid=false 的 pose / valid=true 的 pose（格心 64.25）/
##       未注册 vid 的 pose 不造条目 / filter 五键 / Get_By_Name 未命中返回 {} / Summary 计数 /
##       VehicleRegistry 编队与 get_id_by_name 回归
##
## 用**运行期 `load()`** 取注册表脚本（不是 `preload`）：`vehicle_registry.gd` 的 `_ready` 里直写
## autoload 标识符 `EventBus`，`preload` 会在 `-s` 脚本编译期把它当依赖一起编译 → `Identifier not found`。
## `new()` 后**不进树** ⇒ `_ready` 不跑、EventBus 不被访问，`_on_vehicle_registered` / `_on_pose`
## 等普通方法可直接调用（与 src/test/test_formation.gd 同做法）。
## VehicleApi 是纯静态、不碰 EventBus，用 `preload` 即可（其内部只引用既有全局类 CoordUtils）。

const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"
const Api := preload("res://src/agent/vehicle_api.gd")

## 15 键模板（逐键核；与 vehicle_registry.gd `_on_vehicle_registered` 同集合）
const RECORD_KEYS := [
	"name", "node_type",
	"x", "y", "z", "yaw", "vx", "vy",
	"valid", "sub_gx", "sub_gy", "rtk_fixed",
	"time_boot_ms",
	"has_pose", "last_pose_ms",
]

## 与 OrionMessages.Decode_Pose 返回的键**同名**（这里直接构造，避免依赖协议编解码）
const POSE_IDLE := {
	"time_boot_ms": 1000, "x": 10.0, "y": 20.0, "z": 1.5, "vx": 0.1, "vy": 0.2,
	"yaw": 0.3, "valid": false, "sub_gx": 0, "sub_gy": 0, "rtk_fixed": true,
}
const POSE_GOTO := {
	"time_boot_ms": 2000, "x": 12.0, "y": 22.0, "z": 0.0, "vx": 0.4, "vy": 0.0,
	"yaw": 1.5, "valid": true, "sub_gx": 128, "sub_gy": 128, "rtk_fixed": false,
}

var _registry_script: Script = null


func _initialize() -> void:
	_registry_script = load(REGISTRY_SCRIPT) as Script
	if _registry_script == null:
		print("FAIL load registry script")
		print("=== ALL PASS: false ===")
		quit(1)
		return
	var ok := true
	ok = ok and _test_empty()
	ok = ok and _test_record_keys()
	ok = ok and _test_registered_without_pose()
	ok = ok and _test_pose_idle()
	ok = ok and _test_pose_busy_cell_center()
	ok = ok and _test_pose_for_unregistered_vid()
	ok = ok and _test_filters()
	ok = ok and _test_get_by_name()
	ok = ok and _test_summary()
	ok = ok and _test_registry_regression()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


# ─── 工具 ──────────────────────────────────────────────────────

func _new_reg():
	return _registry_script.new()


func _pose_dict(src: Dictionary) -> Dictionary:
	return src.duplicate(true)


## T1 空注册表：Query 返回 []，Summary.online == 0
func _test_empty() -> bool:
	var reg = _new_reg()
	if not Api.Query(reg, {}).is_empty():
		print("FAIL empty: Query 非空 ", Api.Query(reg, {}))
		reg.free(); return false
	if not Api.Query(reg).is_empty():
		print("FAIL empty: Query 缺省 filter 非空")
		reg.free(); return false
	var sum := Api.Summary(reg)
	if int(sum["online"]) != 0:
		print("FAIL empty: Summary.online=", sum["online"])
		reg.free(); return false
	if int(sum["idle"]) != 0 or int(sum["busy"]) != 0 or int(sum["no_pose"]) != 0:
		print("FAIL empty: 三态计数非零 ", sum)
		reg.free(); return false
	if sum.has("stale") and int(sum["stale"]) != 0:
		print("FAIL empty: stale=", sum["stale"])
		reg.free(); return false
	reg.free()
	print("PASS empty"); return true


## T2 记录模板 15 键（逐键核：14+1 个真键，一个不多一个不少）
func _test_record_keys() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	if not reg.vehicles.has("aa"):
		print("FAIL record_keys: 注册后无条目"); reg.free(); return false
	var rec: Dictionary = reg.vehicles["aa"]
	if rec.size() != RECORD_KEYS.size():
		print("FAIL record_keys: 键数=", rec.size(), " 期望 ", RECORD_KEYS.size(), " 实际键=", rec.keys())
		reg.free(); return false
	for k: String in RECORD_KEYS:
		if not rec.has(k):
			print("FAIL record_keys: 缺键 ", k); reg.free(); return false
	if bool(rec["has_pose"]):
		print("FAIL record_keys: has_pose 初值非 false"); reg.free(); return false
	if int(rec["last_pose_ms"]) != -1:
		print("FAIL record_keys: last_pose_ms 初值非 -1"); reg.free(); return false
	if bool(rec["valid"]):
		print("FAIL record_keys: valid 初值非 false"); reg.free(); return false
	reg.free()
	print("PASS record_keys"); return true


## T3 注册未喂位姿：online=true / has_pose=false / state="no_pose" / pose_age_ms=-1
func _test_registered_without_pose() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_peer_info_updated("aa", "simq_ugv_c1", "car")
	var rows := Api.Query(reg, {})
	if rows.size() != 1:
		print("FAIL no_pose: 条数=", rows.size()); reg.free(); return false
	var r: Dictionary = rows[0]
	if str(r["vid"]) != "aa" or str(r["name"]) != "simq_ugv_c1" or str(r["node_type"]) != "car":
		print("FAIL no_pose: 身份字段错 ", r); reg.free(); return false
	if not bool(r["online"]):
		print("FAIL no_pose: online 非 true"); reg.free(); return false
	if bool(r["has_pose"]):
		print("FAIL no_pose: has_pose 非 false"); reg.free(); return false
	if str(r["state"]) != "no_pose":
		print("FAIL no_pose: state=", r["state"]); reg.free(); return false
	if int(r["pose_age_ms"]) != -1:
		print("FAIL no_pose: pose_age_ms=", r["pose_age_ms"]); reg.free(); return false
	if bool(r["busy"]):
		print("FAIL no_pose: busy 非 false"); reg.free(); return false
	if r["sub_target"] != null:
		print("FAIL no_pose: sub_target 非 null ", r["sub_target"]); reg.free(); return false
	reg.free()
	print("PASS no_pose"); return true


## T4 valid=false 的 pose → has_pose=true / state="idle" / sub_target=null，其余字段真落库
func _test_pose_idle() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_pose("aa", _pose_dict(POSE_IDLE))
	var rows := Api.Query(reg, {})
	if rows.size() != 1:
		print("FAIL pose_idle: 条数=", rows.size()); reg.free(); return false
	var r: Dictionary = rows[0]
	if not bool(r["has_pose"]):
		print("FAIL pose_idle: has_pose 非 true"); reg.free(); return false
	if str(r["state"]) != "idle":
		print("FAIL pose_idle: state=", r["state"]); reg.free(); return false
	if bool(r["busy"]):
		print("FAIL pose_idle: busy 非 false"); reg.free(); return false
	if r["sub_target"] != null:
		print("FAIL pose_idle: sub_target 非 null ", r["sub_target"]); reg.free(); return false
	if int(r["pose_age_ms"]) < 0:
		print("FAIL pose_idle: pose_age_ms=", r["pose_age_ms"]); reg.free(); return false
	if absf(float(r["z"]) - 1.5) > 1e-6:
		print("FAIL pose_idle: z=", r["z"]); reg.free(); return false
	if absf(float(r["vx"]) - 0.1) > 1e-6 or absf(float(r["vy"]) - 0.2) > 1e-6:
		print("FAIL pose_idle: vx/vy=", r["vx"], "/", r["vy"]); reg.free(); return false
	if not bool(r["rtk_fixed"]):
		print("FAIL pose_idle: rtk_fixed 未落库"); reg.free(); return false
	if absf(float(r["x"]) - 10.0) > 1e-6 or absf(float(r["y"]) - 20.0) > 1e-6:
		print("FAIL pose_idle: x/y=", r["x"], "/", r["y"]); reg.free(); return false
	if absf(float(r["yaw"]) - 0.3) > 1e-6:
		print("FAIL pose_idle: yaw=", r["yaw"]); reg.free(); return false
	if int(reg.vehicles["aa"]["time_boot_ms"]) != 1000:
		print("FAIL pose_idle: time_boot_ms 未落库 ", reg.vehicles["aa"]["time_boot_ms"])
		reg.free(); return false
	reg.free()
	print("PASS pose_idle"); return true


## T5 valid=true, sub_gx=sub_gy=128 → state="busy"，sub_target 必须是格**中心** 64.25（不是 64.0）
func _test_pose_busy_cell_center() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_pose("aa", _pose_dict(POSE_GOTO))
	var rows := Api.Query(reg, {})
	if rows.size() != 1:
		print("FAIL busy: 条数=", rows.size()); reg.free(); return false
	var r: Dictionary = rows[0]
	if str(r["state"]) != "busy":
		print("FAIL busy: state=", r["state"]); reg.free(); return false
	if not bool(r["busy"]):
		print("FAIL busy: busy 非 true"); reg.free(); return false
	if not (r["sub_target"] is Dictionary):
		print("FAIL busy: sub_target 非 Dictionary ", r["sub_target"]); reg.free(); return false
	var st: Dictionary = r["sub_target"]
	if not st.has("x") or not st.has("y"):
		print("FAIL busy: sub_target 缺 x/y ", st); reg.free(); return false
	var sx := float(st["x"])
	var sy := float(st["y"])
	if sx != 64.25 or sy != 64.25:
		print("FAIL busy: sub_target=", sx, ",", sy, " 期望 64.25,64.25（格中心，不是 64.0）")
		reg.free(); return false
	if sx == 64.0 or sy == 64.0:
		print("FAIL busy: sub_target 取了格左下角 64.0（应为格中心 64.25）")
		reg.free(); return false
	if int(reg.vehicles["aa"]["sub_gx"]) != 128 or int(reg.vehicles["aa"]["sub_gy"]) != 128:
		print("FAIL busy: sub_gx/sub_gy 未落库 ", reg.vehicles["aa"]["sub_gx"], "/", reg.vehicles["aa"]["sub_gy"])
		reg.free(); return false
	reg.free()
	print("PASS busy_cell_center"); return true


## T6 未注册 vid 的 pose 不得造出条目（保留 `if not vehicles.has(): return`）
func _test_pose_for_unregistered_vid() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_pose("ghost", _pose_dict(POSE_GOTO))
	if reg.vehicles.size() != 1:
		print("FAIL ghost_pose: vehicles.size=", reg.vehicles.size(), " ", reg.vehicles.keys())
		reg.free(); return false
	if reg.vehicles.has("ghost"):
		print("FAIL ghost_pose: 造出了 ghost 条目"); reg.free(); return false
	if Api.Query(reg, {}).size() != 1:
		print("FAIL ghost_pose: Query 条数=", Api.Query(reg, {}).size()); reg.free(); return false
	if not Api.Query(reg, {"vid": "ghost"}).is_empty():
		print("FAIL ghost_pose: ghost 能被 filter 命中"); reg.free(); return false
	reg.free()
	print("PASS ghost_pose"); return true


## T7 filter 各键命中数（含陈旧车：OS.delay_msec 真等 > STALE_MS，不伪造 last_pose_ms——
## 单测进程里 Time.get_ticks_msec() 从 0 起，now - 5000 会是负值被当成"从未收到位姿"）
func _test_filters() -> bool:
	var reg = _new_reg()
	# car #1：idle（valid=false）；car #2：busy；uav #3：从未收到位姿
	reg._on_vehicle_registered("aa")
	reg._on_peer_info_updated("aa", "car_idle", "car")
	reg._on_pose("aa", _pose_dict(POSE_IDLE))

	reg._on_vehicle_registered("bb")
	reg._on_peer_info_updated("bb", "car_busy", "car")
	reg._on_pose("bb", _pose_dict(POSE_GOTO))

	reg._on_vehicle_registered("cc")
	reg._on_peer_info_updated("cc", "uav_1", "uav")

	if Api.Query(reg, {}).size() != 3:
		print("FAIL filter: 全量为 ", Api.Query(reg, {}).size()); reg.free(); return false
	if Api.Query(reg, {"node_type": "car"}).size() != 2:
		print("FAIL filter: node_type=car 命中 ", Api.Query(reg, {"node_type": "car"}).size())
		reg.free(); return false
	if Api.Query(reg, {"node_type": "uav"}).size() != 1:
		print("FAIL filter: node_type=uav 命中 ", Api.Query(reg, {"node_type": "uav"}).size())
		reg.free(); return false
	if Api.Query(reg, {"busy": true}).size() != 1:
		print("FAIL filter: busy=true 命中 ", Api.Query(reg, {"busy": true}).size())
		reg.free(); return false
	if Api.Query(reg, {"busy": false}).size() != 2:
		print("FAIL filter: busy=false 命中 ", Api.Query(reg, {"busy": false}).size())
		reg.free(); return false
	if Api.Query(reg, {"has_pose": false}).size() != 1:
		print("FAIL filter: has_pose=false 命中 ", Api.Query(reg, {"has_pose": false}).size())
		reg.free(); return false
	if Api.Query(reg, {"name": "car_busy"}).size() != 1:
		print("FAIL filter: name 命中 ", Api.Query(reg, {"name": "car_busy"}).size())
		reg.free(); return false
	if Api.Query(reg, {"vid": "cc"}).size() != 1:
		print("FAIL filter: vid 命中 ", Api.Query(reg, {"vid": "cc"}).size())
		reg.free(); return false
	if not Api.Query(reg, {"name": "nobody"}).is_empty():
		print("FAIL filter: 不存在的 name 有命中"); reg.free(); return false

	# 刚喂完位姿 ⇒ 两台"有 pose"的都新鲜（60 s 内）；从未上报的 cc 永远被新鲜度过滤排除
	if Api.Query(reg, {"max_pose_age_ms": 60000}).size() != 2:
		print("FAIL filter: max_pose_age_ms=60000 命中 ", Api.Query(reg, {"max_pose_age_ms": 60000}).size())
		reg.free(); return false
	if not Api.Query(reg, {"max_pose_age_ms": -1}).is_empty():
		print("FAIL filter: max_pose_age_ms=-1 应 0 命中（含从未收到位姿者）")
		reg.free(); return false
	# 真等 1100 ms（> STALE_MS）让两台车确定性变陈旧——不伪造 last_pose_ms、不靠"0 毫秒边界"
	OS.delay_msec(Api.STALE_MS + 100)
	if not Api.Query(reg, {"max_pose_age_ms": 0}).is_empty():
		print("FAIL filter: 陈旧后 max_pose_age_ms=0 命中 ", Api.Query(reg, {"max_pose_age_ms": 0}))
		reg.free(); return false
	if Api.Query(reg, {"max_pose_age_ms": 60000}).size() != 2:
		print("FAIL filter: 陈旧后 60000 命中 ", Api.Query(reg, {"max_pose_age_ms": 60000}).size())
		reg.free(); return false
	# 多键 = 逻辑与
	if Api.Query(reg, {"busy": true, "max_pose_age_ms": 60000}).size() != 1:
		print("FAIL filter: busy+age 组合命中 ", Api.Query(reg, {"busy": true, "max_pose_age_ms": 60000}).size())
		reg.free(); return false
	if Api.Query(reg, {"node_type": "car", "max_pose_age_ms": 60000}).size() != 2:
		print("FAIL filter: car+age 组合命中 ", Api.Query(reg, {"node_type": "car", "max_pose_age_ms": 60000}).size())
		reg.free(); return false
	reg.free()
	print("PASS filters"); return true


## T8 Get_By_Name：命中返回记录；未命中返回空 Dictionary（**不是 null**）
func _test_get_by_name() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_peer_info_updated("aa", "simq_ugv_c1", "car")
	var hit := Api.Get_By_Name(reg, "simq_ugv_c1")
	if not (hit is Dictionary):
		print("FAIL get_by_name: 命中不是 Dictionary"); reg.free(); return false
	if hit.is_empty():
		print("FAIL get_by_name: 命中为空"); reg.free(); return false
	if str(hit["vid"]) != "aa":
		print("FAIL get_by_name: vid=", hit["vid"]); reg.free(); return false
	var miss = Api.Get_By_Name(reg, "nobody")
	if miss == null:
		print("FAIL get_by_name: 未命中返回 null（应为空 Dictionary）"); reg.free(); return false
	if not (miss is Dictionary) or not miss.is_empty():
		print("FAIL get_by_name: 未命中不是空 Dictionary ", miss); reg.free(); return false
	reg.free()
	print("PASS get_by_name"); return true


## T9 Summary：online / cars / uavs / idle / busy / no_pose / stale 七键计数
func _test_summary() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_peer_info_updated("aa", "car_idle", "car")
	reg._on_pose("aa", _pose_dict(POSE_IDLE))
	reg._on_vehicle_registered("bb")
	reg._on_peer_info_updated("bb", "car_busy", "car")
	reg._on_pose("bb", _pose_dict(POSE_GOTO))
	reg._on_vehicle_registered("cc")
	reg._on_peer_info_updated("cc", "uav_1", "uav")
	reg._on_vehicle_registered("dd")          # 类型未知 + 无位姿
	var sum := Api.Summary(reg)
	if int(sum["online"]) != 4:
		print("FAIL summary: online=", sum["online"]); reg.free(); return false
	if int(sum["cars"]) != 2:
		print("FAIL summary: cars=", sum["cars"]); reg.free(); return false
	if int(sum["uavs"]) != 1:
		print("FAIL summary: uavs=", sum["uavs"]); reg.free(); return false
	if int(sum["idle"]) != 1:
		print("FAIL summary: idle=", sum["idle"]); reg.free(); return false
	if int(sum["busy"]) != 1:
		print("FAIL summary: busy=", sum["busy"]); reg.free(); return false
	if int(sum["no_pose"]) != 2:
		print("FAIL summary: no_pose=", sum["no_pose"]); reg.free(); return false
	if int(sum["stale"]) != 0:
		print("FAIL summary: stale=", sum["stale"]); reg.free(); return false
	# 真等 1100 ms（> STALE_MS）→ 两台有 pose 的车都算 stale；cc/dd 无位姿**不计入** stale
	OS.delay_msec(Api.STALE_MS + 100)
	var sum2 := Api.Summary(reg)
	if int(sum2["stale"]) != 2:
		print("FAIL summary: 陈旧后 stale=", sum2["stale"]); reg.free(); return false
	if int(sum2["idle"]) != 1 or int(sum2["busy"]) != 1 or int(sum2["no_pose"]) != 2:
		print("FAIL summary: stale 不应改三态 ", sum2); reg.free(); return false
	reg.free()
	print("PASS summary"); return true


## T10 回归：扩字段后 formations / get_id_by_name / 注销 行为不变
func _test_registry_regression() -> bool:
	var reg = _new_reg()
	reg._on_vehicle_registered("aa")
	reg._on_peer_info_updated("aa", "simq_ugv_c1", "car")
	if reg.get_id_by_name("simq_ugv_c1") != "aa":
		print("FAIL regression: get_id_by_name=", reg.get_id_by_name("simq_ugv_c1"))
		reg.free(); return false
	if reg.get_id_by_name("nobody") != "":
		print("FAIL regression: 未命中不为空串"); reg.free(); return false
	if str(reg.Get_Formation("aa")) != "":
		print("FAIL regression: 默认编队非空"); reg.free(); return false
	if not reg.Join_Formation("aa", "containment"):
		print("FAIL regression: Join_Formation 失败"); reg.free(); return false
	if str(reg.Get_Formation("aa")) != "containment":
		print("FAIL regression: Get_Formation=", reg.Get_Formation("aa")); reg.free(); return false
	# 注销只擦 vehicles，不擦 formations，且不残留 Query 条目
	reg._on_vehicle_unregistered("aa")
	if not reg.vehicles.is_empty():
		print("FAIL regression: 注销后 vehicles 非空"); reg.free(); return false
	if not Api.Query(reg, {}).is_empty():
		print("FAIL regression: 注销后 Query 非空"); reg.free(); return false
	if str(reg.Get_Formation("aa")) != "containment":
		print("FAIL regression: 注销擦掉了编队"); reg.free(); return false
	reg.free()
	print("PASS registry_regression"); return true
