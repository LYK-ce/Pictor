extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## TaskApi 单测（task_51 Step 3 §4.3-6 / §4.4）
## 用法: godot --headless --path Pictor -s res://src/test/test_task_api.gd
## 覆盖 17 组：文档 §4.3-6 的 9 条（①-⑨）+ 8 条附加（⑩-⑰）
##   ① unknown_vehicle       车不在注册表 → 一帧不发                    §4.3-6-1
##   ② unknown_type          "gurad" 被自己的白名单拦（不降级成 Goto）  §4.3-6-2
##   ③ containment_bad_args  缺 half_side / 0 / 负 / NaN               §4.3-6-3
##   ④ guard_face_bad_args   guard 缺 fx 或 fy / face 缺 fx 或 fy      §4.3-6-4
##   ⑤ goto_roundtrip        1 帧，解回 msgid 5 / type 0 / x,y          §4.3-6-5
##   ⑥ two_cars_two_frames   两车两帧、字节不同、各带自己的点           §4.3-6-6
##   ⑦ cancel_empty          missions==[] → mission_count 0              §4.3-6-7
##   ⑧ send_failed           kernel.ret=false → send_failed             §4.3-6-8
##   ⑨ bad_coord             NaN / 200 / -0.1 / 128.0 / INF             §4.3-6-9
##   ⑩ atomic_batch          混合批次（一好一坏）→ 整批一帧不发         〔判据：校验失败 calls 空〕
##   ⑪ wire_all_types        containment / face / guard 的字节层落地     〔附加〕
##   ⑫ envelope_shape        {ok,results,errors} 3/6/2 键 + ok 语义      〔附加〕
##   ⑬ kernel_not_ready      null / 无 send_command + reason 优先级      〔附加〕
##   ⑭ dispatch_one          单车入口同形返回                            〔附加〕
##   ⑮ cancel_api            Cancel 按名 / 按 vid / 空数组 no-op / 未知车〔附加〕
##   ⑯ args_and_decoupling   缺 missions 键 / 非数组 / >255 / 空 tasks   〔附加〕
##   ⑰ replace_semantics     同车两项 → 后帧覆盖前帧（替换语义可见）     〔附加〕
##
## 假 kernel 用**鸭子类型**（`class FakeKernel extends RefCounted`，只有 send_command）；
## 注册表用**真 VehicleRegistry**（运行期 `load()`、**不进树** → `_ready` 不跑 → 不碰 EventBus，
## 与 test_vehicle_api.gd / test_map_api.gd 同做法）；⑯ 另用只含 `vehicles` 的假表，
## 证明 TaskApi 除「车在不在线」外不读注册表任何字段（不读位姿 / 不读地图 = §4.4 末条）。
##
## 帧长（手算，依据 §4.3-3）：frame = 12 B 固定开销（10 B 头 + 2 B 校验，终端 sysid_len = 0）
##   + payload，payload = 1 B mission_count + Σ 记录（type 0/2/4 = 9、3 = 13、5 = 17）。

const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"
const Api := preload("res://src/agent/task_api.gd")

const VID_A := "aa11"
const VID_B := "bb22"
const NAME_A := "小车A"
const NAME_B := "小车B"

## 期望帧长（字节）
const FRAME_CANCEL := 12 + 1                     # 13
const FRAME_GOTO := 12 + 1 + 9                   # 22
const FRAME_CONTAINMENT := 12 + 1 + 13           # 26
const FRAME_GUARD := 12 + 1 + 17                 # 30

## 金标整帧：4f | len u32 BE | 00 seq | 00 sysid_len | c8 compid=200 | 0005 msgid | payload | 0000
## payload 段与 Architecture/robot_arch.md §8.16、test_orion_protocol.gd、Rust messages.rs 同一串
const GOLDEN_GOTO_64 := "4f0000000a0000c80005010042800000428000000000"
const GOLDEN_FACE_64 := "4f0000000a0000c80005010442800000428000000000"
const GOLDEN_CANCEL := "4f000000010000c80005000000"


## 假 kernel（文档 §4.3-6 的写法）：记录每次 send_command，ret 可设
class FakeKernel extends RefCounted:
	var calls: Array = []
	var ret := true

	func send_command(id: String, frame: PackedByteArray) -> bool:
		calls.append({"id": id, "frame": frame})
		return ret


## 只有 `vehicles` 的假注册表：证明 TaskApi 不依赖 VehicleRegistry 的任何方法 / 其它字段
class FakeTable extends RefCounted:
	var vehicles: Dictionary = {}


var _registry_script: Script = null


func _initialize() -> void:
	_registry_script = load(REGISTRY_SCRIPT) as Script
	if _registry_script == null:
		print("FAIL load ", REGISTRY_SCRIPT)
		print("=== ALL PASS: false ===")
		quit(1)
		return
	var ok := true
	ok = ok and _test_unknown_vehicle()
	ok = ok and _test_unknown_type()
	ok = ok and _test_containment_bad_args()
	ok = ok and _test_guard_face_bad_args()
	ok = ok and _test_goto_roundtrip()
	ok = ok and _test_two_cars_two_frames()
	ok = ok and _test_cancel_empty()
	ok = ok and _test_send_failed()
	ok = ok and _test_bad_coord()
	ok = ok and _test_atomic_batch()
	ok = ok and _test_wire_all_types()
	ok = ok and _test_envelope_shape()
	ok = ok and _test_kernel_not_ready()
	ok = ok and _test_dispatch_one()
	ok = ok and _test_cancel_api()
	ok = ok and _test_args_and_decoupling()
	ok = ok and _test_replace_semantics()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


