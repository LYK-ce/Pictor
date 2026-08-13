extends Node
## Presented by KeJi
## Date ： 2026-08-12
##
## 两车接入握手 e2e（场景模式，EventBus autoload 可用）— Task 21 阶段 2
## 链路：CarA(:9090, variant0) → own 上报 → Pictor 聚合 → 返还 ownA
##       CarB(:9091, variant1) → own 上报 → Pictor 聚合 → 返还 clamp(ownA+ownB)
## 用法: godot --headless --path . res://src/test/test_e2e_multivehicle.tscn
##
## 确定性图：variant0 = 上/下边界 +8 + 中央空地(120~135) −8
##            variant1 = 左/右边界 +8 + 中央空地(40~55) −8
## 重叠格 (0,0) 均为 +8 → 断言 clamp(8+8)=8（非 16）

const URL_A := "ws://127.0.0.1:9090"
const URL_B := "ws://127.0.0.1:9091"
const TIMEOUT := 20.0

@onready var car_a: Node = $CarA
@onready var car_b: Node = $CarB
@onready var map_data: Node = $MapData2D

enum Phase { CONNECT_A, WAIT_A, CONNECT_B, WAIT_B, GROUP, GROUP_WAIT, SINGLE, SINGLE_WAIT }

var _phase := Phase.CONNECT_A
var _phase_t := 0.0
var _failures: Array[String] = []


var _g: Dictionary = {}   # 群发/单车阶段的前置计数


func _ready() -> void:
	print("[E2E-MV] starting (CarA :9090 variant0 / CarB :9091 variant1)")


func _process(delta: float) -> void:
	_phase_t += delta
	match _phase:
		Phase.CONNECT_A:
			EventBus.ws_connect_requested.emit(URL_A)
			_phase = Phase.WAIT_A
			_phase_t = 0.0
			print("[E2E-MV] connect A")
		Phase.WAIT_A:
			if car_a.get_full_rx_count() >= 1:
				_Check_Phase_A()
				_phase = Phase.CONNECT_B
				_phase_t = 0.0
				print("[E2E-MV] A got merged FULL → connect B")
			elif _phase_t > TIMEOUT:
				_Fail("A timeout waiting merged FULL")
				_Finish()
		Phase.CONNECT_B:
			EventBus.ws_connect_requested.emit(URL_B)
			_phase = Phase.WAIT_B
			_phase_t = 0.0
			print("[E2E-MV] connect B")
		Phase.WAIT_B:
			if car_b.get_full_rx_count() >= 1:
				_Check_Phase_B()
				_phase = Phase.GROUP
				_phase_t = 0.0
				print("[E2E-MV] map merge done → group task test")
			elif _phase_t > TIMEOUT:
				_Fail("B timeout waiting merged FULL")
				_Finish()
		Phase.GROUP:
			# Task 22：群发 TASK_SET 给两车（members=[car_a, car_b]），两车都应收到
			var before_a: int = car_a.get_task_rx_count()
			var before_b: int = car_b.get_task_rx_count()
			EventBus.cmd_send.emit(["car_a", "car_b"] as Array[String],
				MessageBuilder.build_auto_push_goto(10.0, 10.0))
			_phase = Phase.GROUP_WAIT
			_phase_t = 0.0
			_g = {"before_a": before_a, "before_b": before_b}
		Phase.GROUP_WAIT:
			if car_a.get_task_rx_count() > _g.before_a and car_b.get_task_rx_count() > _g.before_b:
				print("[E2E-MV] group task received by both ✓")
				_phase = Phase.SINGLE
				_phase_t = 0.0
			elif _phase_t > 5.0:
				_Fail("group task not received by both: a=%d b=%d" % [car_a.get_task_rx_count(), car_b.get_task_rx_count()])
				_Finish()
		Phase.SINGLE:
			# 单车任务（members=[car_a]）：car_a 收到，car_b 非成员忽略
			var before_a: int = car_a.get_task_rx_count()
			var before_b: int = car_b.get_task_rx_count()
			EventBus.cmd_send.emit(["car_a"] as Array[String],
				MessageBuilder.build_auto_push_goto(20.0, 20.0))
			_phase = Phase.SINGLE_WAIT
			_phase_t = 0.0
			_g = {"before_a": before_a, "before_b": before_b}
		Phase.SINGLE_WAIT:
			if car_a.get_task_rx_count() > _g.before_a:
				if car_b.get_task_rx_count() == _g.before_b:
					print("[E2E-MV] single task: car_a only ✓ (car_b ignored as non-member)")
					_Finish()
				else:
					_Fail("car_b received single-car task (should ignore): b=%d" % car_b.get_task_rx_count())
					_Finish()
			elif _phase_t > 5.0:
				_Fail("single task not received by car_a")
				_Finish()


