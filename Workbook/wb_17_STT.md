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

### 2026-08-04 主场景录音集成 ✅ + 方案讨论
- AudioInput 挂到 ControlMaster（control.tscn）
- UI mic 按钮（button_list，用户/队友已加 mic.svg）→ EventBus 两个新信号
  → audio_input.gd 录音 + 保存 res://recordings/record_时间戳.wav（原始格式）
- 端到端验证通过（headless 模拟，4.7.1）
- 研究了 ripple-jmx/vehicle-stt 仓库（用户提供）
- 方案讨论：路线 A（纯 Rust GDExtension 本地推理）vs 路线 B（纯 Godot+Python faster-whisper）
- **待拍板：路线 A/B**（用户倾向 A）

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
- 备注：Whisper 模型只认 16kHz/mono；faster-whisper 自动重采样，whisper.cpp 需自写

### 5. 其他
- Godot 4.6 `AudioStreamMicrophone` 无 `mix_rate` 属性（4.7 才有），不要设置
- `get_recording()` 在无数据时返回 null，需判空（防御：`No recording data`）
- **环境 Godot 已升级 4.6.3 → 4.7.1.stable.official**（用户 Steam 版同款；旧版备份 godot-4.6.3.bak）

## vehicle-stt 研究结论（2026-08-04）
- 仓库 = Rust C 库（cdylib，仅 2.8MB）+ Python faster-whisper 服务
- Rust 部分纯 HTTP 客户端（收音频 → POST /v1/audio/transcriptions → 文字），**不跑模型**
- 推理在 Python：stt_server.py（faster-whisper + large-v3，A100 实测 14/14，0.42s/条，中文口语数字自动转阿拉伯）
- 支持任意格式（webm/mp3/wav/ogg/flac/m4a）是因为 **faster-whisper 内部 PyAV 自动重采样**
- 结论：中间层 Rust 转发对 Godot 多余（HTTPRequest 直连即可）；Rust 跑模型用 whisper-rs/candle（均支持 CUDA）

## 完成产物
- `src/test/audio_record_test.tscn` / `.gd` — 录音测试场景（按住录/松开播）
- `src/control/audio_input.tscn` — AudioStreamPlayer + mic + autoplay + bus=Record
- `src/control/audio_input.gd` — 录音控制 + 保存 wav（EventBus 驱动）
- `src/control/control.tscn` — AudioInput 挂 ControlMaster
- `src/event_bus/event_bus.gd` — audio_record_started/finished
- `src/ui/button_list.gd/tscn` — mic 按钮（按住/松开 → EventBus）
- `default_bus_layout.tres` — Record bus (mute=true) + AudioEffectRecord
- 提交：57d27b9 / 9703b77 / 5570850 / a37541a / 9f89380

## 下一步（待用户拍板路线后）
- [ ] 确定路线 A（纯 Rust GDExtension）或 B（Godot HTTP + Python faster-whisper）
- [ ] A: rust/ 项目搭建（godot crate 0.5.4 + whisper-rs/candle），异步 transcribe + 信号
- [ ] B: stt_server.py 部署（models 下载 ~3GB）+ Godot HTTPRequest 接入
- [ ] 语音文本接入下游（LLM cmd / 车控指令）
