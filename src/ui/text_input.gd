## Presented by KeJi
## Date ： 2026-08-05
##
## TextInput — 自然语言指令输入框（UI 组件）
## 点击发送 → EventBus.command_requested.emit(text) → AutoHandler 编排（LLM 翻译 + 下发）

extends Control

@onready var _text_edit := $PanelContainer/HBoxContainer/TextEdit as TextEdit


# 按下发送按钮：广播输入内容给 AutoHandler，并清空输入框
func _on_send_pressed() -> void:
	var text := _text_edit.text.strip_edges()
	if text == "":
		return
	EventBus.command_requested.emit(text)
	_text_edit.text = ""
