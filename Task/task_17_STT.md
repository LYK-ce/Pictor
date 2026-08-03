# Task 17: STT (Speech to Text)

## 目标

通过 Rust GDExtension 实现语音转文本：Godot 侧录音 → Rust 透传 Whisper API → 返回文本。

## 架构

```
Godot 录音 (AudioEffectRecord) → AudioStreamWAV → get_data() / save_to_wav()
                                                          │
                                                          ▼
                                                   Rust STT 模块
                                                 (HTTP 透传，同步阻塞)
                                                          │
                                                          ▼
                                                    文本 (String)
```

### Rust 模块

```
rust/
├── Cargo.toml                   ← dep: reqwest(blocking) + godot
├── src/
│   └── lib.rs                   ← 一个 class，一个 transcribe 函数
└── target/release/
    └── libpictor_stt.linux.so   ← 编译产物

pictor_stt.gdextension           ← Godot 注册文件
```

### 接口

```rust
#[func]
fn transcribe(&self, audio_data: PackedByteArray, mime_type: GString) -> GString
```

- 音频原样 multipart POST 给 Whisper API
- 不做任何编解码，纯 HTTP 透传
- 同步阻塞调用

### Godot 侧（✅ 录音链路已验证，见 `src/test/audio_record_test.tscn`）

```
麦克风
  │
  ▼
AudioInput (AudioStreamPlayer, bus=Record)
  │   stream=AudioStreamMicrophone, autoplay=true   ← 常驻激活麦克风
  ▼
Record bus (mute=true)                                ← 防止实时外放
  └── AudioEffectRecord 效果器 (default_bus_layout.tres)
        │  set_recording_active(true/false) 控制开关
        ▼
AudioStreamWAV ← effect.get_recording()     ← 44.1kHz/16bit/stereo（录制默认）
        │
        ├── PlaybackPlayer.play()           ← 独立播放器（默认 Master bus）回放
        └── (STT) transcribe(get_data(), "audio/wav")   ← 后续接入
```

> ⚠️ **关键经验（已验证）**：
> 1. `AudioStreamMicrophone` 必须由 `AudioStreamPlayer` **处于播放状态**（autoplay=true 或 play()）麦克风才激活，否则录音为空
> 2. Record bus 必须 **mute=true**（官方 mic_record demo 同款），否则麦克风输入实时外放
> 3. 回放必须用**独立的 AudioStreamPlayer（默认 Master bus）**——复用 Record bus 的播放器会被 mute 静音
> 4. **不要**在录音后调用 `set_mix_rate()`/`set_stereo()` 改元数据（不重采样，播放会变调变慢）；Whisper API 支持任意采样率内部自动重采样
> 5. Godot 4.6 的 `AudioStreamMicrophone` **没有** `mix_rate` 属性（4.7 才有）；录音采样率由 AudioEffectRecord 决定（默认 44.1kHz）
> 6. 录音数据为空时 `get_recording()` 返回 null，需判空防御

## 设计决策

| 项 | 决定 |
|------|------|
| STT 后端 | OpenAI Whisper API |
| Rust 编译目标 | `cdylib` → `.so` / `.dylib` / `.dll` |
| 调用方式 | GDScript → Rust `#[func]` 同步调用 |
| API Key | ConfigFile 读取 |
| 录音方案 | **AudioEffectRecord + Record bus**（官方 demo 方案，已验证），非 AudioStreamMicrophone 手动 PCM |
| WAV 编码 | `AudioStreamWAV.save_to_wav()` 内置（无需手写 44 字节 header） |
| 音频格式 | 录制原始 44.1kHz/16bit/stereo 直接透传 |

## 子任务

- [ ] 1. Rust 项目搭建 (Cargo.toml + lib.rs)
- [ ] 2. 实现 `transcribe` 函数
- [ ] 3. 创建 `.gdextension` 注册文件
- [x] 4. Godot 侧录音验证（`audio_record_test.tscn`：按住录音/松开回放）✅ 2026-08-03
- [ ] 5. `src/STT/` 正式录音组件封装（audio_recorder.gd，复用测试逻辑）
- [ ] 6. 与 UI 集成

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `rust/Cargo.toml` | 新建 | Rust 项目配置 |
| `rust/src/lib.rs` | 新建 | STT GDExtension |
| `pictor_stt.gdextension` | 新建 | Godot 注册 |
| `src/STT/audio_recorder.gd` | 新建 | 录音组件（封装 AudioEffectRecord 逻辑） |
| `src/test/audio_record_test.tscn/gd` | ✅ 已有 | 录音验证场景 |
| `src/control/audio_input.tscn/gd` | ✅ 已有 | 麦克风输入节点（AudioStreamPlayer + autoplay） |
| `default_bus_layout.tres` | ✅ 已有 | Record bus (mute=true) + AudioEffectRecord |

## 依赖

- Rust 工具链
- OpenAI API Key
- task_16 (LLM 共用 config)