# ─── 工具 ──────────────────────────────────────────────────────

## 一行断言：失败就打 FAIL（带 tag 与实测值），不中断后续用例（一次跑出全部问题）
func _expect(cond: bool, tag: String, msg: String) -> bool:
	if cond:
		return true
	print("FAIL ", tag, ": ", msg)
	return false


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0e-6


## 两辆在线车（真注册表，**不进树**：_ready 不跑 → 不碰 EventBus）
func _reg_two():
	var reg = _registry_script.new()
	reg.add_mock_vehicle(VID_A, NAME_A)
	reg.add_mock_vehicle(VID_B, NAME_B)
	return reg


## 一条 goto（字符串 type：走白名单那条路）
func _goto(x: float, y: float) -> Dictionary:
	return {"type": "goto", "x": x, "y": y}


## 解一帧 → {ok, msgid, compid, sysid_len, mission_count, missions, error}
func _decode(frame: PackedByteArray) -> Dictionary:
	var f: Dictionary = OrionFrame.Decode_Frame(frame)
	if not bool(f.get("ok", false)):
		return {"ok": false, "error": "frame: " + str(f.get("error", ""))}
	var sid: PackedByteArray = f["sysid"]
	var ts: Dictionary = OrionMessages.Decode_Task_Set(f["payload"])
	if not bool(ts.get("ok", false)):
		return {"ok": false, "error": "task_set: " + str(ts.get("error", ""))}
	return {
		"ok": true,
		"msgid": int(f["msgid"]),
		"compid": int(f["compid"]),
		"sysid_len": sid.size(),
		"mission_count": int(ts["mission_count"]),
		"missions": ts["missions"],
		"error": "",
	}


## 断言「被拒 + 一帧不发 + reason 命中」
func _expect_reject(r: Dictionary, k, want: String, tag: String) -> bool:
	var ok := true
	ok = ok and _expect(not bool(r["ok"]), tag, "ok 应为 false")
	ok = ok and _expect(r["results"].is_empty(), tag, "results 应空（实际 %d 条）" % r["results"].size())
	ok = ok and _expect(r["errors"].size() == 1, tag, "errors 应有 1 条（实际 %d 条）" % r["errors"].size())
	if not ok:
		return false
	ok = ok and _expect(str(r["errors"][0]["reason"]) == want, tag,
			"reason=%s 期望 %s" % [str(r["errors"][0]["reason"]), want])
	ok = ok and _expect(k.calls.is_empty(), tag, "校验失败却发了 %d 帧" % k.calls.size())
	return ok


# ─── ① unknown_vehicle ───────────────────────────────────────

func _test_unknown_vehicle() -> bool:
	var tag := "unknown_vehicle"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": "不存在的车", "missions": [_goto(1.0, 2.0)]}])
	ok = ok and _expect_reject(r, k, "unknown_vehicle", tag)
	if ok:
		ok = ok and _expect(str(r["errors"][0]["vehicle"]) == "不存在的车", tag,
				"errors.vehicle 应是入参标签（实际 " + str(r["errors"][0]["vehicle"]) + "）")
	# vid 形态的未知车：同一 reason
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Dispatch(k2, reg, [{"vid": "ffff", "missions": [_goto(1.0, 2.0)]}])
	ok = ok and _expect_reject(r2, k2, "unknown_vehicle", tag)
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ② unknown_type（白名单自己判，绝不降级成 Goto）────────────

func _test_unknown_type() -> bool:
	var tag := "unknown_type"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	# 先证明「坑」真实存在：ProtocolDef.Mission_Type_From 把未知串返回 0（= Goto）
	ok = ok and _expect(ProtocolDef.Mission_Type_From("gurad") == ProtocolDef.MISSION_TYPE_GOTO, tag,
			"Mission_Type_From(\"gurad\") 不再是 0 —— 本测试的靶子变了，需复查白名单")
	# 拼错 / 退役 1=Circle / 空串 / 非整数 float / bool / 越界整数：一律 unknown_type 且一帧不发
	var bad_types: Array = ["gurad", "GOTO2", "circle", "Circle", "", 1, 6, -1, 3.5, true]
	for bad in bad_types:
		var r: Dictionary = Api.Dispatch(k, reg,
				[{"vehicle": NAME_A, "missions": [{"type": bad, "x": 1.0, "y": 2.0}]}])
		ok = ok and _expect_reject(r, k, "unknown_type", tag)
		if not ok:
			print("  ↑ 该用例的 type = ", bad)
			break
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ③ containment 的 half_side ───────────────────────────────

