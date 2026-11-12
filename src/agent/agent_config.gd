## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentConfig — agent 的 LLM 配置（task_51 Step 6 §7.2）
## 只读 `user://agent_config.cfg`；文件不存在 → 落一份模板再按模板返回（created=true）。
##
## ⚠️ 与 `Pictor/.config/pictor_config.cfg`（llm.gd 的 DeepSeek 配置）**无关**，本步不碰那份。
##    `.config/config.toml` 是 kernel 的（listen_port / peer_name），也不在这里。
## ⚠️ 本文件**不引用任何 autoload**（`EventBus` 之类）：`-s` 脚本在启动时编译，
##    那一刻 autoload 全局名还没注册，写了就是 `Identifier not found`（实测，见 tmp/task51/impl.md）。
## ⚠️ 一律 `ConfigFile.new().load()`，不用 `FileAccess.get_as_text() + JSON`：cfg 不是 JSON。
##
## 归一化口径（逐条定死，单测 T3~T8 逐个钉）：
##   ① api_url —— strip_edges()，空串 → DEFAULT_URL
##   ② api_key —— strip_edges()，**允许空串**（本地 vLLM 无鉴权时不发 Authorization 头）
##   ③ model   —— strip_edges()，空串 → DEFAULT_MODEL
##   ④ max_tokens —— 非数字类型一律默认；String 先 is_valid_int() 再转；最后 clampi(1, 8192)
##   ⑤ 未知键（temperature 等）忽略，Values() 永远只有 4 个键
##   ⑥ 文件已存在 → **不重写**（created=false），只有缺文件才写模板

class_name AgentConfig
extends RefCounted

## 缺省路径与段名
const DEFAULT_PATH := "user://agent_config.cfg"
const SECTION := "llm"

## 四个键（Values() 的键集唯一真源）
const KEY_URL := "api_url"
const KEY_API_KEY := "api_key"
const KEY_MODEL := "model"
const KEY_MAX_TOKENS := "max_tokens"
const CONFIG_KEYS := [KEY_URL, KEY_API_KEY, KEY_MODEL, KEY_MAX_TOKENS]

## 缺省值（= 本机 vLLM 的实况：127.0.0.1:8080 + qwen3.8-27b，§7.1）
const DEFAULT_URL := "http://127.0.0.1:8080/v1/chat/completions"
const DEFAULT_API_KEY := "local"
const DEFAULT_MODEL := "qwen3.8-27b"
const DEFAULT_MAX_TOKENS := 1024

## max_tokens 夹取区间（防手改成 0 或天文数字）
const MAX_TOKENS_MIN := 1
const MAX_TOKENS_MAX := 8192

## Load() 的 error 短码（只有落盘失败与解析失败两种；成功是空串）
const ERR_WRITE := "write_error"
const ERR_PARSE := "parse_error"

var _path: String = DEFAULT_PATH
var _values: Dictionary = {}


## 只记路径，不读盘（读盘由调用方 Load() 决定，与 PlaceMap 同风格）
func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_values = Defaults()


# ─── 模板与缺省 ───────────────────────────────────────────────

## 模板正文：4 个键 + 段名 + 注释头。
## ⚠️ cfg 的行注释是 `;`，**不是** `#`（`#` 会被 ConfigFile 当普通字符）。
static func Template_Text() -> String:
	return """; Presented by KeJi
; Created Date ： 2026-11-12
; Modified Date ： 2026-11-12
; Pictor agent 的 LLM 配置（task_51 Step 6）。改完不必重启编辑器，下次 Run 生效。
[llm]
api_url="%s"
api_key="%s"
model="%s"
max_tokens=%d
""" % [DEFAULT_URL, DEFAULT_API_KEY, DEFAULT_MODEL, DEFAULT_MAX_TOKENS]


