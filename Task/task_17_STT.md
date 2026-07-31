# Task 17: STT (Speech to Text)

## 目标

通过 Rust GDExtension 实现语音转文本：Godot 侧录音 → Rust 透传 Whisper API → 返回文本。

## 架构

```
Godot 录音 (AudioStreamMicrophone) → PCM → 转 WAV
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

### Godot 侧

```
麦克风
  │
  ▼
AudioRecorder  ← AudioStreamMicrophone 录音
  │              输出 PCM float32 (32kHz mono)
  │
  ▼
WAV 编码      ← 加 44 字节 WAV header
  │
  ▼
STTService.transcribe(bytes, "audio/wav")
  │
  ▼
文本
```

## 设计决策

| 项 | 决定 |
|------|------|
| STT 后端 | OpenAI Whisper API |
| Rust 编译目标 | `cdylib` → `.so` / `.dylib` / `.dll` |
| 调用方式 | GDScript → Rust `#[func]` 同步调用 |
| API Key | ConfigFile 读取 |
| 音频格式 | Godot 输出 PCM → 编码 WAV → Rust 透传 |

## 子任务

- [ ] 1. Rust 项目搭建 (Cargo.toml + lib.rs)
- [ ] 2. 实现 `transcribe` 函数
- [ ] 3. 创建 `.gdextension` 注册文件
- [ ] 4. Godot 侧 AudioRecorder 组件
- [ ] 5. WAV 编码工具
- [ ] 6. 与 UI 集成
## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `rust/Cargo.toml` | 新建 | Rust 项目配置 |
| `rust/src/lib.rs` | 新建 | STT GDExtension |
| `pictor_stt.gdextension` | 新建 | Godot 注册 |
| `src/STT/audio_recorder.gd` | 新建 | 录音组件 |
| `src/STT/wav_encoder.gd` | 新建 | PCM → WAV |
## 依赖

- Rust 工具链
- OpenAI API Key
- task_16 (LLM 共用 config)
