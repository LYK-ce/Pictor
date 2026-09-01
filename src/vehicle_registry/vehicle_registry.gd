## Presented by KeJi
## Date ： 2026-09-01
##
## VehicleRegistry — 车辆注册表（单一数据源）
## 订阅 EventBus 车辆信号，维护 {vehicle_id → {name, x, y, yaw, node_type}}，供 LLM 编排读取上下文。

class_name VehicleRegistry
extends Node

## {vehicle_id → {name: String, x: float, y: float, yaw: float}}
var vehicles: Dictionary = {}


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	EventBus.peer_info_updated.connect(_on_peer_info_updated)
	EventBus.pose_received.connect(_on_pose)

	


func _on_vehicle_registered(vehicle_id: String) -> void:
	if vehicles.has(vehicle_id):
		return
	vehicles[vehicle_id] = {"name": "", "x": 0.0, "y": 0.0, "yaw": 0.0, "node_type": ""}


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	vehicles.erase(vehicle_id)


func _on_peer_info_updated(vehicle_id: String, peer_name: String, node_type: String) -> void:
	if not vehicles.has(vehicle_id):
		return
	if not peer_name.is_empty():
		vehicles[vehicle_id]["name"] = peer_name
	if not node_type.is_empty():
		vehicles[vehicle_id]["node_type"] = node_type


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	if not vehicles.has(vehicle_id):
		return
	vehicles[vehicle_id]["x"] = float(pose.get("x", 0.0))
	vehicles[vehicle_id]["y"] = float(pose.get("y", 0.0))
	vehicles[vehicle_id]["yaw"] = float(pose.get("yaw", 0.0))


## 按车名反查 vehicle_id（未找到返回 ""）
func get_id_by_name(vehicle_name: String) -> String:
	for id: String in vehicles:
		if str(vehicles[id].get("name", "")) == vehicle_name:
			return id
	return ""


## mock 车辆接口（测试用）：手动塞一辆假车进注册表，供 STT/LLM 无真车联调。
## 注意：不在 _ready 里调用，需要时由外部（测试脚本/调试）手动调用。
func add_mock_vehicle(vehicle_id: String, vehicle_name: String) -> void:
	vehicles[vehicle_id] = {"name": vehicle_name, "x": 0.0, "y": 0.0, "yaw": 0.0, "node_type": ""}