func _test_containment_bad_args() -> bool:
	var tag := "containment_bad_args"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var cases: Array = [
		{"type": "containment", "x": 64.0, "y": 64.0},                        # 缺 half_side
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": 0.0},      # 0
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": -1.0},     # 负
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": NAN},      # 非有限
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": "2"},      # 非数字
	]
	for c in cases:
		var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [c]}])
		ok = ok and _expect_reject(r, k, "bad_args", tag)
		if not ok:
			print("  ↑ 该用例 = ", c)
			break
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ④ guard / face 的 fx、fy ────────────────────────────────

func _test_guard_face_bad_args() -> bool:
	var tag := "guard_face_bad_args"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var cases: Array = [
		{"type": "guard", "x": 10.0, "y": 20.0, "fy": 30.0},                  # guard 缺 fx
		{"type": "guard", "x": 10.0, "y": 20.0, "fx": 30.0},                  # guard 缺 fy
		{"type": "face", "fy": 30.0},                                         # face 缺 fx
		{"type": "face", "fx": 30.0},                                         # face 缺 fy
		{"type": "face"},                                                     # face 两个都缺
	]
	for c in cases:
		var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [c]}])
		ok = ok and _expect_reject(r, k, "bad_args", tag)
		if not ok:
			print("  ↑ 该用例 = ", c)
			break
	# 正面：face **不需要** x/y（只有 fx/fy），必须发得出去
	var k3 := FakeKernel.new()
	var r3: Dictionary = Api.Dispatch(k3, reg,
			[{"vehicle": NAME_A, "missions": [{"type": "face", "fx": 30.0, "fy": 40.0}]}])
	ok = ok and _expect(bool(r3["ok"]) and k3.calls.size() == 1, tag,
			"face 只给 fx/fy 应能下发（ok=%s calls=%d）" % [str(r3["ok"]), k3.calls.size()])
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑤ goto 正常路径 + 解帧自证 ───────────────────────────────

func _test_goto_roundtrip() -> bool:
	var tag := "goto_roundtrip"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [_goto(10.5, 20.25)]}])
	ok = ok and _expect(bool(r["ok"]), tag, "ok 应为 true")
	ok = ok and _expect(r["errors"].is_empty(), tag, "errors 应空")
	ok = ok and _expect(r["results"].size() == 1, tag, "results 应有 1 条")
	if ok:
		var row: Dictionary = r["results"][0]
		ok = ok and _expect(str(row["vehicle"]) == NAME_A, tag, "vehicle=" + str(row["vehicle"]))
		ok = ok and _expect(str(row["vid"]) == VID_A, tag, "vid=" + str(row["vid"]))
		ok = ok and _expect(bool(row["ok"]) and bool(row["sent"]), tag, "ok/sent 应为 true")
		ok = ok and _expect(int(row["frame_bytes"]) == FRAME_GOTO, tag,
				"frame_bytes=%d 期望 %d" % [int(row["frame_bytes"]), FRAME_GOTO])
		ok = ok and _expect(str(row["reason"]) == "", tag, "reason 应空串（实际 " + str(row["reason"]) + "）")
	# 一车一帧：只发到 VID_A
	ok = ok and _expect(k.calls.size() == 1, tag, "calls=%d 期望 1" % k.calls.size())
	if ok:
		ok = ok and _expect(str(k.calls[0]["id"]) == VID_A, tag, "send_command 的 id=" + str(k.calls[0]["id"]))
		var d: Dictionary = _decode(k.calls[0]["frame"])
		ok = ok and _expect(bool(d["ok"]), tag, "解帧失败: " + str(d["error"]))
		if ok:
			ok = ok and _expect(int(d["msgid"]) == ProtocolDef.MSGID_TASK_SET, tag, "msgid=%d" % int(d["msgid"]))
			ok = ok and _expect(int(d["compid"]) == ProtocolDef.COMPID_TERMINAL, tag, "compid=%d" % int(d["compid"]))
			ok = ok and _expect(int(d["sysid_len"]) == 0, tag, "sysid_len=%d 期望 0" % int(d["sysid_len"]))
			ok = ok and _expect(int(d["mission_count"]) == 1, tag, "mission_count=%d" % int(d["mission_count"]))
			var m: Dictionary = d["missions"][0]
			ok = ok and _expect(int(m["type"]) == ProtocolDef.MISSION_TYPE_GOTO, tag, "type=%d" % int(m["type"]))
			ok = ok and _expect(_near(float(m["x"]), 10.5) and _near(float(m["y"]), 20.25), tag,
					"解回 x/y=%f/%f 期望 10.5/20.25" % [float(m["x"]), float(m["y"])])
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑥ 两车两帧（防 targets > 1 的坑）────────────────────────