# ─── 断言 ─────────────────────────────────────────────────────

## Phase A：首车返还 = ownA（merged 替换为 ownA，own 保留不变）
func _Check_Phase_A() -> void:
	var merged: PackedByteArray = car_a.get_merged_cells()
	var own: PackedByteArray = car_a.get_own_cells()
	if merged.size() != 65536 or own.size() != 65536:
		_Fail("A merged/own size mismatch")
		return
	if merged != own:
		_Fail("A merged != own (first-car return should equal ownA)")
	# MapData2D 表 == variant0 图（抽样）
	var md: PackedByteArray = map_data.get_chunk_cells(0, 0)
	if md.size() != 65536:
		_Fail("A MapData2D table empty")
		return
	_Assert_Cell("A", md, 0, 0, 8)        # 上边界墙
	_Assert_Cell("A", md, 130, 130, -8)   # 中央空地
	_Assert_Cell("A", md, 10, 10, 0)      # 未知
	_Assert_Cell("A", md, 0, 100, 0)      # variant0 无左墙
	print("[E2E-MV] Phase A PASS: merged==own, table==variant0")


## Phase B：返还 = clamp(ownA + ownB)（重叠格 clamp、A-only/B-only 区分）
func _Check_Phase_B() -> void:
	var merged: PackedByteArray = car_b.get_merged_cells()
	if merged.size() != 65536:
		_Fail("B merged size mismatch")
		return
	_Assert_Cell("B", merged, 0, 0, 8)      # 8+8 → clamp 8（非 16）
	_Assert_Cell("B", merged, 100, 0, 8)    # A-only 上边界
	_Assert_Cell("B", merged, 0, 100, 8)    # B-only 左边界
	_Assert_Cell("B", merged, 130, 130, -8) # A 中央空地
	_Assert_Cell("B", merged, 48, 48, -8)   # B 中央空地
	_Assert_Cell("B", merged, 10, 10, 0)    # 双 0
	# 终端表 == B 收到的返还（逐字节一致）
	var md: PackedByteArray = map_data.get_chunk_cells(0, 0)
	if md != merged:
		_Fail("MapData2D table != merged returned to B")
	print("[E2E-MV] Phase B PASS: merged==clamp(ownA+ownB), terminal table matches")


func _Assert_Cell(tag: String, map: PackedByteArray, gx: int, gy: int, expect: int) -> void:
	var v := ChunkData2D.to_i8(map[gy * 256 + gx])
	if v != expect:
		_Fail("%s cell(%d,%d) = %d (expect %d)" % [tag, gx, gy, v, expect])


func _Fail(msg: String) -> void:
	_failures.append(msg)
	print("[E2E-MV] FAIL: ", msg)


func _Finish() -> void:
	var ok := _failures.is_empty()
	print("=== E2E-MV result: ", "PASS" if ok else "FAIL", " ===")
	if not _failures.is_empty():
		for f in _failures:
			print("  FAIL: ", f)
	get_tree().quit(0 if ok else 1)
