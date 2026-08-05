## Presented by KeJi
## Date ： 2026-08-05
##
## TextInput — LLM 自然语言指令输入框（UI 组件）
## 点击发送按钮 → util.llm.generate_cmds(text)

extends Control

## 工具箱引用（场景面板拖入 Main/Util）
@export var util: Util

@onready var _text_edit := $PanelContainer/HBoxContainer/TextEdit as TextEdit


# 按下发送按钮，将当前文本框内容发送给 LLM
func _on_send_pressed() -> void:
	var text := _text_edit.text.strip_edges()
	if text == "":
		return
	util.llm.generate_cmds(text)
