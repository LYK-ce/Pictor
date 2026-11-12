## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentTransport — agent 的网络抽层（task_51 Step 5 §6.3-1）
## 唯一职责：把 messages 变成 {ok, content, error, elapsed_ms} 四键结果。
##
## ⚠️ GDScript 没有 try —— 本层**永不抛、永不返回 null、永不返回别的形状**，
##    失败只走 ok=false + error 短码（调用方按短码判，不按异常）。
## ⚠️ 本层**不做重试**：重试在任何调用方（AgentLoop._Post_With_Retry：1 次、间隔 1 s、
##    不额外计轮）。传输层只负责「一次投递」。
## ⚠️ 方法名用 Pascal `Post`：task_51 §6.3-1 里的小写 `post` 是伪代码，
##    全局硬约束是「新增 API 一律 Pascal」（同 Run / Parse / Exec / Build_System）。
## ⚠️ 不走继承：内部类 `extends <外部 class_name>` 是对自身全局类名的引用（依赖全局类缓存），
##    而 AgentLoop 只按方法名调用（鸭子类型），继承零收益 ⇒ HttpTransport 独立 `extends RefCounted`。
## ⚠️ 内部类引用外部类的常量 / 静态方法**一律带类名限定**（`AgentTransport.X`）：
##    GDScript 的内部类看不到外部脚本的成员，不限定就是 Identifier not declared。

class_name AgentTransport
extends RefCounted

## Post() 的返回键（一个不多一个不少）
const RESULT_KEYS := ["ok", "content", "error", "elapsed_ms"]

## 单请求超时（秒）：**不复用 llm.gd 的 120**（§6.3-6）
const DEFAULT_TIMEOUT_S := 60.0

## error 短码（稳定值，单测与 Step 6 日志都按它判；不在这里抛异常）
const ERR_NOT_IMPLEMENTED := "not_implemented"
const ERR_NO_ENDPOINT := "no_endpoint"
const ERR_HOST_NOT_IN_TREE := "host_not_in_tree"
const ERR_IN_FLIGHT := "in_flight"
const ERR_START_FAILED := "request_start_failed"
const ERR_HTTP_RESULT := "http_result"
const ERR_HTTP_STATUS := "http_status"
const ERR_BAD_BODY := "bad_response"
const ERR_TRANSPORT_GONE := "transport_gone"
const ERR_CANCELLED := "cancelled"


## 契约（基类给空实现：当「空对象」用时一律失败，绝不静默成功）
func Post(_messages: Array, _opt: Dictionary = {}) -> Dictionary:
	return Fail(ERR_NOT_IMPLEMENTED, Time.get_ticks_msec())


## 取消：默认空实现（Fake / 空对象无需实现）
func Cancel() -> void:
	pass


## 统一的失败结果（elapsed 由调用点传 t0 算，保证四键形状恒定）
static func Fail(code: String, t0: int) -> Dictionary:
	return {
		"ok": false, "content": "", "error": code,
		"elapsed_ms": maxi(0, Time.get_ticks_msec() - t0),
	}


