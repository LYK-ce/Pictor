extends Label
## Present by KeJi
## Date: 2026-06-18
##
## HelpLabel — 左下角操作说明


func _ready() -> void:
	text = "W/S  前进/后退\nA/D  左旋/右旋\n空格  停止"
	add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	add_theme_font_size_override("font_size", 14)
