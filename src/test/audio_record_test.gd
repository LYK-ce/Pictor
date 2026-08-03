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

## 录音采样率（Whisper 标准输入 16kHz）
const MIX_RATE := 16000


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
	recording.set_mix_rate(MIX_RATE)
	recording.set_format(AudioStreamWAV.FORMAT_16_BITS)
	recording.set_stereo(false)
	print("[AudioRecordTest] recorded %d bytes, %d Hz, %s" % [
		recording.get_data().size(), recording.mix_rate,
		"mono" if not recording.stereo else "stereo"])
	playback_player.stream = recording
	playback_player.play()
	record_button.text = "Record"
