## Presented by KeJi
## Date ： 2026-09-08
##
## CommandChannel — 命令通道输入框
## LineEdit 回车提交 → log_message 回显命令 + user_command_requested 下发内核命令

extends PanelContainer

@onready var _input := $LineEdit as LineEdit


func _ready() -> void:
	_input.text_submitted.connect(_on_text_submitted)


func _on_text_submitted(text: String) -> void:
	var cmd := text.strip_edges()
	if cmd.is_empty():
		return
	_input.clear()
	EventBus.log_message.emit("> " + cmd, "info")
	EventBus.user_command_requested.emit(cmd)
