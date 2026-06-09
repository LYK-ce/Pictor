extends CanvasLayer
## Present by KeJi
## Date: 2026-06-09
##
## UI — 父容器（CanvasLayer），挂载所有 UI 子组件


func _ready() -> void:
	var zs_scene := load("res://src/ui/zoom_slider/zoom_slider.tscn")
	var zs := zs_scene.instantiate()
	add_child(zs)
