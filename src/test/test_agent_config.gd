extends SceneTree
## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentConfig 离线单测（task_51 Step 6 / L1「无网单测回归」）—— 9 条，零联网、零节点
## 用法：godot --headless --path Pictor -s src/test/test_agent_config.gd
## 期望：末行 `=== ALL PASS: true ===`，退出码 0
## 复现失败：照抄上面这条命令；日志落 tmp/task51/s6/L1_test_agent_config.log
##
## 覆盖 9 条：
##   T1 missing_file_creates_template  缺文件 → 落模板 + ok/created 双真 + config == Defaults()  §7.2
##   T2 template_round_trip            模板 5 处文本齐全；二次 Load 不重写且逐键相等
##   T3 partial_file_uses_defaults     只手写 model → 其余 3 键取缺省
##   T4 max_tokens_clamped             99999→8192 / 0→1 / "abc"→1024 / "2048"→2048
##   T5 extra_keys_ignored             多写 temperature → Values() 仍只有 4 键
##   T6 custom_path                    自定义路径不串味（path 就是它）
##   T7 empty_url_falls_back           api_url="" → 缺省；api_key="" → **允许为空**
##   T8 model_trimmed                  model 两侧空白被 strip_edges()
##   T9 parse_error_keeps_defaults     坏文件 → ok=false + parse_error + config == Defaults()
##
## ⚠️ T9 会**故意**让 ConfigFile.load() 失败，Godot 因此会自己往 stderr 打 1 行 ERROR
##    （`ConfigFile::_load` 的报错），**属预期**；本步的 0 ERROR 判据只针对
##    `godot --headless --path Pictor --import`，不针对单测日志。
## ⚠️ 只写 user://test_agent_config_{a,b}.cfg，跑完（含失败）一律删。

const ConfigScript := preload("res://src/agent/agent_config.gd")

const TEST_A := "user://test_agent_config_a.cfg"
const TEST_B := "user://test_agent_config_b.cfg"


func _initialize() -> void:
	# ⚠️ _init 阶段 autoload 未注册；单测入口一律 _initialize + call_deferred
	_Run_All.call_deferred()


func _Run_All() -> void:
	_cleanup()
	var ok := true
	var r := true
	r = _T1_missing_file_creates_template()
	ok = ok and r
	r = _T2_template_round_trip()
	ok = ok and r
	r = _T3_partial_file_uses_defaults()
	ok = ok and r
	r = _T4_max_tokens_clamped()
	ok = ok and r
	r = _T5_extra_keys_ignored()
	ok = ok and r
	r = _T6_custom_path()
	ok = ok and r
	r = _T7_empty_url_falls_back()
	ok = ok and r
	r = _T8_model_trimmed()
	ok = ok and r
	r = _T9_parse_error_keeps_defaults()
	ok = ok and r
	print("=== ALL PASS: ", ok, " ===")
	_cleanup()
	quit(0 if ok else 1)


# ─── T1..T9 ──────────────────────────────────────────────────

## 缺文件 → 落模板；ok/created 双真；内存值 == Defaults()；请求的路径就是返回值里的 path
func _T1_missing_file_creates_template() -> bool:
	_delete(TEST_A)
	var cfg = ConfigScript.new(TEST_A)
	var lr: Dictionary = cfg.Load()
	if not bool(lr.get("ok", false)):
		return _fail("T1", "Load.ok=false error=" + str(lr.get("error", "")))
	if not bool(lr.get("created", false)):
		return _fail("T1", "created 应为 true（文件是刚生成的）")
	if not FileAccess.file_exists(TEST_A):
		return _fail("T1", "模板文件没生成：" + TEST_A)
	if str(lr.get("path", "")) != TEST_A:
		return _fail("T1", "path 不等于请求路径：" + str(lr.get("path", "")))
	if str(lr.get("error", "")) != "":
		return _fail("T1", "成功时 error 应为空串，实为 " + str(lr.get("error", "")))
	if lr["config"] != ConfigScript.Defaults():
		return _fail("T1", "config 不等于 Defaults()：" + JSON.stringify(lr["config"]))
	return true


