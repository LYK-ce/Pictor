extends Node
## Presented by KeJi
## Date ： 2026-09-01
## Modified Date ： 2026-11-05
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
## targets = 目标车辆列表（hex vehicle_id）；TASK_SET 一帧一车，targets 只应有 1 个元素（task_36 §12.7）
signal cmd_send(targets: Array[String], cmd: Dictionary)
## UAV 协助请求（msgid 7）：requester_id = 请求者 sysid（hex）；x/y = 目标世界坐标（米）
signal assist_request_received(requester_id: String, x: float, y: float)
## X 键随访（task_48 Step 4.7）：vehicle_id = 被随访的车；**只发「进入随访」**，取消不发本信号
signal follow_requested(vehicle_id: String)
signal cells_changed(updates: Array)
signal goto_issued(x: float, y: float)
signal mode_transited(mode: int)
signal audio_record_started
signal audio_record_finished
## 录音结束、内存拼好 wav 后由 AudioInput 发出，STT 接收后上传转录
signal audio_captured(wav_bytes: PackedByteArray)
signal command_requested(text: String)
## 命令通道：用户下发内核命令字符串（如 "session create xxx" / "api 1"），KernelBridge 转发给内核
signal user_command_requested(command_line: String)
## 屏上日志面板：text=内容，level=info/warn/error（面板据此上色；导出后替代 print 作为语音/LLM 管线状态提示）
signal log_message(text: String, level: String)