func _test_two_cars_two_frames() -> bool:
	var tag := "two_cars_two_frames"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [
		{"vehicle": NAME_A, "missions": [_goto(10.0, 10.0)]},
		{"vid": VID_B, "missions": [_goto(100.0, 120.0)]},
	])
	ok = ok and _expect(bool(r["ok"]) and r["results"].size() == 2, tag,
			"ok=%s results=%d" % [str(r["ok"]), r["results"].size()])
	ok = ok and _expect(k.calls.size() == 2, tag, "calls=%d 期望 2（一车一帧）" % k.calls.size())
	if ok:
		ok = ok and _expect(str(k.calls[0]["id"]) == VID_A and str(k.calls[1]["id"]) == VID_B, tag,
				"帧顺序应等于入参顺序: %s / %s" % [str(k.calls[0]["id"]), str(k.calls[1]["id"])])
		var f0: PackedByteArray = k.calls[0]["frame"]
		var f1: PackedByteArray = k.calls[1]["frame"]
		ok = ok and _expect(f0.size() == FRAME_GOTO and f1.size() == FRAME_GOTO, tag,
				"两帧长度 %d/%d 期望各 %d" % [f0.size(), f1.size(), FRAME_GOTO])
		# 同长但**字节不同**：这正是「同一帧被重复发给多辆车」的反面证据
		ok = ok and _expect(f0 != f1, tag, "两车两帧字节相同 —— 极可能是同一帧重发（targets>1 的坑）")
		var d0: Dictionary = _decode(f0)
		var d1: Dictionary = _decode(f1)
		ok = ok and _expect(bool(d0["ok"]) and bool(d1["ok"]), tag, "解帧失败")
		if ok and int(d0["mission_count"]) == 1 and int(d1["mission_count"]) == 1:
			var m0: Dictionary = d0["missions"][0]
			var m1: Dictionary = d1["missions"][0]
			ok = ok and _expect(_near(float(m0["x"]), 10.0) and _near(float(m0["y"]), 10.0), tag,
					"车 A 的帧 x/y=%f/%f 期望 10/10" % [float(m0["x"]), float(m0["y"])])
			ok = ok and _expect(_near(float(m1["x"]), 100.0) and _near(float(m1["y"]), 120.0), tag,
					"车 B 的帧 x/y=%f/%f 期望 100/120" % [float(m1["x"]), float(m1["y"])])
		else:
			ok = ok and _expect(false, tag, "两帧的 mission_count 不都是 1")
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑦ missions == [] → 取消帧 ───────────────────────────────

func _test_cancel_empty() -> bool:
	var tag := "cancel_empty"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": []}])
	ok = ok and _expect(bool(r["ok"]) and r["results"].size() == 1, tag,
			"ok=%s results=%d" % [str(r["ok"]), r["results"].size()])
	ok = ok and _expect(k.calls.size() == 1, tag, "calls=%d 期望 1" % k.calls.size())
	if ok:
		var frame: PackedByteArray = k.calls[0]["frame"]
		ok = ok and _expect(frame.size() == FRAME_CANCEL, tag,
				"取消帧 %d B 期望 %d B" % [frame.size(), FRAME_CANCEL])
		ok = ok and _expect(frame.hex_encode() == GOLDEN_CANCEL, tag, "取消帧金标不符: " + frame.hex_encode())
		var d: Dictionary = _decode(frame)
		ok = ok and _expect(bool(d["ok"]), tag, "解帧失败: " + str(d["error"]))
		if ok:
			ok = ok and _expect(int(d["mission_count"]) == 0, tag, "mission_count=%d 期望 0" % int(d["mission_count"]))
			ok = ok and _expect(d["missions"].is_empty(), tag, "missions 应空")
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑧ send_command 返回 false ────────────────────────────────

func _test_send_failed() -> bool:
	var tag := "send_failed"
	var k := FakeKernel.new()
	k.ret = false
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [_goto(5.0, 6.0)]}])
	ok = ok and _expect(not bool(r["ok"]), tag, "ok 应为 false")
	ok = ok and _expect(r["errors"].is_empty(), tag, "发送失败不是校验失败，errors 应空")
	ok = ok and _expect(r["results"].size() == 1, tag, "results 应有 1 条")
	if ok:
		var row: Dictionary = r["results"][0]
		ok = ok and _expect(not bool(row["ok"]), tag, "results[0].ok 应为 false")
		ok = ok and _expect(not bool(row["sent"]), tag, "results[0].sent 应为 false")
		ok = ok and _expect(str(row["reason"]) == "send_failed", tag, "reason=" + str(row["reason"]))
		ok = ok and _expect(int(row["frame_bytes"]) == FRAME_GOTO, tag,
				"帧还是拼出来了（frame_bytes=%d）" % int(row["frame_bytes"]))
	ok = ok and _expect(k.calls.size() == 1, tag, "calls=%d 期望 1（帧进过通道，只是被拒）" % k.calls.size())
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑨ bad_coord ─────────────────────────────────────────────

