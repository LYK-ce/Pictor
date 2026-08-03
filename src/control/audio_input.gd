## Presented by KeJi
## Date ： 2026-08-03
##
## AudioInput — 麦克风输入节点（AudioStreamPlayer）
## 通过 EventBus 信号控制录音：
##   audio_record_started  → 开始录音
##   audio_record_finished → 结束录音并保存到项目目录
## 依赖：default_bus_layout.tres 中的 Record bus（AudioEffectRecord）

extends AudioStreamPlayer

## 录音输出目录（项目目录内）
const RECORD_DIR := "res://recordings/"

## Record bus 上的 AudioEffectRecord 效果器
var record_effect: AudioEffectRecord


func _ready() -> void:
	var idx := AudioServer.get_bus_index("Record")
	record_effect = AudioServer.get_bus_effect(idx, 0)
	EventBus.audio_record_started.connect(_On_Record_Started)
	EventBus.audio_record_finished.connect(_On_Record_Finished)


## 开始录音
func _On_Record_Started() -> void:
	if record_effect == null:
		return
	record_effect.set_recording_active(true)
	print("[AudioInput] recording started")


## 结束录音并保存到项目目录（时间戳文件名，保持录制原始格式）
func _On_Record_Finished() -> void:
	if record_effect == null:
		return
	record_effect.set_recording_active(false)
	var recording: AudioStreamWAV = record_effect.get_recording()
	if recording == null:
		printerr("[AudioInput] no recording data (microphone not ready?)")
		return
	# 不修改 mix_rate/format/stereo，保持录制原始格式
	var timestamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := RECORD_DIR + "record_" + timestamp + ".wav"
	DirAccess.make_dir_recursive_absolute(RECORD_DIR)
	recording.save_to_wav(path)
	print("[AudioInput] saved: %s (%d bytes, %d Hz, %s)" % [
		path, recording.get_data().size(), recording.mix_rate,
		"mono" if not recording.stereo else "stereo"])
