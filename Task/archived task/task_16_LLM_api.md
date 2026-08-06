# Task 16: LLM API

## 目标

在 `src/` 下创建 `LLM/` 目录，实现 LLM 驱动的指令生成：用户输入自然语言命令 → LLM 输出 cmd 指令流 → 下发给小车。

## 架构

```
src/LLM/
├── llm_config.gd          ← 配置文件（API key / endpoint / model）
├── llm_client.gd          ← HTTP 客户端，调 OpenAI 兼容 API
├── llm_prompt.gd          ← Prompt 管理（加载/拼接/变量替换）
├── llm_parser.gd          ← 解析 LLM 输出 → cmd 数组
└── ui/
    └── llm_input.tscn/gd  ← 独立 UI 输入框
```

```
用户输入 → llm_prompt → llm_client → llm_parser → cmd[] → EventBus.cmd_send
```

## 设计决策

| 项 | 决定 |
|------|------|
| LLM 服务 | OpenAI 兼容 API (`/v1/chat/completions`) |
| 输出格式 | 现有 cmd 协议 JSON 数组 |
| 用户输入 | 独立 UI 组件 |
| API Key | ConfigFile (`user://llm_config.cfg`) |

## 待讨论

- Streaming vs 非流式？
- 解析器的容错策略？
- Prompt 文件加载方式？

## 子任务

- [ ] 1. 创建 `src/LLM/` 目录
- [ ] 2. `llm_config.gd` — ConfigFile 加载
- [ ] 3. `llm_client.gd` — HTTP API 调用
- [ ] 4. `llm_prompt.gd` — Prompt 管理
- [ ] 5. `llm_parser.gd` — 输出解析
- [ ] 6. `llm_input` — UI 输入组件

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/LLM/llm_config.gd` | 新建 | 配置加载 |
| `src/LLM/llm_client.gd` | 新建 | API 调用 |
| `src/LLM/llm_prompt.gd` | 新建 | Prompt 管理 |
| `src/LLM/llm_parser.gd` | 新建 | 输出解析 |
| `src/LLM/ui/llm_input.tscn` | 新建 | UI 组件 |

## 依赖

- task_15 (Protocol / MessageBuilder)
- EventBus cmd_send 链路
