## Presented by KeJi
## Date ： 2026-07-28
##
## Camera2D — 独立摄像机组件
## 控制：中键拖拽 + 边缘滚动 + 滚轮缩放
## 跟车：监听 mode_transited(FOLLOW)，内部 IDLE/FOLLOW 状态机

extends Camera2D

## 共享状态
@export var app_state: AppStateResource

## 边缘滚动触发区宽度（像素）
@export var edge_margin := 20.0

## 边缘滚动速度（像素/秒）
@export var edge_speed := 500.0

## 滚轮缩放步进
@export var zoom_step := 0.1

## 最小/最大缩放
@export var zoom_min := 0.2
@export var zoom_max := 4.0

enum State { IDLE, FOLLOW }
var _state := State.IDLE

## 中键拖拽状态
var _is_dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_camera := Vector2.ZERO

## 跟车目标位置（FOLLOW 时由 pose_received 更新）
var _target_position := Vector2.ZERO


func _ready() -> void:
	EventBus.mode_transited.connect(_on_mode_transited)
	EventBus.pose_received.connect(_on_pose)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)


func _process(delta: float) -> void:
	match _state:
		State.FOLLOW:
			position = position.lerp(_target_position, 0.3)
		_:
			_Edge_Scroll(delta)


func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.FOLLOW:
			_Zoom(event)
		_:
			_Middle_Drag(event)
			_Zoom(event)


## 全局模式变化 → 切换内部状态
func _on_mode_transited(mode: int) -> void:
	match mode:
		AppStateResource.Mode.FOLLOW:
			_state = State.FOLLOW
			_target_position = position
			print("[Camera] follow started")
		_:
			if _state == State.FOLLOW:
				print("[Camera] follow stopped")
			_state = State.IDLE


## 车辆位姿更新 → 更新跟车目标位置
func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	if _state != State.FOLLOW:
		return
	if not app_state:
		return
	if vehicle_id != app_state.selected_id:
		return
	var x: float = pose.get("x", 0.0)
	var y: float = pose.get("y", 0.0)
	_target_position = CoordUtils.real_to_game(x, y)


## 车辆断开 → 自动退出跟车
func _on_vehicle_unregistered(vehicle_id: String) -> void:
	if _state != State.FOLLOW:
		return
	if not app_state:
		return
	if vehicle_id == app_state.selected_id:
		_state = State.IDLE
		print("[Camera] follow stopped (vehicle disconnected)")


## 鼠标中键拖拽 —— "抓住地图拖动"
func _Middle_Drag(event: InputEvent) -> void:
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		return

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_MIDDLE:
			return
		if event.pressed:
			_is_dragging = true
			_drag_start_mouse = event.position
			_drag_start_camera = position
		else:
			_is_dragging = false

	if event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _drag_start_mouse
		position = _drag_start_camera - delta / zoom

## 边缘滚动 —— 鼠标贴边平移（RTS 风格）
func _Edge_Scroll(delta: float) -> void:
	var mouse   := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
	var dir     := Vector2.ZERO

	if mouse.x < edge_margin:           dir.x -= 1
	if mouse.x > vp_size.x - edge_margin: dir.x += 1
	if mouse.y < edge_margin:           dir.y -= 1
	if mouse.y > vp_size.y - edge_margin: dir.y += 1

	if dir != Vector2.ZERO:
		position += dir * edge_speed * delta / zoom


## 滚轮缩放 —— 以鼠标位置为中心
func _Zoom(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_Apply_Zoom(zoom_step, event.position)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_Apply_Zoom(-zoom_step, event.position)


func _Apply_Zoom(step: float, anchor: Vector2) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom + step, zoom_min, zoom_max)
	if new_zoom == old_zoom:
		return
	zoom = Vector2(new_zoom, new_zoom)
	var ratio := new_zoom / old_zoom - 1.0
	position += (position - anchor) * ratio
