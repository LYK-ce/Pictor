extends CanvasLayer
## Present by KeJi
## Date: 2026-06-18
##
## Menu — 启动菜单，选择渲染模式

signal renderer_selected(mode: String)

@onready var _btn_none := $Panel/VBoxContainer/BtnNone as Button
@onready var _btn_2d := $Panel/VBoxContainer/Btn2D as Button
@onready var _btn_3d := $Panel/VBoxContainer/Btn3D as Button


func _ready() -> void:
	_btn_none.pressed.connect(_on_none)
	_btn_2d.pressed.connect(_on_2d)
	_btn_3d.pressed.connect(_on_3d)


func _on_none() -> void:
	renderer_selected.emit("none")
	queue_free()


func _on_2d() -> void:
	renderer_selected.emit("2d")
	queue_free()


func _on_3d() -> void:
	renderer_selected.emit("3d")
	queue_free()
