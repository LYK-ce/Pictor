## Presented by KeJi
## Date ： 2026-09-01
##
## LogPanel — 屏上日志面板（RichTextLabel 滚动日志）
## 订阅 EventBus.log_message，按 level 上色追加；导出后替代 print 作为语音/LLM 管线状态提示。

extends PanelContainer

## 日志正文
@onready var _log := $RichTextLabel as RichTextLabel

## 最多保留行数（超出清空重来，防止无界增长）
const MAX_LINES := 200

var _line_count := 0


func _ready() -> void:
	_log.scroll_following = true
	EventBus.log_message.connect(_on_log_message)


## 追加一条日志，按 level 上色：info 白 / warn 黄 / error 红
func _on_log_message(text: String, level: String) -> void:
	var color := Color(0.85, 0.85, 0.85)
	match level:
		"warn":
			color = Color(1.0, 0.85, 0.3)
		"error":
			color = Color(1.0, 0.35, 0.35)
	_log.push_color(color)
	_log.append_text(text + "\n")
	_log.pop()
	_line_count += 1
	if _line_count >= MAX_LINES:
		_log.clear()
		_line_count = 0
