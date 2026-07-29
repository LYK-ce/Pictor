extends PanelContainer

@export var app_state: AppStateResource


func _on_lock_camera_pressed() -> void:
	if not app_state:
		return
	if app_state.mode == AppStateResource.Mode.FOLLOW:
		app_state.mode = AppStateResource.Mode.NONE
	else:
		app_state.mode = AppStateResource.Mode.FOLLOW


func _on_goto_pressed() -> void:
	if not app_state:
		return
	if app_state.mode == AppStateResource.Mode.GOTO:
		app_state.mode = AppStateResource.Mode.NONE
	else:
		app_state.mode = AppStateResource.Mode.GOTO
		print(self.name,'goto button pressed')
