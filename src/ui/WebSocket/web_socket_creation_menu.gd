extends Control

@onready var address = $Panel/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/address
@onready var port = $Panel/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/port



# 按钮按下的时候根据address和port创建websocket，点击创建完毕后这个子节点就不需要了。
func _on_button_pressed() -> void:
	pass # Replace with function body.