func _test_bad_coord() -> bool:
	var tag := "bad_coord"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var cases: Array = [
		{"type": "goto", "x": NAN, "y": 1.0},                                  # 非有限
		{"type": "goto", "x": INF, "y": 1.0},                                  # 非有限
		{"type": "goto", "x": 200.0, "y": 50.0},                               # 越界（右）
		{"type": "goto", "x": -0.1, "y": 50.0},                                # 越界（左）
		{"type": "goto", "x": 128.0, "y": 50.0},                               # 右开区间：128.0 不在世界里
		{"type": "goto", "x": 50.0, "y": -INF},                                # y 非有限
		{"type": "guard", "x": 10.0, "y": 10.0, "fx": 200.0, "fy": 10.0},      # 注视点越界
		{"type": "face", "fx": NAN, "fy": 10.0},                               # 朝向点非有限
	]
	for c in cases:
		var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [c]}])
		ok = ok and _expect_reject(r, k, "bad_coord", tag)
		if not ok:
			print("  ↑ 该用例 = ", c)
			break
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑩ 整批原子：一好一坏 → 一帧不发 ─────────────────────────

func _test_atomic_batch() -> bool:
	var tag := "atomic_batch"
	var reg = _reg_two()
	var ok := true
	# 好车在前、坏车在后
	var k1 := FakeKernel.new()
	var r1: Dictionary = Api.Dispatch(k1, reg, [
		{"vehicle": NAME_A, "missions": [_goto(10.0, 10.0)]},
		{"vehicle": "不存在的车", "missions": [_goto(20.0, 20.0)]},
	])
	ok = ok and _expect(not bool(r1["ok"]), tag, "ok 应为 false")
	ok = ok and _expect(r1["errors"].size() == 1, tag, "errors=%d 期望 1" % r1["errors"].size())
	ok = ok and _expect(r1["results"].is_empty(), tag, "results 应空（好车也不发）")
	ok = ok and _expect(k1.calls.is_empty(), tag, "混合批次却发了 %d 帧（好车被提前下发）" % k1.calls.size())
	# 坏车在前、好车在后：同样一帧不发
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Dispatch(k2, reg, [
		{"vehicle": "不存在的车", "missions": [_goto(20.0, 20.0)]},
		{"vehicle": NAME_A, "missions": [_goto(10.0, 10.0)]},
	])
	ok = ok and _expect(not bool(r2["ok"]) and r2["results"].is_empty(), tag, "倒序也应整批不发")
	ok = ok and _expect(k2.calls.is_empty(), tag, "倒序却发了 %d 帧" % k2.calls.size())
	# 两台坏车 → 两条 errors 都报出来（不 short-circuit，模型一轮能改全）
	var k3 := FakeKernel.new()
	var r3: Dictionary = Api.Dispatch(k3, reg, [
		{"vehicle": "不存在的1", "missions": [_goto(1.0, 1.0)]},
		{"vehicle": "不存在的2", "missions": [_goto(2.0, 2.0)]},
	])
	ok = ok and _expect(r3["errors"].size() == 2, tag, "errors=%d 期望 2（一次报全）" % r3["errors"].size())
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑪ 四种非 goto 类型的字节层落地 ──────────────────────────

