## Presented by KeJi
## Date ： 2026-08-03
##
## AudioInput — 麦克风输入节点（AudioStreamPlayer）
## 通过 EventBus 信号控制录音：
##   audio_record_started  → 开始录音
##   audio_record_finished → 结束录音，内存拼 WAV → audio_captured 发出
## 依赖：default_bus_layout.tres 中的 Record bus（AudioEffectRecord）
## 说明：Task 27 起改为「内存转发」，不再落盘；录音字节经 audio_captured 交给 STT。

extends AudioStreamPlayer

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
	EventBus.log_message.emit("🎙 录音开始", "info")


## 结束录音：内存拼 WAV 头 + PCM → 经 EventBus 发给 STT（不落盘）
func _On_Record_Finished() -> void:
	if record_effect == null:
		return
	record_effect.set_recording_active(false)
	var recording: AudioStreamWAV = record_effect.get_recording()
	if recording == null:
		printerr("[AudioInput] no recording data (microphone not ready?)")
		EventBus.log_message.emit("❌ 未采集到录音数据（麦克风未就绪？）", "error")
		return
	var wav := _build_wav_bytes(recording)
	EventBus.audio_captured.emit(wav)
	print("[AudioInput] captured %d wav bytes (%d Hz, %s)" % [
		wav.size(), recording.mix_rate,
		"mono" if not recording.stereo else "stereo"])
	EventBus.log_message.emit("🎙 录音完成（%d 字节）" % wav.size(), "info")


## 在内存中拼一个完整 WAV（44 字节 RIFF 头 + 原始 PCM），供 HTTP 上传
## 麦克风录音为 16bit PCM；非 PCM 格式（IMA_ADPCM/QOA）暂不处理
func _build_wav_bytes(recording: AudioStreamWAV) -> PackedByteArray:
	var pcm := recording.get_data()
	var channels := 2 if recording.stereo else 1
	var bits := 16 if recording.format == AudioStreamWAV.FORMAT_16_BITS else 8
	var sample_rate := recording.mix_rate
	var byte_rate := sample_rate * channels * bits / 8
	var block_align := channels * bits / 8

	var wav := PackedByteArray()
	wav.append_array("RIFF".to_ascii_buffer())
	wav.append_array(_u32(pcm.size() + 36))
	wav.append_array("WAVE".to_ascii_buffer())
	wav.append_array("fmt ".to_ascii_buffer())
	wav.append_array(_u32(16))          # fmt chunk 大小（PCM）
	wav.append_array(_u16(1))           # 音频格式 1 = PCM
	wav.append_array(_u16(channels))
	wav.append_array(_u32(sample_rate))
	wav.append_array(_u32(byte_rate))
	wav.append_array(_u16(block_align))
	wav.append_array(_u16(bits))
	wav.append_array("data".to_ascii_buffer())
	wav.append_array(_u32(pcm.size()))
	wav.append_array(pcm)
	return wav


## 小端 u16 → 2 字节
func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])


## 小端 u32 → 4 字节
func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])
