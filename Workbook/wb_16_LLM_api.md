# wb_16_LLM_api

## meta
- task: task_16_LLM_api
- start: 2026-07-29
- end:
- status: in-progress

## 进度

### 2026-08-04 设计讨论 + 阶段一实现 ✅
- 设计定案：main.tscn 挂 Util 容器（独立 util.tscn）→ 内部实例化 LLM/STT 独立 tscn；工具箱门面模式
- class_name: Util / LLM / STT；调用方 @export var util: Util 面板拖入
- 阶段一范围（用户定）：只调 API + print 结果，**不下发指令**，无 UI
- DeepSeek API：base_url https://api.deepseek.com/chat/completions，模型 deepseek-v4-flash/pro（文档 2026-08-04 确认）
- 实现：src/util/llm.gd(+tscn, HTTPRequest 子节点) + util.gd(+tscn)；main.tscn 挂 Util
- llm.gd：@export api_url/api_key/model/timeout；generate_cmds(text) 异步；SYSTEM_PROMPT 内嵌常量；_parse_cmds 直接 JSON/代码块提取；_ready 自动测试调用（api_key 非空时，接 UI 后移除）
- 踩坑：项目 warning 当 error——`var x := 函数返回Variant` 会编译失败，需显式类型（`var err: Error` / 去 :=）；新 class_name 需 --import 刷新全局类缓存
- 验证：godot --headless --import + --quit-after 5 无错误；本地 mock HTTP 服务器端到端测试通过（请求/响应/解析/print 全链路）
- 待办：用户填 api_key 后真实 API 验证；阶段二接 EventBus.cmd_send 广播（app_state.selected_ids，注释已定）

### 2026-08-05 TextInput 接线 ✅ + result=13 解决
- result=13 (RESULT_DISCONNECTED) 根因：请求体缺 DeepSeek v4 必填 thinking/reasoning_effort 参数 → 服务器断连
- 修复：请求体对齐官方 SDK 示例（model=deepseek-v4-pro, thinking.enabled, reasoning_effort=high）→ 用户本地实测通过（commit 684f6b7）
- 模型输出实测："前进三米然后左转" → [mode switch_to_auto, auto goto(3,0), mode switch_to_manual, manual spin_left]（thinking 模型推理自洽；⚠️ goto 是绝对坐标，模型假设原点朝 x 轴——prompt 语义待调优）
- 用户新建 text_input UI（src/ui/text_input.tscn，挂 main.tscn UI/CanvasLayer 下，commit 1e80ef5/c6be557）
- 本次（未提交）：llm.gd 移除 _ready 自动发送；text_input.gd 实现 _on_send_pressed → util.llm.generate_cmds(text)（@export util: Util + @onready TextEdit as TextEdit + KeJi 头注释）；main.tscn TextInput 实例注入 util = NodePath("../../Util")
- 验证：headless EXIT=0 无脚本错误

### 2026-08-05 LLM 下发链路（阶段二）✅
- 设计定案：TextInput 纯 UI（emit 信号）；AutoHandler 编排（接收输入→调 LLM→收结果→广播下发）；LLM 保持纯工具
- EventBus 新增 `command_requested(text: String)`；llm.gd 新增 `cmds_generated(cmds)` / `request_failed(msg)` 信号（_parse_cmds 失败返回 null 以区分空数组）
- text_input.gd：发送 → emit command_requested → 清空输入框；移除 util 引用
- auto_handler.gd：@onready util := get_node("../../Util") as Util；_on_command_requested → generate_cmds；_on_cmds_generated → for selected_ids × cmds → EventBus.cmd_send（空数组/未选车不下发仅日志）
- 🔴 踩坑：AutoHandler._ready 时 util.llm 的 @onready 尚未赋值（树序 ControlMaster 先于 Util ready）→ 连接被跳过 → 修复：`_connect_llm_signals.call_deferred()`（帧末再连）
- 验证：mock 端到端通过——command_requested("左转") → LLM(mock) → [LLM] → test_car_0 ×2 条指令广播