func _test_wire_all_types() -> bool:
	var tag := "wire_all_types"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	# containment(64,64, half=2.5) / face(64,64) / guard(值守 64,64 → 注视 64,127)
	# ⚠️ 注视点用 127.0 而不是 robot_arch §8.16 金标里的 128.0：世界是**左闭右开** [0,128)
	# （§4.3-2 坐标项），128.0 会被本 API 判 bad_coord（⑨ 已单独钉住这条边界）。
	var r1: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": 2.5}]}])
	var r2: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [
		{"type": "face", "fx": 64.0, "fy": 64.0}]}])
	var r3: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [
		{"type": "guard", "x": 64.0, "y": 64.0, "fx": 64.0, "fy": 127.0}]}])
	ok = ok and _expect(bool(r1["ok"]) and bool(r2["ok"]) and bool(r3["ok"]), tag, "三次下发都应成功")
	ok = ok and _expect(k.calls.size() == 3, tag, "calls=%d 期望 3" % k.calls.size())
	if ok:
		var c: PackedByteArray = k.calls[0]["frame"]
		ok = ok and _expect(c.size() == FRAME_CONTAINMENT, tag,
				"containment 帧 %d B 期望 %d B" % [c.size(), FRAME_CONTAINMENT])
		var d: Dictionary = _decode(c)
		ok = ok and _expect(bool(d["ok"]), tag, "containment 解帧失败: " + str(d["error"]))
		if ok:
			var m: Dictionary = d["missions"][0]
			ok = ok and _expect(int(m["type"]) == ProtocolDef.MISSION_TYPE_CONTAINMENT, tag,
					"type=%d 期望 3" % int(m["type"]))
			ok = ok and _expect(_near(float(m["x"]), 64.0) and _near(float(m["y"]), 64.0), tag,
					"containment 中心 x/y 不对")
			ok = ok and _expect(_near(float(m["half_side"]), 2.5), tag, "half_side=%f 期望 2.5" % float(m["half_side"]))
	if ok:
		var f: PackedByteArray = k.calls[1]["frame"]
		ok = ok and _expect(f.hex_encode() == GOLDEN_FACE_64, tag, "face 整帧金标不符: " + f.hex_encode())
		var d2: Dictionary = _decode(f)
		ok = ok and _expect(bool(d2["ok"]), tag, "face 解帧失败: " + str(d2["error"]))
		if ok:
			var m2: Dictionary = d2["missions"][0]
			ok = ok and _expect(int(m2["type"]) == ProtocolDef.MISSION_TYPE_FACE, tag, "type=%d 期望 4" % int(m2["type"]))
			ok = ok and _expect(_near(float(m2["x"]), 64.0) and _near(float(m2["y"]), 64.0), tag,
					"face 的 fx/fy 没落到 x/y 键上: %f/%f" % [float(m2["x"]), float(m2["y"])])
	if ok:
		var g: PackedByteArray = k.calls[2]["frame"]
		ok = ok and _expect(g.size() == FRAME_GUARD, tag, "guard 帧 %d B 期望 %d B" % [g.size(), FRAME_GUARD])
		var d3: Dictionary = _decode(g)
		ok = ok and _expect(bool(d3["ok"]), tag, "guard 解帧失败: " + str(d3["error"]))
		if ok:
			var m3: Dictionary = d3["missions"][0]
			ok = ok and _expect(int(m3["type"]) == ProtocolDef.MISSION_TYPE_GUARD, tag, "type=%d 期望 5" % int(m3["type"]))
			ok = ok and _expect(_near(float(m3["x"]), 64.0) and _near(float(m3["y"]), 64.0), tag, "guard 值守点不对")
			ok = ok and _expect(_near(float(m3["fx"]), 64.0) and _near(float(m3["fy"]), 127.0), tag,
					"guard 注视点 fx/fy=%f/%f 期望 64/127" % [float(m3["fx"]), float(m3["fy"])])
	# 多任务同帧：[Goto, Face] → 19 B payload → 31 B 帧
	var k4 := FakeKernel.new()
	var r4: Dictionary = Api.Dispatch(k4, reg, [{"vehicle": NAME_A, "missions": [
		{"type": "goto", "x": 64.0, "y": 64.0},
		{"type": "face", "fx": 64.0, "fy": 64.0},
	]}])
	ok = ok and _expect(bool(r4["ok"]) and k4.calls.size() == 1, tag, "[Goto, Face] 应合成一帧")
	if k4.calls.size() == 1:
		var gf: PackedByteArray = k4.calls[0]["frame"]
		ok = ok and _expect(gf.size() == 12 + 19, tag, "两条任务一帧 %d B 期望 %d B" % [gf.size(), 12 + 19])
		var d4: Dictionary = _decode(gf)
		ok = ok and _expect(bool(d4["ok"]) and int(d4["mission_count"]) == 2, tag, "mission_count 应为 2")
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑫ 返回结构（3 / 6 / 2 键）+ ok 语义 ────────────────────

func _test_envelope_shape() -> bool:
	var tag := "envelope_shape"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [{"vehicle": NAME_A, "missions": [_goto(1.0, 2.0)]}])
	ok = ok and _expect(r.size() == 3, tag, "顶层键数=%d 期望 3（%s）" % [r.size(), str(r.keys())])
	for key: String in ["ok", "results", "errors"]:
		ok = ok and _expect(r.has(key), tag, "顶层缺键 " + key)
	ok = ok and _expect(r["results"].size() == 1, tag, "results 应有 1 条")
	if ok:
		var row: Dictionary = r["results"][0]
		var want := ["vehicle", "vid", "ok", "sent", "frame_bytes", "reason"]
		ok = ok and _expect(row.size() == want.size(), tag,
				"results 行键数=%d 期望 %d（%s）" % [row.size(), want.size(), str(row.keys())])
		for key: String in want:
			ok = ok and _expect(row.has(key), tag, "results 行缺键 " + key)
	# errors 行 2 键
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Dispatch(k2, reg, [{"vehicle": "不存在", "missions": [_goto(1.0, 2.0)]}])
	ok = ok and _expect(r2["errors"].size() == 1, tag, "errors 应有 1 条")
	if r2["errors"].size() == 1:
		var er: Dictionary = r2["errors"][0]
		ok = ok and _expect(er.size() == 2, tag, "errors 行键数=%d 期望 2（%s）" % [er.size(), str(er.keys())])
		ok = ok and _expect(er.has("vehicle") and er.has("reason"), tag, "errors 行缺键")
	# ok 语义：两车都成功才 true
	var k3 := FakeKernel.new()
	var r3: Dictionary = Api.Dispatch(k3, reg, [
		{"vehicle": NAME_A, "missions": [_goto(1.0, 2.0)]},
		{"vehicle": NAME_B, "missions": [_goto(3.0, 4.0)]},
	])
	ok = ok and _expect(bool(r3["ok"]) and r3["results"].size() == 2 and k3.calls.size() == 2, tag,
			"两车都成功时 ok 应为 true（ok=%s results=%d calls=%d）" % [
				str(r3["ok"]), r3["results"].size(), k3.calls.size()])
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑬ kernel 未就绪 + reason 优先级 ─────────────────────────

