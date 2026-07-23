extends PanelContainer


func _on_lock_camera_pressed() -> void:
	EventBus.camera_follow_requested.emit()