## 模板正文 5 处关键文本齐全；第二次 Load 不重写（created=false）且 4 键逐键相等
func _T2_template_round_trip() -> bool:
	var text := _read(TEST_A)
	for needle: String in [
		"[llm]",
		"api_url=\"http://127.0.0.1:8080/v1/chat/completions\"",
		"api_key=\"local\"",
		"model=\"qwen3.8-27b\"",
		"max_tokens=1024",
	]:
		if not text.contains(needle):
			return _fail("T2", "模板缺文本：" + needle)
	var first: Dictionary = ConfigScript.new(TEST_A).Load()
	var second: Dictionary = ConfigScript.new(TEST_A).Load()
	if not bool(second.get("ok", false)):
		return _fail("T2", "二次 Load 失败：" + str(second.get("error", "")))
	if bool(second.get("created", false)):
		return _fail("T2", "文件已存在时 created 必须是 false（不许重写）")
	var a: Dictionary = first["config"]
	var b: Dictionary = second["config"]
	for key: String in ConfigScript.CONFIG_KEYS:
		if a.get(key) != b.get(key):
			return _fail("T2", "两次读取的 %s 不一致：%s vs %s" % [key, str(a.get(key)), str(b.get(key))])
	return true


## 只写 model → 其余 3 键取缺省（Load 宽松）
func _T3_partial_file_uses_defaults() -> bool:
	_write(TEST_A, "[llm]\nmodel=\"m2\"\n")
	var lr: Dictionary = ConfigScript.new(TEST_A).Load()
	if not bool(lr.get("ok", false)):
		return _fail("T3", "Load 失败：" + str(lr.get("error", "")))
	var c: Dictionary = lr["config"]
	if str(c[ConfigScript.KEY_MODEL]) != "m2":
		return _fail("T3", "model 应为 m2，实为 " + str(c[ConfigScript.KEY_MODEL]))
	if str(c[ConfigScript.KEY_URL]) != ConfigScript.DEFAULT_URL:
		return _fail("T3", "api_url 应回缺省，实为 " + str(c[ConfigScript.KEY_URL]))
	if str(c[ConfigScript.KEY_API_KEY]) != ConfigScript.DEFAULT_API_KEY:
		return _fail("T3", "api_key 应回缺省，实为 " + str(c[ConfigScript.KEY_API_KEY]))
	if int(c[ConfigScript.KEY_MAX_TOKENS]) != ConfigScript.DEFAULT_MAX_TOKENS:
		return _fail("T3", "max_tokens 应回缺省，实为 " + str(c[ConfigScript.KEY_MAX_TOKENS]))
	return true


## max_tokens 夹取：99999→8192 / 0→1 / "abc"→1024 / "2048"→2048（全部走 cfg 文件，即真路径）
func _T4_max_tokens_clamped() -> bool:
	var cases := [
		{"raw": "99999", "want": ConfigScript.MAX_TOKENS_MAX},
		{"raw": "0", "want": ConfigScript.MAX_TOKENS_MIN},
		{"raw": "\"abc\"", "want": ConfigScript.DEFAULT_MAX_TOKENS},
		{"raw": "\"2048\"", "want": 2048},
	]
	for one: Dictionary in cases:
		_write(TEST_A, "[llm]\nmax_tokens=%s\n" % str(one["raw"]))
		var lr: Dictionary = ConfigScript.new(TEST_A).Load()
		if not bool(lr.get("ok", false)):
			return _fail("T4", "Load 失败 raw=" + str(one["raw"]))
		var got := int((lr["config"] as Dictionary)[ConfigScript.KEY_MAX_TOKENS])
		if got != int(one["want"]):
			return _fail("T4", "max_tokens=%s 应为 %d，实为 %d" % [str(one["raw"]), int(one["want"]), got])
	return true


## 未知键忽略：Values() 永远 4 键，且不含 temperature
func _T5_extra_keys_ignored() -> bool:
	_write(TEST_A, "[llm]\nmodel=\"m3\"\ntemperature=0.5\nfoo=\"bar\"\n")
	var cfg = ConfigScript.new(TEST_A)
	var lr: Dictionary = cfg.Load()
	if not bool(lr.get("ok", false)):
		return _fail("T5", "Load 失败：" + str(lr.get("error", "")))
	var values: Dictionary = cfg.Values()
	if values.size() != ConfigScript.CONFIG_KEYS.size():
		return _fail("T5", "Values() 应只有 4 键，实有 %d 键：%s" % [values.size(), JSON.stringify(values)])
	if values.has("temperature"):
		return _fail("T5", "Values() 不该含 temperature")
	if str(cfg.Model()) != "m3":
		return _fail("T5", "model 应仍是 m3，实为 " + str(cfg.Model()))
	return true