func _test_kernel_not_ready() -> bool:
	var tag := "kernel_not_ready"
	var reg = _reg_two()
	var ok := true
	var tasks: Array = [{"vehicle": NAME_A, "missions": [_goto(1.0, 2.0)]}]
	# ① null
	var r1: Dictionary = Api.Dispatch(null, reg, tasks)
	ok = ok and _expect(not bool(r1["ok"]) and r1["errors"].size() == 1, tag, "kernel=null 应报 1 条错")
	if r1["errors"].size() == 1:
		ok = ok and _expect(str(r1["errors"][0]["reason"]) == "kernel_not_ready", tag,
				"reason=" + str(r1["errors"][0]["reason"]))
	ok = ok and _expect(r1["results"].is_empty(), tag, "kernel 未就绪时不该有 results")
	# ② 有对象但没有 send_command（鸭子类型不过关）
	var no_send := RefCounted.new()
	var r2: Dictionary = Api.Dispatch(no_send, reg, tasks)
	ok = ok and _expect(r2["errors"].size() == 1 and str(r2["errors"][0]["reason"]) == "kernel_not_ready", tag,
			"无 send_command 的对象应判 kernel_not_ready")
	# ③ 优先级：车不存在 > kernel 未就绪（文档 §4.3-2 表格的顺序）
	var r3: Dictionary = Api.Dispatch(null, reg, [{"vehicle": "不存在", "missions": [_goto(1.0, 2.0)]}])
	ok = ok and _expect(str(r3["errors"][0]["reason"]) == "unknown_vehicle", tag,
			"车不存在应优先于 kernel_not_ready（实际 " + str(r3["errors"][0]["reason"]) + "）")
	# ④ 优先级：类型非法 > kernel 未就绪
	var r4: Dictionary = Api.Dispatch(null, reg,
			[{"vehicle": NAME_A, "missions": [{"type": "gurad", "x": 1.0, "y": 2.0}]}])
	ok = ok and _expect(str(r4["errors"][0]["reason"]) == "unknown_type", tag,
			"类型非法应优先于 kernel_not_ready（实际 " + str(r4["errors"][0]["reason"]) + "）")
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑭ Dispatch_One（与 Dispatch 同形）───────────────────────

func _test_dispatch_one() -> bool:
	var tag := "dispatch_one"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch_One(k, reg, NAME_A, [_goto(5.0, 6.0)])
	ok = ok and _expect(bool(r["ok"]) and r["results"].size() == 1 and r["errors"].is_empty(), tag,
			"单车入口返回形状不对（ok=%s results=%d）" % [str(r["ok"]), r["results"].size()])
	if ok:
		ok = ok and _expect(str(r["results"][0]["vid"]) == VID_A, tag, "vid=" + str(r["results"][0]["vid"]))
		ok = ok and _expect(int(r["results"][0]["frame_bytes"]) == FRAME_GOTO, tag, "frame_bytes 不对")
	ok = ok and _expect(k.calls.size() == 1, tag, "calls=%d 期望 1" % k.calls.size())
	if k.calls.size() == 1:
		var d: Dictionary = _decode(k.calls[0]["frame"])
		ok = ok and _expect(bool(d["ok"]) and _near(float(d["missions"][0]["x"]), 5.0), tag, "解帧的 x 不是 5")
	# 未知车：同样是 errors 一条、一帧不发
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Dispatch_One(k2, reg, "不存在", [_goto(5.0, 6.0)])
	ok = ok and _expect_reject(r2, k2, "unknown_vehicle", tag)
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑮ Cancel（按名 / 按 vid / 空数组 no-op）─────────────────

func _test_cancel_api() -> bool:
	var tag := "cancel_api"
	var reg = _reg_two()
	var ok := true
	var k := FakeKernel.new()
	var r: Dictionary = Api.Cancel(k, reg, [NAME_A, VID_B])
	ok = ok and _expect(bool(r["ok"]) and r["results"].size() == 2, tag,
			"Cancel 两车应成功（ok=%s results=%d）" % [str(r["ok"]), r["results"].size()])
	ok = ok and _expect(k.calls.size() == 2, tag, "calls=%d 期望 2（一车一帧取消）" % k.calls.size())
	if ok:
		ok = ok and _expect(str(k.calls[0]["id"]) == VID_A and str(k.calls[1]["id"]) == VID_B, tag,
				"取消帧的目标顺序不对: %s / %s" % [str(k.calls[0]["id"]), str(k.calls[1]["id"])])
		var c0: PackedByteArray = k.calls[0]["frame"]
		var c1: PackedByteArray = k.calls[1]["frame"]
		ok = ok and _expect(c0.size() == FRAME_CANCEL and c1.size() == FRAME_CANCEL, tag, "取消帧长度不对")
		ok = ok and _expect(c0.hex_encode() == GOLDEN_CANCEL and c1.hex_encode() == GOLDEN_CANCEL, tag,
				"取消帧金标不符")
		var d: Dictionary = _decode(c0)
		ok = ok and _expect(bool(d["ok"]) and int(d["mission_count"]) == 0, tag, "取消帧解回 mission_count 应 0")
	# 未知车
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Cancel(k2, reg, ["不存在的车"])
	ok = ok and _expect_reject(r2, k2, "unknown_vehicle", tag)
	# 空数组 = no-op（保守：不把全队停车）
	var k3 := FakeKernel.new()
	var r3: Dictionary = Api.Cancel(k3, reg, [])
	ok = ok and _expect(bool(r3["ok"]) and r3["results"].is_empty() and r3["errors"].is_empty(), tag,
			"Cancel([]) 应是 ok 的空操作")
	ok = ok and _expect(k3.calls.is_empty(), tag, "Cancel([]) 不该发帧（实际 %d 帧）" % k3.calls.size())
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑯ 参数形态 + 与注册表解耦 ───────────────────────────────

