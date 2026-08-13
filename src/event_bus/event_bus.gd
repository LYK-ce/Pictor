extends Node
## Presented by KeJi
## Date ： 2026-08-12
##
## EventBus — 全局事件总线（Autoload 单例）

signal pose_received(vehicle_id: String, pose: Dictionary)
## 收到某车接入上报的 own 整表（FULL）。vehicle_id 用于路由返还（阶段 2 多车聚合）。
signal map_full_received(vehicle_id: String, chunk_x: int, chunk_y: int, cells: PackedByteArray)
signal map_delta_received(voxels: Array)
## 本地合并表完成一次 own FULL 聚合后发出（载荷 = 聚合后的合并表快照），驱动返还下发。
signal map_merged(vehicle_id: String, chunk_x: int, chunk_y: int, cells: PackedByteArray)
signal chunk_updated(chunk_x: int, chunk_y: int)
signal ws_connected
signal ws_connect_requested(url: String)
signal ws_disconnect_requested(vehicle_id: String)
signal vehicle_registered(vehicle_id: String, url: String)
signal vehicle_unregistered(vehicle_id: String)
signal selection_changed(id: String)
## Task 22：targets = 目标车辆列表（显式收件人，单车为 1 元素）；TASK_SET 的 members 由 WebSocketManager 按 targets 查表填充
signal cmd_send(targets: Array[String], cmd: Dictionary)
signal cells_changed(updates: Array)
signal goto_issued(x: float, y: float)
signal mode_transited(mode: int)
signal audio_record_started
signal audio_record_finished
signal command_requested(text: String)
