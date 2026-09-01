## Presented by KeJi
## Date ： 2026-09-01
##
## LLM — 自然语言指令翻译工具
## 输入：用户自然语言 + 车辆上下文（由 AutoHandler 拼好传入）
## 输出：带 vehicle 字段的多指令数组（Task 27 按车分发）

class_name LLM
extends Node

## 翻译成功（非空或空数组），由调用方决定是否下发
signal cmds_generated(cmds: Array)
## 请求/解析失败
signal request_failed(msg: String)

## OpenAI 兼容 API endpoint（DeepSeek: https://api.deepseek.com/chat/completions）
@export var api_url := "https://api.deepseek.com/chat/completions"
## API Key（DeepSeek 平台申请，场景面板中填写；为空时跳过调用并提示）
@export var api_key := ""
## 模型名（默认 deepseek-v4-flash；pro 版为 deepseek-v4-pro）
@export var model := "deepseek-v4-flash"
## 请求超时（秒）
@export var timeout := 120.0

## 配置文件路径：运行环境 .config/pictor_config.cfg（已 .gitignore，不进 git）
const CONFIG_PATH := "res://.config/pictor_config.cfg"

@onready var _http := $HTTPRequest

## 系统提示词：约束 LLM 输出为任务序列（missions JSON 数组）
const SYSTEM_PROMPT := """你是 Pictor 多车控制系统的指令翻译器。用户输入自然语言指令，你必须只输出一个 JSON 数组（不要任何解释文字、不要 markdown 代码块标记），数组元素为分发给单辆车的任务，协议如下：

{"vehicle": "车名", "type": "goto", "x": 米, "y": 米}
{"vehicle": "车名", "type": "circle", "x": 圆心x米, "y": 圆心y米}

说明：
- vehicle 必须是「当前在线车辆」列表里给出的车名，一字不差
- type 支持 "goto"（前往目标点）与 "circle"（围绕圆心环形散布）
- x / y 为全局世界坐标，单位米
- 当前在线车辆含位置 (x, y) 与朝向（度，0=正北，90=正东）；「前进N米」等相对指令可结合位置+朝向换算目标点
- 每辆车可分配 0 条或多条任务，可一次给多辆车下发
- 无法映射的输入输出空数组 []"""


func _ready() -> void:
	_load_config()  # 先读 .config 配置，覆盖 @export 默认值
	_http.timeout = timeout
	_http.request_completed.connect(_on_request_completed)
	# 不自动发送：等待外部调用 generate_cmds()（如 TextInput 发送按钮）


## 加载配置文件覆盖 @export 默认值；文件不存在时生成默认模板
func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		_save_default_config()
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		printerr("[LLM] 读取配置失败: ", err, " — 使用 @export 默认值")
		return
	api_url = str(cfg.get_value("llm", "api_url", api_url))
	api_key = str(cfg.get_value("llm", "api_key", api_key))
	model = str(cfg.get_value("llm", "model", model))
	timeout = float(cfg.get_value("llm", "timeout", timeout))


## 生成默认配置模板（api_key 留空，用户在文件里填真实 key）
func _save_default_config() -> void:
	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.config"))
	if dir_err != OK:
		printerr("[LLM] 创建 .config 目录失败: ", dir_err)
		return
	var cfg := ConfigFile.new()
	cfg.set_value("llm", "api_url", api_url)
	cfg.set_value("llm", "api_key", "")
	cfg.set_value("llm", "model", model)
	cfg.set_value("llm", "timeout", timeout)
	var save_err := cfg.save(CONFIG_PATH)
	if save_err != OK:
		printerr("[LLM] 生成默认配置失败: ", save_err)
	else:
		print("[LLM] 已生成默认配置: ", CONFIG_PATH)


## 发起一次指令翻译请求（异步，结果经 _on_request_completed 回调）
func generate_cmds(text: String) -> void:
	if api_key == "":
		printerr("[LLM] api_key 未配置，请在场景面板填写 LLM 节点的 api_key 属性")
		EventBus.log_message.emit("❌ LLM api_key 未配置", "error")
		return
	EventBus.log_message.emit("🤖 LLM 翻译中…", "info")
	var body := {
		"model": model,
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": text},
		],
		"stream": false,
		"thinking": {"type": "enabled"},
		"reasoning_effort": "medium",
	}
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	]
	var err: Error = _http.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		printerr("[LLM] 请求发起失败: ", err)
		EventBus.log_message.emit("❌ LLM 请求发起失败", "error")


## HTTP 回调：解析响应 → print
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		printerr("[LLM] 请求失败 result=", result)
		EventBus.log_message.emit("❌ LLM 请求失败", "error")
		request_failed.emit("请求失败 result=%d" % result)
		return
	if response_code != 200:
		printerr("[LLM] HTTP ", response_code, ": ", body.get_string_from_utf8())
		EventBus.log_message.emit("❌ LLM HTTP %d" % response_code, "error")
		request_failed.emit("HTTP %d" % response_code)
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if response == null or not response is Dictionary:
		printerr("[LLM] 响应不是合法 JSON")
		EventBus.log_message.emit("❌ LLM 响应不是合法 JSON", "error")
		request_failed.emit("响应不是合法 JSON")
		return
	print(response)
	var content: String = response["choices"][0]["message"]["content"]
	print("[LLM] 原始响应: ", content)
	var cmds = _parse_cmds(content)
	if cmds == null:
		printerr("[LLM] 输出解析失败")
		EventBus.log_message.emit("❌ LLM 输出解析失败", "error")
		request_failed.emit("LLM 输出解析失败")
		return
	print("[LLM] 解析结果: ", cmds)
	cmds_generated.emit(cmds)
	EventBus.log_message.emit("✅ LLM 输出：%s" % str(cmds), "info")


## 解析 LLM 输出 → cmd 数组（先试直接 JSON，失败再提取 ```json 代码块）
## 返回 null 表示解析失败（区别于模型输出空数组 []）
func _parse_cmds(content: String):
	var parsed = JSON.parse_string(content)
	if parsed is Array:
		return parsed
	# 提取 ```json ... ``` 代码块
	var match := RegEx.create_from_string("```(?:json)?\\s*([\\s\\S]*?)```").search(content)
	if match:
		parsed = JSON.parse_string(match.get_string(1).strip_edges())
		if parsed is Array:
			return parsed
	printerr("[LLM] 输出解析失败，原文: ", content)
	return null