func _test_args_and_decoupling() -> bool:
	var tag := "args_and_decoupling"
	var reg = _reg_two()
	var ok := true
	# ① 缺 missions 键 ≠ missions: []（后者是取消，前者是参数错）
	var k1 := FakeKernel.new()
	var r1: Dictionary = Api.Dispatch(k1, reg, [{"vehicle": NAME_A}])
	ok = ok and _expect_reject(r1, k1, "bad_args", tag)
	# ② missions 不是数组
	var k2 := FakeKernel.new()
	var r2: Dictionary = Api.Dispatch(k2, reg, [{"vehicle": NAME_A, "missions": "goto"}])
	ok = ok and _expect_reject(r2, k2, "bad_args", tag)
	# ③ missions 超过 u8 上限（> 255）：宁拒不错发（Encode_Task_Set 会静默截断）
	var many: Array = []
	for i in range(256):
		many.append(_goto(1.0, 1.0))
	var k3 := FakeKernel.new()
	var r3: Dictionary = Api.Dispatch(k3, reg, [{"vehicle": NAME_A, "missions": many}])
	ok = ok and _expect_reject(r3, k3, "bad_args", tag)
	# ④ 恰好 255 条要**能发**（边界另一侧）
	var k4 := FakeKernel.new()
	var r4: Dictionary = Api.Dispatch(k4, reg, [{"vehicle": NAME_A, "missions": many.slice(0, 255)}])
	ok = ok and _expect(bool(r4["ok"]) and k4.calls.size() == 1, tag,
			"255 条应能发（ok=%s calls=%d）" % [str(r4["ok"]), k4.calls.size()])
	if k4.calls.size() == 1:
		var d: Dictionary = _decode(k4.calls[0]["frame"])
		ok = ok and _expect(bool(d["ok"]) and int(d["mission_count"]) == 255, tag,
				"255 条解回 mission_count=%d" % int(d.get("mission_count", -1)))
	# ⑤ 只读 vehicles：假表里只有 name（没有位姿键），照样能下发
	var table := FakeTable.new()
	table.vehicles[VID_A] = {"name": NAME_A}
	var k5 := FakeKernel.new()
	var r5: Dictionary = Api.Dispatch(k5, table, [{"vehicle": NAME_A, "missions": [_goto(9.0, 9.0)]}])
	ok = ok and _expect(bool(r5["ok"]) and k5.calls.size() == 1, tag,
			"只有 vehicles 的假表应可用（ok=%s calls=%d）" % [str(r5["ok"]), k5.calls.size()])
	if r5["results"].size() == 1:
		ok = ok and _expect(str(r5["results"][0]["vid"]) == VID_A, tag, "假表解析出的 vid 不对")
	# ⑥ 空 tasks = 什么都不做（不是取消）
	var k6 := FakeKernel.new()
	var r6: Dictionary = Api.Dispatch(k6, reg, [])
	ok = ok and _expect(bool(r6["ok"]) and r6["results"].is_empty() and r6["errors"].is_empty(), tag,
			"空 tasks 应是 ok 的空操作")
	ok = ok and _expect(k6.calls.is_empty(), tag, "空 tasks 不该发帧（实际 %d 帧）" % k6.calls.size())
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑰ 替换语义：同车两项 → 后帧覆盖前帧 ─────────────────────

func _test_replace_semantics() -> bool:
	var tag := "replace_semantics"
	var k := FakeKernel.new()
	var reg = _reg_two()
	var ok := true
	var r: Dictionary = Api.Dispatch(k, reg, [
		{"vehicle": NAME_A, "missions": [_goto(10.0, 10.0)]},
		{"vehicle": NAME_A, "missions": [_goto(20.0, 20.0)]},
	])
	ok = ok and _expect(r["results"].size() == 2, tag,
			"同一车两项应各出一条 results（实际 %d）" % r["results"].size())
	ok = ok and _expect(k.calls.size() == 2, tag, "calls=%d 期望 2" % k.calls.size())
	if ok:
		var d0: Dictionary = _decode(k.calls[0]["frame"])
		var d1: Dictionary = _decode(k.calls[1]["frame"])
		ok = ok and _expect(bool(d0["ok"]) and bool(d1["ok"]), tag, "解帧失败")
		if ok:
			ok = ok and _expect(_near(float(d0["missions"][0]["x"]), 10.0), tag, "第一帧 x 应为 10")
			ok = ok and _expect(_near(float(d1["missions"][0]["x"]), 20.0), tag, "第二帧 x 应为 20")
			ok = ok and _expect(int(d1["mission_count"]) == 1, tag,
					"第二帧是**整队替换**：只含 1 条，不是追加成 2 条")
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok
