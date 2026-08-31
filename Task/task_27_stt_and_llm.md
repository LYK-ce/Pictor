# Task 27: STT & LLM 重构

> 创建日期：2026-08-31
> 状态：方案讨论中（随讨论逐步补全）

## 一、STT 方案（已定方向）

- 架构：Python 本地 HTTP 服务 + Godot `HTTPRequest`。
- 流程：Godot 录音（wav）→ HTTP POST → Python 转录 → HTTP 响应返回文本 → Godot 拿文本。
- 模型：本地 faster-whisper（用户倾向），中文，medium / large-v3。
- 文件位置：`tool/stt_server.py`。

## 二、Python 服务设计（✅ 已定）

### 三状态状态机（用户设想）

| 状态 | 说明 |
|---|---|
| 1. READY | 等待接收音频 |
| 2. INFERENCING | 推理（转录） |
| 3. RETURN | 返回结果 → 回到 READY |

- 推理期间收到新音频 → 忽略（单任务，忙时丢弃新请求）。

> 实现备注：用 FastAPI/uvicorn，事件循环由框架托管，状态机落实为「忙标志 + 请求处理函数」；不一定需要手写 while 循环。

### 已定结论
- [x] 忙时返回 `busy` 状态给 Godot（不静默丢弃）
- [ ] 本地 / 远端 API 切换开关（默认本地模型；暂不做，后续可选）
- [x] 接口约定：`POST /transcribe`，请求体 = JSON `{"audio_base64": "<wav base64>"}`，响应 = `{"text": "..."}` / `{"busy": true}` / `{"error": "..."}`（Godot HTTPRequest 只能发 String body，二进制 wav 需 base64）

## 三、Godot 侧 STT 模块（部分已定）

### 已定
- [x] **内存转发**：录音后不落盘，直接用 `AudioStreamWAV.get_data()`（裸 PCM）+ 拼 44 字节 WAV 头 → POST。
- [x] **阶段一**：返回文本先只打印到终端，不接下游。
- [x] **结构**：`audio_input.gd` 留在 `control/`（只管录音）；STT 独立节点在 `util/STT/`（只管转录，挂 HTTPRequest 子节点）。二者经 EventBus 解耦，STT 不直接拿 audio_input。
- [x] **EventBus 新增信号** `audio_captured(wav_bytes: PackedByteArray)`：AudioInput 拼好 wav 后 emit，STT 连接后 POST 给 Python。

信号链：`按钮(audio_record_started/finished) → AudioInput 录音 → audio_captured(wav) → STT → HTTP POST → Python → 返回文本 → STT print`

### STT 节点设计（已定）

- 类型：`class_name STT extends Node`（纯逻辑，同 LLM）
- 子节点：`HTTPRequest`（发音频 / 收文本）

```
STT (Node, stt.gd)
└── HTTPRequest
```

- 属性：
  - `@export var stt_url := "http://127.0.0.1:9881/transcribe"`
  - `@export var timeout := 15.0`
- 方法：
  - `transcribe(wav_bytes: PackedByteArray)` — 对外入口，POST 音频
  - `_on_audio_captured(wav_bytes)` — 连 EventBus.audio_captured，转发给 transcribe
  - `_on_request_completed(...)` — HTTP 回调：复位 busy + 解析 + print
  - `_parse_response(body)` — 解析 JSON（text / busy / 错误）
- busy 守卫（单任务）：
  - `var _busy := false`
  - `transcribe()` 先查 `_busy`，忙则直接 return（丢新音频），否则置 true 发请求
  - `_on_request_completed()` 里**成功/失败都要复位 `_busy = false`**（否则失败后永久卡死）

### 阶段一范围（已定）
- [x] 返回文本只 `print` 到终端，不接下游（不回显输入框、不进 LLM —— 后续再做）
- [x] 不做 busy / 识别中的 UI 反馈（后续再做）

## 四、目录重组计划（部分完成）

在 `src/util/` 下新增两个子目录，与现有 `util.gd/.tscn`（工具箱容器）配合：

```
src/util/
├── util.gd / util.tscn   ← 工具箱容器（class_name Util，挂 LLM + STT）
├── LLM/                  ← ✅ llm.gd / llm.tscn 已挪入
│   ├── llm.gd
│   └── llm.tscn
└── STT/                  ← ✅ stt.gd / stt.tscn 已创建
    ├── stt.gd
    └── stt.tscn
```

### 进度
1. [x] 把 `llm.gd` / `llm.tscn`（+ `.uid`）移入 `src/util/LLM/`，更新 `util.tscn` / `llm.tscn` 引用路径。
2. [x] 在 `src/util/STT/` 下新建 `stt.gd` / `stt.tscn`。
3. [x] 把 STT 实例挂进 `util.tscn`（与 LLM 平级），并给 `util.gd` 加 `@onready var stt: STT = $STT`。

## 五、LLM（待议）
- （暂空，等 STT 定稿后接着聊）
