extends Control
## Present by KeJi
## Date: 2026-06-09
##
## ZoomSlider — 缩放滑块，通过 EventBus 与 Renderer 通信

@onready var _slider := $Panel/VSlider as VSlider
@onready var _label := $Panel/Label as Label


func _ready() -> void:
	_slider.min_value = 0.5
	_slider.max_value = 4.0
	_slider.step = 0.1
	_slider.value = 1.0
	_slider.value_changed.connect(_on_value_changed)

	_label.text = "Zoom: 1.0x"

	EventBus.zoom_changed.connect(_on_zoom_changed)


func _on_value_changed(v: float) -> void:
	_label.text = "Zoom: %.1fx" % v
	EventBus.zoom_changed.emit(v)


func _on_zoom_changed(zoom: float) -> void:
	_slider.set_value_no_signal(zoom)
	_label.text = "Zoom: %.1fx" % zoom
