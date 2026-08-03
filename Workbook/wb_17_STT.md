# wb_17_STT

## meta
- task: task_17_STT
- start: 2026-08-03
- end:
- status: in-progress

## 进度

### 2026-08-03 录音链路验证完成 ✅
- 参考 Godot 官方 demo `mic_record`（Godot 4.7 文档 recording_with_microphone）
- 创建测试场景 `src/test/audio_record_test.tscn` + `audio_record_test.gd`
- 交互：按住 Record 录音，松开自动回放（button_down/button_up 信号）

## 踩坑记录（重要）

### 1. 麦克风不激活（无图标/空录音）
- 现象：右下角无麦克风图标，录不到声音
- 原因：`AudioStreamMicrophone` 必须由 `AudioStreamPlayer` 播放（autoplay=true 或 play()）才激活输入
- 修复：`audio_input.tscn` 配置 `stream=AudioStreamMicrophone + autoplay=true + bus=Record`

### 2. 录音时实时外放（听到自己声音）
- 原因：Record bus 未静音，麦克风输入直达 Master
- 修复：`default_bus_layout.tres` 的 Record bus `mute=true`（官方 demo 同款；AudioEffectRecord 在 muted bus 上仍正常录音）

### 3. 回放听不到（松开按钮后无声音）
- 原因：复用 AudioInput（bus=Record，muted）播放录音 → 被静音
- 修复：新增独立 `PlaybackPlayer`（默认 Master bus）播放录音；AudioInput 只管常驻录音

### 4. 回放声音变调/变慢（"放不出正确声音"）
- 原因：录音后调用 `recording.set_mix_rate(16000)` + `set_stereo(false)` 只改元数据不重采样，44100Hz/stereo 数据按 16000Hz/mono 播放
- 修复：删除 set_* 调用，保持录制原始格式（44.1kHz/16bit/stereo）直接播放
- 备注：Whisper API 支持任意采样率自动重采样，无需提前转 16k

### 5. 其他
- Godot 4.6 `AudioStreamMicrophone` 无 `mix_rate` 属性（4.7 才有），不要设置
- `get_recording()` 在无数据时返回 null，需判空（防御：`No recording data`）
- 环境 Godot 版本：4.6.3（headless 验证用）；项目 features 声明 "4.7"

## 完成产物
- `src/test/audio_record_test.tscn` / `.gd` — 录音测试场景（按住录/松开播）
- `src/control/audio_input.tscn` — AudioStreamPlayer + mic + autoplay + bus=Record
- `default_bus_layout.tres` — Record bus (mute=true) + AudioEffectRecord
- 提交：57d27b9 / 9703b77 / 5570850 / a37541a

## 下一步
- [ ] Rust GDExtension 项目搭建（transcribe 透传）
- [ ] `src/STT/audio_recorder.gd` 正式组件封装
- [ ] WAV 直接 `save_to_wav()`（内置编码）或 `get_data()` 透传