## 自定义路径不串味：new(TEST_B).Load() 的 path 就是 TEST_B，且值来自 TEST_B
func _T6_custom_path() -> bool:
	_write(TEST_A, "[llm]\nmodel=\"from_a\"\n")
	_write(TEST_B, "[llm]\nmodel=\"from_b\"\n")
	var cfg_b = ConfigScript.new(TEST_B)
	var lr: Dictionary = cfg_b.Load()
	if str(cfg_b.Path()) != TEST_B:
		return _fail("T6", "Path() 应为 %s，实为 %s" % [TEST_B, cfg_b.Path()])
	if str(lr.get("path", "")) != TEST_B:
		return _fail("T6", "Load().path 应为 %s，实为 %s" % [TEST_B, str(lr.get("path", ""))])
	if str(cfg_b.Model()) != "from_b":
		return _fail("T6", "读了别的文件：model=" + str(cfg_b.Model()))
	var cfg_a = ConfigScript.new(TEST_A)
	cfg_a.Load()
	if str(cfg_a.Model()) != "from_a":
		return _fail("T6", "A 被 B 串味：model=" + str(cfg_a.Model()))
	return true


## api_url="" → 缺省；api_key="" → 允许为空（与 url 不同）
func _T7_empty_url_falls_back() -> bool:
	_write(TEST_A, "[llm]\napi_url=\"\"\napi_key=\"\"\n")
	var cfg = ConfigScript.new(TEST_A)
	var lr: Dictionary = cfg.Load()
	if not bool(lr.get("ok", false)):
		return _fail("T7", "Load 失败：" + str(lr.get("error", "")))
	if cfg.Url() != ConfigScript.DEFAULT_URL:
		return _fail("T7", "空 api_url 应回缺省，实为 " + cfg.Url())
	if not cfg.Api_Key().is_empty():
		return _fail("T7", "空 api_key 应保持空串（本地 vLLM 无鉴权），实为 " + cfg.Api_Key())
	return true


## model 两侧空白被去掉
func _T8_model_trimmed() -> bool:
	_write(TEST_A, "[llm]\nmodel=\"  qwen3.8-27b  \"\n")
	var cfg = ConfigScript.new(TEST_A)
	var lr: Dictionary = cfg.Load()
	if not bool(lr.get("ok", false)):
		return _fail("T8", "Load 失败：" + str(lr.get("error", "")))
	if cfg.Model() != "qwen3.8-27b":
		return _fail("T8", "model 未 strip：[" + cfg.Model() + "]")
	return true


## 坏文件 → ok=false + parse_error + config 回到 Defaults()（不让半份配置进 Run）
## ⚠️ 本用例会让 ConfigFile 自己打 1 行 ERROR（预期，见文件头）
## ⚠️ 只有「键有等号但值为空」这类才真让 ConfigFile 报 parse error（实测 err=43 =
##    ERR_PARSE_ERROR）；纯中文行 / 缺右括号的段头会被**静默忽略**（err=OK），不能当坏文件用
func _T9_parse_error_keeps_defaults() -> bool:
	_write(TEST_A, "[llm]\nbroken_key = \n")
	var cfg = ConfigScript.new(TEST_A)
	var lr: Dictionary = cfg.Load()
	if bool(lr.get("ok", false)):
		return _fail("T9", "坏文件不该 ok=true")
	if str(lr.get("error", "")) != ConfigScript.ERR_PARSE:
		return _fail("T9", "error 应为 parse_error，实为 " + str(lr.get("error", "")))
	if lr["config"] != ConfigScript.Defaults():
		return _fail("T9", "失败后 config 应为 Defaults()：" + JSON.stringify(lr["config"]))
	if cfg.Values() != ConfigScript.Defaults():
		return _fail("T9", "失败后 Values() 应为 Defaults()")
	return true


# ─── 小工具 ──────────────────────────────────────────────────

func _fail(tag: String, msg: String) -> bool:
	print("FAIL ", tag, " ", msg)
	return false


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[test_agent_config] 写失败：" + path)
		return
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[test_agent_config] 读失败：" + path)
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup() -> void:
	_delete(TEST_A)
	_delete(TEST_B)
