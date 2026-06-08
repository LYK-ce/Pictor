extends Node3D
## Present by KeJi
## Date: 2026-06-08
##
## MapContainer3D — 体素地图存储与 MultiMeshInstance3D 渲染

const STATE_COLORS := {
	0: Color(0.25, 0.25, 0.25),  # gray
	1: Color(0.0, 0.0, 0.0),     # black
	2: Color(1.0, 1.0, 1.0),     # white
}

@onready var _mmi := $MultiMeshInstance3D as MultiMeshInstance3D

var _map: Dictionary = {}  # _map[gx][gy][gz] = {"state","conf","ts","source"}
var _index_map: Dictionary = {}  # {(gx,gy,gz): instance_index}


func _ready() -> void:
	_setup_multimesh()


func _setup_multimesh() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	mm.visible_instance_count = 0

	_mmi.multimesh = mm
	_mmi.material_override = StandardMaterial3D.new()


func _ensure_instance_count(n: int) -> void:
	var mm := _mmi.multimesh
	if mm.instance_count < n:
		mm.instance_count = n
		mm.visible_instance_count = n


func _set_instance(idx: int, gx: int, gy: int, gz: int, state: int) -> void:
	var mm := _mmi.multimesh
	var t := Transform3D(Basis(), Vector3(gx, gy, gz))
	mm.set_instance_transform(idx, t)
	# 每个实例用不同 material 需要在 MultiMeshInstance3D 层面处理
	# 目前统一用白色 material_override，后续优化


func set_cell(gx: int, gy: int, gz: int, data: Dictionary) -> void:
	var key := Vector3i(gx, gy, gz)
	if _index_map.has(key):
		return  # 已存在，仅更新数据

	if not _map.has(gx):
		_map[gx] = {}
	if not _map[gx].has(gy):
		_map[gx][gy] = {}
	_map[gx][gy][gz] = data

	var idx := _index_map.size()
	_index_map[key] = idx
	_ensure_instance_count(idx + 1)
	_set_instance(idx, gx, gy, gz, data.get("state", 0))


func set_full(voxels: Array) -> void:
	_map.clear()
	_index_map.clear()
	for v in voxels:
		set_cell(v.get("gx", 0), v.get("gy", 0), v.get("gz", 0), {
			"state": v.get("state", 0),
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		})


func set_delta(voxels: Array) -> void:
	for v in voxels:
		set_cell(v.get("gx", 0), v.get("gy", 0), v.get("gz", 0), {
			"state": v.get("state", 0),
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		})


func get_cell(gx: int, gy: int, gz: int) -> Dictionary:
	if _map.has(gx) and _map[gx].has(gy) and _map[gx][gy].has(gz):
		return _map[gx][gy][gz]
	return {"state": 0, "conf": 0.0}


func get_all_cells() -> Array:
	var cells: Array = []
	for gx in _map:
		for gy in _map[gx]:
			for gz in _map[gx][gy]:
				var d: Dictionary = _map[gx][gy][gz]
				cells.append({"gx": gx, "gy": gy, "gz": gz, "state": d.get("state"), "conf": d.get("conf")})
	return cells
