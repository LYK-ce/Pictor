## Presented by KeJi
## Date ： 2026-08-03
##
## AudioRecordTest — 麦克风录音测试
## 按住 Record 按钮开始录音，松开后停止并自动播放
## 依赖：default_bus_layout.tres 中的 Record bus（AudioEffectRecord）

extends Control

## 麦克风输入节点（AudioStreamPlayer，stream = AudioStreamMicrophone, bus = Record）
@onready var audio_input := $AudioInput

## 录音按钮
@onready var record_button := $RecordButton

## Record bus 上的 AudioEffectRecord 效果器
var effect: AudioEffectRecord

## 麦克风流（录音时使用）
var mic_stream: AudioStreamMicrophone

## 录音采样率（Whisper 标准输入 16kHz）
const MIX_RATE := 16000


func _ready() -> void:
	var idx := AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx, 0)
	mic_stream = AudioStreamMicrophone.new()
	audio_input.stream = mic_stream
	audio_input.bus = "Record"
	record_button.button_down.connect(_On_Record_Button_Down)
	record_button.button_up.connect(_On_Record_Button_Up)
	audio_input.finished.connect(_On_Audio_Finished)


## 按下：开始录音
func _On_Record_Button_Down() -> void:
	if audio_input.playing:
		audio_input.stop()
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
	audio_input.stream = recording
	audio_input.play()
	record_button.text = "Record"


## 播放结束：换回麦克风，便于再次录音
func _On_Audio_Finished() -> void:
	audio_input.stream = mic_stream
