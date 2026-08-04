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

