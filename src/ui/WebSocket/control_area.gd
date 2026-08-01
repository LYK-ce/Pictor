extends ColorRect


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print('input mouse button')
