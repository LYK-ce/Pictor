## Presented by KeJi
## Date ： 2026-08-31
##
## STT — 语音转文本工具节点
## 监听 EventBus.audio_captured(wav_bytes) → POST 给本地 Python 服务 → 打印返回文本。
## 阶段一：仅打印文本，不下发、不接 LLM。
## 单任务守卫：推理中收到新音频直接丢弃（_busy）。

class_name STT
extends Node

## Python STT 服务地址（tool/stt_server.py）
@export var stt_url := "http://127.0.0.1:9881/transcribe"
## 请求超时（秒）
@export var timeout := 30.0

@onready var _http := $HTTPRequest

## 单任务守卫：推理中丢弃新音频
var _busy := false


func _ready() -> void:
	_http.timeout = timeout
	_http.request_completed.connect(_on_request_completed)
	EventBus.audio_captured.connect(_on_audio_captured)


## EventBus 入口：收到音频 → 转发给 transcribe
func _on_audio_captured(wav_bytes: PackedByteArray) -> void:
	transcribe(wav_bytes)


## 对外入口：把 wav 字节 POST 给 Python（busy 时丢弃）
func transcribe(wav_bytes: PackedByteArray) -> void:
	if _busy:
		print("[STT] busy，丢弃新音频")
		return
	_busy = true
	var body := JSON.stringify({"audio_base64": Marshalls.raw_to_base64(wav_bytes)})
	var headers := ["Content-Type: application/json"]
	var err: Error = _http.request(stt_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		printerr("[STT] 请求发起失败: ", err)


## HTTP 回调：复位 busy + 解析 + 打印
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		printerr("[STT] 请求失败 result=", result)
		return
	if response_code != 200:
		printerr("[STT] HTTP ", response_code, ": ", body.get_string_from_utf8())
		return
	var text := _parse_response(body)
	if text == "":
		printerr("[STT] 未识别出文本")
		return
	print("[STT] 识别结果: ", text)
	# 阶段二：识别文本接入 LLM（与文字输入同一入口）
	EventBus.command_requested.emit(text)


## 解析 JSON 响应 → text（busy/error 返回空并打印提示）
func _parse_response(body: PackedByteArray) -> String:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data == null or not data is Dictionary:
		printerr("[STT] 响应不是合法 JSON")
		return ""
	if data.has("busy") and data["busy"] == true:
		print("[STT] 服务忙")
		return ""
	if data.has("error"):
		printerr("[STT] 服务错误: ", data["error"])
		return ""
	if data.has("text"):
		return str(data["text"])
	printerr("[STT] 响应缺 text 字段: ", data)
	return ""
