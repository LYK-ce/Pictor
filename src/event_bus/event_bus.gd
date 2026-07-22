extends Node
## Present by KeJi
## Date: 2026-06-08
##
## EventBus — 全局事件总线（Autoload 单例）

signal pose_received(vehicle_id: String, pose: Dictionary)
signal map_full_received(chunk_x: int, chunk_y: int, cells: PackedByteArray)
signal map_delta_received(voxels: Array)
signal chunk_updated(chunk_x: int, chunk_y: int)
signal ws_connected
signal ws_connect_requested(url: String)
signal ws_disconnect_requested(vehicle_id: String)
signal vehicle_registered(vehicle_id: String, url: String)
signal vehicle_unregistered(vehicle_id: String)
signal vehicle_control_changed(vehicle_id: String)
signal cmd_send(vehicle_id: String, cmd: Dictionary)
