extends Node
## Presented by KeJi
## Date ： 2026-09-01
##
## EventBus — 全局事件总线（Autoload 单例）

signal pose_received(vehicle_id: String, pose: Dictionary)
## 收到某车接入上报的 own 整表（FULL）。vehicle_id 暂未用于合并（多车合并暂缓）。
signal map_full_received(vehicle_id: String, chunk_x: int, chunk_y: int, cells: PackedByteArray)
signal map_delta_received(voxels: Array)
signal chunk_updated(chunk_x: int, chunk_y: int)
signal vehicle_registered(vehicle_id: String)
signal vehicle_unregistered(vehicle_id: String)
## 桥透传的节点名 + 节点类型（peer_info_updated），面板据此显示车名与类型
signal peer_info_updated(vehicle_id: String, peer_name: String, node_type: String)
signal selection_changed(id: String)
## targets = 目标车辆列表（hex vehicle_id）；TASK_SET 的 members 由 KernelBridge 按 targets 填充
signal cmd_send(targets: Array[String], cmd: Dictionary)
signal cells_changed(updates: Array)
signal goto_issued(x: float, y: float)
signal mode_transited(mode: int)
signal audio_record_started
signal audio_record_finished
## 录音结束、内存拼好 wav 后由 AudioInput 发出，STT 接收后上传转录
signal audio_captured(wav_bytes: PackedByteArray)
signal command_requested(text: String)
## 屏上日志面板：text=内容，level=info/warn/error（面板据此上色；导出后替代 print 作为语音/LLM 管线状态提示）
signal log_message(text: String, level: String)