## 生产实现：包一个懒建的 HTTPRequest 子节点（挂在 host 上；host 由调用方传 self）
class HttpTransport extends RefCounted:
	var host = null
	var url := ""
	var api_key := ""
	var model := ""
	var timeout_s := AgentTransport.DEFAULT_TIMEOUT_S

	var _http: HTTPRequest = null
	## ⚠️ Godot 坑 ①：HTTPRequest 一次只能挂一个请求 —— 用自家标志守，不赌版本 API
	var _inflight := false
	var _cancelled := false

	func _init(p_host = null, p_url := "", p_api_key := "", p_model := "",
			p_timeout_s := AgentTransport.DEFAULT_TIMEOUT_S) -> void:
		host = p_host
		url = str(p_url)
		api_key = str(p_api_key)
		model = str(p_model)
		timeout_s = float(p_timeout_s)

	## 调用方在 Run 之前调它（不新增 project.godot 键、不新增 autoload）
	func Set_Endpoint(p_url: String, p_api_key: String = "", p_model: String = "") -> void:
		url = p_url
		api_key = p_api_key
		model = p_model

	## 一次投递 → 四键结果。url 为空直接 no_endpoint（= 不联网），单测永远注入 FakeTransport。
	func Post(messages: Array, opt: Dictionary = {}) -> Dictionary:
		var t0 := Time.get_ticks_msec()
		if url.strip_edges().is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_NO_ENDPOINT, t0)
		if _cancelled:
			return AgentTransport.Fail(AgentTransport.ERR_CANCELLED, t0)
		if _inflight:
			return AgentTransport.Fail(AgentTransport.ERR_IN_FLIGHT, t0)
		if not _Ensure_Http():
			return AgentTransport.Fail(AgentTransport.ERR_HOST_NOT_IN_TREE, t0)
		_http.timeout = float(opt.get("timeout_s", timeout_s))
		var body := {"model": model, "messages": messages, "stream": false, "temperature": 0.0}
		var headers := PackedStringArray(["Content-Type: application/json"])
		if not api_key.strip_edges().is_empty():
			headers.append("Authorization: Bearer %s" % api_key)
		_inflight = true
		var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			_inflight = false
			return AgentTransport.Fail(AgentTransport.ERR_START_FAILED, t0)
		# ⚠️ Godot 坑 ②：节点 free 后 request_completed 不再触发 → await 会永久挂起。
		#    这一行是唯一出口：先验身份，再碰任何成员（_http 可能已被宿主带走）。
		var resp = await _http.request_completed      # [result, response_code, headers, body]
		_inflight = false
		if not is_instance_valid(_http):
			return AgentTransport.Fail(AgentTransport.ERR_TRANSPORT_GONE, t0)
		if int(resp[0]) != HTTPRequest.RESULT_SUCCESS:
			return AgentTransport.Fail(AgentTransport.ERR_HTTP_RESULT, t0)
		if int(resp[1]) != 200:
			return AgentTransport.Fail(AgentTransport.ERR_HTTP_STATUS, t0)
		var text: String = (resp[3] as PackedByteArray).get_string_from_utf8()
		# ⚠️ 一律 JSON.new().parse()：JSON.parse_string 失败会往 stderr 打 ERROR
		#    （place_map.gd:103 先例），会把 headless 日志判据污染成「有 ERROR」
		var json := JSON.new()
		if json.parse(text) != OK or not (json.data is Dictionary):
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var choices: Variant = (json.data as Dictionary).get("choices", [])
		if not (choices is Array) or (choices as Array).is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var message: Variant = (choices[0] as Dictionary).get("message", {})
		if not (message is Dictionary):
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var content := str((message as Dictionary).get("content", ""))
		if content.strip_edges().is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		return {
			"ok": true, "content": content, "error": "",
			"elapsed_ms": maxi(0, Time.get_ticks_msec() - t0),
		}

	## 懒建 HTTPRequest：_ready 里不建（无副作用，单测不注入就永远不建）
	func _Ensure_Http() -> bool:
		if is_instance_valid(_http):
			return true
		# HTTPRequest 靠 _process 推进：不在树里会「request 成功但永不完成」（挂起的第二种形态）
		if host == null or not is_instance_valid(host) or not host.is_inside_tree():
			return false
		_http = HTTPRequest.new()
		_http.name = "AgentHttpRequest"
		_http.timeout = timeout_s
		host.add_child(_http)
		return true

	## 取消：置标志 + cancel_request()（宿主 _exit_tree 里调；见 AgentLoop._Exit_Tree 的注释）
	func Cancel() -> void:
		_cancelled = true
		if is_instance_valid(_http) and _inflight:
			_http.cancel_request()

	func Is_In_Flight() -> bool:
		return _inflight
