## Presented by KeJi
## Date ： 2026-08-31
##
## VehicleRegistry — 车辆注册表（单一数据源）
## 订阅 EventBus 车辆信号，维护 {vehicle_id → {name, x, y, yaw}}，供 LLM 编排读取上下文。

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
	vehicles[vehicle_id] = {"name": "", "x": 0.0, "y": 0.0, "yaw": 0.0}


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
	vehicles[vehicle_id]["yaw"] = float(pose.get("yaw", 0.0))


## 按车名反查 vehicle_id（未找到返回 ""）
func get_id_by_name(vehicle_name: String) -> String:
	for id: String in vehicles:
		if str(vehicles[id].get("name", "")) == vehicle_name:
			return id
	return ""
