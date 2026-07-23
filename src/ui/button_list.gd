extends PanelContainer


func _on_lock_camera_pressed() -> void:
	EventBus.camera_follow_requested.emit()


func _on_goto_pressed() -> void:
	pass # Replace with function body.
