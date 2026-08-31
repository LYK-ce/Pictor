## Presented by KeJi
## Date ： 2026-08-31
##
## VehicleRegistry — 车辆注册表（单一数据源）
## 订阅 EventBus 车辆信号，维护 {vehicle_id → {name, x, y}}，供 LLM 编排读取上下文。
## mock 车辆仅用于无真车时的联调测试（MOCK_ENABLED 控制，真车测试前关闭/删除）。

class_name VehicleRegistry
extends Node

## 是否注册 mock 车辆（真车测试前设为 false）
const MOCK_ENABLED := true

## {vehicle_id → {name: String, x: float, y: float}}
var vehicles: Dictionary = {}


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	EventBus.peer_info_updated.connect(_on_peer_info_updated)
	EventBus.pose_received.connect(_on_pose)
	if MOCK_ENABLED:
		_add_mock_vehicles()
		print("[VehicleRegistry] mock 车辆已注册: ", vehicles.keys())


func _on_vehicle_registered(vehicle_id: String) -> void:
	if vehicles.has(vehicle_id):
		return
	vehicles[vehicle_id] = {"name": "", "x": 0.0, "y": 0.0}


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	vehicles.erase(vehicle_id)


func _on_peer_info_updated(vehicle_id: String, peer_name: String) -> void:
	if vehicles.has(vehicle_id) and not peer_name.is_empty():
		vehicles[vehicle_id]["name"] = peer_name


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	if not vehicles.has(vehicle_id):
		return
	vehicles[vehicle_id]["x"] = float(pose.get("x", 0.0))
	vehicles[vehicle_id]["y"] = float(pose.get("y", 0.0))


## 按车名反查 vehicle_id（未找到返回 ""）
func get_id_by_name(vehicle_name: String) -> String:
	for id: String in vehicles:
		if str(vehicles[id].get("name", "")) == vehicle_name:
			return id
	return ""


## mock 车辆（测试用，真车测试前删除）
func _add_mock_vehicles() -> void:
	vehicles["mock_a"] = {"name": "小车A", "x": 0.0, "y": 0.0}
	vehicles["mock_b"] = {"name": "小车B", "x": 3.0, "y": 0.0}
	vehicles["mock_c"] = {"name": "小车C", "x": 0.0, "y": 3.0}
