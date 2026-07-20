extends Control
## Present by KeJi
## Date: 2026-07-20
##
## WebSocketMenu — Connect 按钮，弹出 CreationMenu

@export var creation_menu_scene: PackedScene
var _creation_menu: Control = null


func _on_connect_pressed() -> void:
	if _creation_menu:
		_creation_menu.queue_free()
		_creation_menu = null
		return

	_creation_menu = creation_menu_scene.instantiate()
	get_parent().add_child(_creation_menu)
