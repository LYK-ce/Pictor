extends Control
## Present by KeJi
## Date: 2026-07-20
##
## WebSocketCreationMenu — 输入地址端口，emit ws_connect_requested

@onready var address =$Panel/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/address
@onready var port = $Panel/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/port


func _on_button_pressed() -> void:
	var url := "ws://%s:%s" % [address.text, port.text]
	EventBus.ws_connect_requested.emit(url)
	queue_free()
