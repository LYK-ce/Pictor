## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentParse — 模型输出解析层（task_51 Step 5 §6.3-2）
## 只认两种 JSON 对象（action 大小写与首尾空白不敏感）：
##   {"action":"call",  "tool":"<name>", "args":{...}}
##   {"action":"final", "tasks":[{"vehicle":"小车A","missions":[{...}]}, ...]}
## 容错顺序（§6.3-2）：剥 ``` 围栏 → 直接解析 → 失败则截第一个 `{` 到最后一个 `}` 再解析
##   → 仍失败 `bad_json`。
##
## ⚠️ 一律 `JSON.new().parse()`，不用 `JSON.parse_string()`：后者解析失败会往 stderr 打 ERROR，
##    把「单测日志零 ERROR」这条判据污染掉（place_map.gd:103 已踩过同一个坑）。
## ⚠️ 解析层只管「形状」，不管语义：action / tool / args / tasks 缺了或类型不对才报错；
##    工具名认不认识、任务能不能下发，是 AgentTools 与 TaskApi 的事。

class_name AgentParse
extends RefCounted

const ACTION_CALL := "call"
const ACTION_FINAL := "final"
const ACTIONS := [ACTION_CALL, ACTION_FINAL]

## 4 个错误码（§6.3-2 的判定顺序即代码顺序）
const ERR_BAD_JSON := "bad_json"
const ERR_BAD_ACTION := "bad_action"
const ERR_BAD_CALL := "bad_call"
const ERR_BAD_FINAL := "bad_final"

## Parse() 的返回键（7 个，一个不多一个不少）
const RESULT_KEYS := ["ok", "action", "tool", "args", "tasks", "error", "json"]


## 模型原始输出 → {ok, action, tool, args, tasks, error, json}
## 成功时 error == ""；失败时 ok == false 且 error ∈ 4 个码之一，其余键保持默认（{} / [] / ""）。
static func Parse(raw: String) -> Dictionary:
	var out := {
		"ok": false, "action": "", "tool": "", "args": {}, "tasks": [],
		"error": ERR_BAD_JSON, "json": "",
	}
	var obj: Variant = _First_Object(raw)
	if obj == null or not (obj is Dictionary):
		return out                                  # bad_json
	var d: Dictionary = obj
	out["json"] = JSON.stringify(d)
	# ① action：必须先判它，否则「既没 action 又没 tool」会被误报成 bad_call
	var action_raw: Variant = d.get("action", null)
	if not (action_raw is String):
		out["error"] = ERR_BAD_ACTION
		return out
	var action := str(action_raw).strip_edges().to_lower()
	if not ACTIONS.has(action):
		out["error"] = ERR_BAD_ACTION
		return out
	out["action"] = action
	# ② call：tool 必须是非空字符串；args 可省（视为 {}），但给了就必须是对象
	if action == ACTION_CALL:
		var tool_raw: Variant = d.get("tool", null)
		if not (tool_raw is String) or str(tool_raw).strip_edges().is_empty():
			out["error"] = ERR_BAD_CALL
			return out
		var args_raw: Variant = d.get("args", {})
		if args_raw == null:
			args_raw = {}
		if not (args_raw is Dictionary):
			out["error"] = ERR_BAD_CALL
			return out
		out["ok"] = true
		out["error"] = ""
		out["tool"] = str(tool_raw).strip_edges()
		out["args"] = (args_raw as Dictionary).duplicate(true)
		return out
	# ③ final：tasks 必须是数组（空数组合法 = 「什么都不做」，不是取消）
	var tasks_raw: Variant = d.get("tasks", null)
	if not (tasks_raw is Array):
		out["error"] = ERR_BAD_FINAL
		return out
	out["ok"] = true
	out["error"] = ""
	out["tasks"] = (tasks_raw as Array).duplicate(true)
	return out


## 剥 ```json … ``` 围栏（没有围栏就只 strip_edges）
static func Strip_Fence(raw: String) -> String:
	var text := raw.strip_edges()
	var re := RegEx.create_from_string("```(?:json)?\\s*([\\s\\S]*?)```")
	var m := re.search(text)
	if m != null:
		return m.get_string(1).strip_edges()
	return text


## 三段式取对象：剥围栏 → 直接解析 → 截第一个 { 到最后一个 } 再解析
static func _First_Object(raw: String) -> Variant:
	var text := Strip_Fence(raw)
	var v: Variant = _Try_Parse(text)
	if v != null:
		return v
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		return null
	return _Try_Parse(text.substr(a, b - a + 1))


## ⚠️ 用 JSON.new().parse()：JSON.parse_string 解析失败会往 stderr 打 ERROR
static func _Try_Parse(text: String) -> Variant:
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var data: Variant = json.data
	if data is Dictionary or data is Array:
		return data
	return null
