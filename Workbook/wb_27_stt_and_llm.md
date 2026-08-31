# wb_27_stt_and_llm

## meta
- task: task_27_stt_and_llm
- start: 2026-08-31
- status: STT 完成，LLM 进行中

## STT 进度（✅ 已完成，2026-08-31 真机验证通过）

### 方案
- Python 本地服务（faster-whisper + FastAPI）+ Godot HTTPRequest
- 三态状态机（READY→INFERENCING→RETURN），busy 时回 `{"busy": true}`
- 接口：POST /transcribe，body `{"audio_base64": "<wav base64>"}`，回 `{"text"}` / `{"busy"}` / `{"error"}`

### Godot 侧
- `src/util/STT/stt.gd`（class_name STT，Node + HTTPRequest，`_busy` 守卫）
- EventBus 新增 `audio_captured(wav_bytes)`
- `audio_input.gd` 改内存转发：`_build_wav_bytes()`（44B RIFF 头 + PCM），不再落盘
- STT 挂 `util.tscn`（与 LLM 平级），`util.gd` 加 `@onready var stt`

### Python 侧 tool/stt_server.py
- faster-whisper，`device="cpu"` + `compute_type="int8"`，`language="zh"`
- 内置 `KMP_DUPLICATE_LIB_OK=TRUE`（Windows OpenMP 冲突）

### 踩坑（重要）
1. 模型下载：HuggingFace 直连被墙（WinError 10054）→ 用 hf-mirror 镜像 或 ModelScope 手动下
2. OpenMP 冲突：faster-whisper + onnxruntime 重复加载 libiomp5md.dll → `KMP_DUPLICATE_LIB_OK=TRUE`
3. cublas 找不到：device="auto" 检测到 GPU 但缺 CUDA12 → 强制 `device="cpu"`
4. 模型格式：ModelScope `iic/Whisper-large-v3`（transformers）不能直接用；要用 `Systran/faster-whisper-*`（CTranslate2，含 model.bin）
5. 本地加载：`WhisperModel(path)` 需 path 为**已存在目录**，否则当 repo_id 联网下载；用 `os.path.dirname(__file__)` 拼路径最稳
6. 用户最终用 ModelScope 下了 large-v3（tool/model/），CPU 跑通

## LLM（待讨论）
- 现状：单文件 `src/util/LLM/llm.gd` + llm.tscn，DeepSeek HTTP，TextInput→command_requested→AutoHandler→cmd_send
- 遗留：api_key 明文🔴 / prompt 语义🟡 / 文件头"阶段一"过时🟢
