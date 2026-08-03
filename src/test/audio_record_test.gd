## Presented by KeJi
## Date ： 2026-08-03
##
## AudioRecordTest — 麦克风录音测试
## 按住 Record 按钮开始录音，松开后停止并自动播放
## 依赖：default_bus_layout.tres 中的 Record bus（AudioEffectRecord）

extends Control

## 麦克风输入节点（AudioStreamPlayer，stream = AudioStreamMicrophone, bus = Record，常驻录音）
@onready var audio_input := $AudioInput

## 录音按钮
@onready var record_button := $RecordButton

## 回放节点（默认 Master bus，播放录音用）
@onready var playback_player := $PlaybackPlayer

## Record bus 上的 AudioEffectRecord 效果器
var effect: AudioEffectRecord

## 录音采样率（录制默认 44100Hz，由 AudioEffectRecord 决定）
## 注意：不要在录音后修改 mix_rate/stereo 元数据，会导致播放速度/声道错乱
## Whisper API 支持任意采样率，内部自动重采样，无需提前转换
func _ready() -> void:
	var idx := AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx, 0)
	record_button.button_down.connect(_On_Record_Button_Down)
	record_button.button_up.connect(_On_Record_Button_Up)


## 按下：开始录音
func _On_Record_Button_Down() -> void:
	if playback_player.playing:
		playback_player.stop()
	effect.set_recording_active(true)
	record_button.text = "Recording..."


## 松开：停止录音并自动播放
func _On_Record_Button_Up() -> void:
	effect.set_recording_active(false)
	var recording: AudioStreamWAV = effect.get_recording()
	if recording == null:
		printerr("[AudioRecordTest] No recording data (microphone not ready?)")
		record_button.text = "Record"
		return
	# 不修改 recording 的 mix_rate/format/stereo（保持录制原始格式）
	print("[AudioRecordTest] recorded %d bytes, %d Hz, %s" % [
		recording.get_data().size(), recording.mix_rate,
		"mono" if not recording.stereo else "stereo"])
	playback_player.stream = recording
	playback_player.play()
	record_button.text = "Record"