## 四个缺省值（新字典，调用方随便改）
static func Defaults() -> Dictionary:
	return {
		KEY_URL: DEFAULT_URL,
		KEY_API_KEY: DEFAULT_API_KEY,
		KEY_MODEL: DEFAULT_MODEL,
		KEY_MAX_TOKENS: DEFAULT_MAX_TOKENS,
	}


## 归一化：4 键齐全（唯一入口，Load 与单测都走它）
static func Normalize(url: Variant, api_key: Variant, model: Variant, max_tokens: Variant) -> Dictionary:
	var u := str(url).strip_edges()
	if u.is_empty():
		u = DEFAULT_URL
	var k := str(api_key).strip_edges()
	var m := str(model).strip_edges()
	if m.is_empty():
		m = DEFAULT_MODEL
	return {
		KEY_URL: u,
		KEY_API_KEY: k,
		KEY_MODEL: m,
		KEY_MAX_TOKENS: _As_Tokens(max_tokens),
	}


# ─── 读盘 ─────────────────────────────────────────────────────

func Path() -> String:
	return _path


## 读配置。返回固定 5 键：{ok, created, error, path, config}；失败时 config = 缺省值
func Load() -> Dictionary:
	var created := false
	if not FileAccess.file_exists(_path):
		if not _Write_Template():
			_values = Defaults()
			return {
				"ok": false, "created": false, "error": ERR_WRITE,
				"path": _path, "config": _values.duplicate(true),
			}
		created = true
	# ⚠️ 坏文件时 ConfigFile 会**自己往 stderr 打 1 行 ERROR**（单测 T9 就是这条路径，
	#    属预期；判据只针对 `--import` 的 0 ERROR，见 impl.md）
	var cf := ConfigFile.new()
	var err: int = cf.load(_path)
	if err != OK:
		_values = Defaults()
		return {
			"ok": false, "created": created, "error": ERR_PARSE,
			"path": _path, "config": _values.duplicate(true),
		}
	_values = Normalize(
		cf.get_value(SECTION, KEY_URL, DEFAULT_URL),
		cf.get_value(SECTION, KEY_API_KEY, DEFAULT_API_KEY),
		cf.get_value(SECTION, KEY_MODEL, DEFAULT_MODEL),
		cf.get_value(SECTION, KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS))
	return {"ok": true, "created": created, "error": "", "path": _path, "config": _values.duplicate(true)}


# ─── 四个取值口（调用点不用记键名）────────────────────────────

func Values() -> Dictionary:
	return _values.duplicate(true)


func Url() -> String:
	return str(_values.get(KEY_URL, DEFAULT_URL))


func Api_Key() -> String:
	return str(_values.get(KEY_API_KEY, DEFAULT_API_KEY))


func Model() -> String:
	return str(_values.get(KEY_MODEL, DEFAULT_MODEL))


func Max_Tokens() -> int:
	return int(_values.get(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS))


# ─── 内部：落模板 / 类型归一 ──────────────────────────────────

## 写模板（只在缺文件时调用）。失败 → false，调用方按 write_error 处理
func _Write_Template() -> bool:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_warning("[AgentConfig] 模板写入失败：%s（%s）" % [_path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(Template_Text())
	f.close()
	return true


## max_tokens 归一：bool / Dictionary / Array / null / 非整数字符串 → 缺省；结果夹到 [1, 8192]
static func _As_Tokens(v: Variant) -> int:
	if v is int:
		return clampi(int(v), MAX_TOKENS_MIN, MAX_TOKENS_MAX)
	if v is float:
		# JSON 里 1024 会解成 float；非有限值（1e999）与 1024.9 都按四舍五入后的整数夹取
		if not is_finite(float(v)):
			return DEFAULT_MAX_TOKENS
		return clampi(int(round(float(v))), MAX_TOKENS_MIN, MAX_TOKENS_MAX)
	if v is String:
		var text := str(v).strip_edges()
		if not text.is_valid_int():
			return DEFAULT_MAX_TOKENS
		return clampi(int(text), MAX_TOKENS_MIN, MAX_TOKENS_MAX)
	return DEFAULT_MAX_TOKENS
