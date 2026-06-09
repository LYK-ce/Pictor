extends CanvasLayer
## Present by KeJi
## Date: 2026-06-09
##
## UI — 父容器（CanvasLayer），挂载所有 UI 子组件

@export var zoom_slider_scene: PackedScene


func _ready() -> void:
	if not zoom_slider_scene:
		zoom_slider_scene = load("res://src/ui/zoom_slider/zoom_slider.tscn")
	if zoom_slider_scene:
		add_child(zoom_slider_scene.instantiate())
