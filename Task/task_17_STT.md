# Task 17: STT (Speech to Text)

## 目标

实现语音转文本：Godot 侧录音 → 模型推理 → 返回文本。**方案未最终确定**（两条路线待选，见「方案讨论」）。

## 已完成部分

### Godot 侧录音 ✅（2026-08-03/04，主场景已集成）

```
麦克风 → AudioInput (ControlMaster 下, bus=Record, autoplay 常驻)
          ↓
Record bus (mute=true) → AudioEffectRecord 捕获 (default_bus_layout.tres)
          ↓
UI 麦克风按钮 (button_list) 按住/松开 → EventBus.audio_record_started/finished
          ↓
audio_input.gd: set_recording_active → get_recording()
          ↓
save_to_wav("res://recordings/record_时间戳.wav")  ← 原始 44.1kHz/16bit/stereo
```

链路（已验证，Godot 4.7.1）：
`Audio_Input 按钮(UI) → EventBus → AudioInput(ControlMaster) → 录音/保存`

> ⚠️ **录音关键经验（已验证）**：
> 1. `AudioStreamMicrophone` 必须由 `AudioStreamPlayer` **处于播放状态**（autoplay=true 或 play()）麦克风才激活
> 2. Record bus 必须 **mute=true**，否则麦克风实时外放
> 3. 回放必须用**独立 AudioStreamPlayer（默认 Master bus）**，复用 Record bus 会被静音
> 4. **不要**在录音后改 `mix_rate/stereo` 元数据（不重采样，播放变调）
> 5. 录音数据为空时 `get_recording()` 返回 null，需判空

## 方案讨论（2026-08-04，待决策）

### 背景：vehicle-stt 仓库研究结论
- `ripple-jmx/vehicle-stt`（MIT）：Rust C 库（cdylib）+ Python faster-whisper 服务
- **其 Rust 部分只是 HTTP 客户端**（收音频 → POST → 返回文字），**不跑模型**，纯转发
- 真正推理在 Python（`stt_server.py`，faster-whisper + large-v3，A100 实测 14/14，0.42s/条）
- 它"接受任意音频格式"是因为 **faster-whisper 内部（PyAV）自动重采样**，不是 Rust 的功劳

### 关键结论
- **不存在"零重采样"选项**：whisper 模型只认 16kHz/mono 输入
  - faster-whisper（Python）：自动重采样 ✅
  - whisper.cpp/whisper-rs（Rust）：需自己写重采样（~20 行线性插值）
- **中间层（Rust 转发客户端）对我们是多余的**：Godot 自带 HTTPRequest，可直接 POST
- Rust 确实能跑 Whisper 模型（whisper-rs / candle 均可，支持 CUDA）

### 两条待选路线

| | 路线 A：纯 Rust | 路线 B：纯 Godot + Python |
|---|---|---|
| 谁跑模型 | Rust（whisper-rs/candle） | Python（faster-whisper） |
| Godot 调用 | GDExtension `transcribe()`（异步+信号） | HTTPRequest 直接 POST |
| 重采样 | 自写 ~20 行 | 自动（PyAV） |
| 识别效果 | 好（whisper.cpp） | 更好（实测 14/14） |
| 额外进程 | 无 | 常驻 Python 服务（:9881） |
| 部署 | 编译 Rust .so，打进 Godot | Python 环境 + 3GB 模型 |
| 模型文件 | ggml 格式（用户提供） | faster-whisper 格式（用户提供） |

### 若走路线 A 的设计要点（讨论稿）
- 接口：`transcribe_async(audio_bytes, mime)` + `transcription_finished/failed` 信号（异步，不卡 UI）
- 技术：gdext 的 `task` 模块（spawn 线程推理 → sync_to_main_thread 发信号）
- 并发：whisper 非线程安全 → 单任务，忙时忽略新请求
- 模型加载：首次调用时后台加载，完成发 `model_loaded` 信号
- 音频：Rust 内部 WAV 解析 + 重采样 16kHz/mono/f32，GDScript 无感
- 版本：godot crate 0.5.4 对 Godot 4.7；引擎已统一 4.7.1（Steam 版 = 服务器版）

**待拍板：选路线 A 还是 B**（用户倾向 A：本地推理打进 Godot，无中间服务）

## 设计决策

| 项 | 决定 |
|------|------|
| 录音方案 | ✅ AudioEffectRecord + Record bus（已验证） |
| WAV 编码 | ✅ `AudioStreamWAV.save_to_wav()` 内置 |
| 模型推理方 | ⏳ 待定（Rust whisper-rs/candle vs Python faster-whisper） |
| 调用方式 | ⏳ 待定（GDExtension 异步 vs HTTPRequest） |
| 重采样 | ⏳ 视路线（Rust 自写 vs Python 自动） |
| 环境 | ✅ Godot 4.7.1（Steam 版 + 服务器统一） |

## 子任务

- [x] 1. Godot 侧录音验证（测试场景：按住录/松开回放）✅ 2026-08-03
- [x] 2. 主场景录音集成（AudioInput 挂 ControlMaster + mic 按钮 + 存 wav）✅ 2026-08-04
- [ ] 3. 确定方案（路线 A/B）→ 细化设计
- [ ] 4. （路线 A）Rust GDExtension 项目搭建 + transcribe + 异步信号
- [ ] 5. （路线 B）stt_server.py 部署 + Godot HTTPRequest 接入
- [ ] 6. 语音文本接入下游（LLM cmd / 车控指令）

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/control/audio_input.tscn/gd` | ✅ 已有 | 麦克风节点 + 录音/保存逻辑 |
| `src/control/control.tscn` | ✅ 已有 | AudioInput 挂 ControlMaster |
| `src/event_bus/event_bus.gd` | ✅ 已有 | audio_record_started/finished 信号 |
| `src/ui/button_list.tscn/gd` | ✅ 已有 | mic 按钮（按住/松开 → EventBus） |
| `src/test/audio_record_test.tscn/gd` | ✅ 已有 | 录音验证场景（回放） |
| `default_bus_layout.tres` | ✅ 已有 | Record bus (mute=true) + AudioEffectRecord |
| `rust/`（路线 A） | 新建 | GDExtension 项目 |
| `pictor_stt.gdextension`（路线 A） | 新建 | Godot 注册 |
| `stt_server.py` 等（路线 B） | 新建/复用 | faster-whisper 服务（vehicle-stt 提供） |

## 依赖

- Rust 工具链（路线 A）/ Python + faster-whisper（路线 B）
- Whisper 模型文件（ggml 或 faster-whisper 格式，用户提供）
- task_16 (LLM 共用 config)
