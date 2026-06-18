extends Control
## Present by KeJi
## Date: 2026-06-18
##
## WebSocketManager — 连接管理 UI + WebSocketClient 生命周期

@export var ws_client_scene: PackedScene

@onready var _ip_input := $Panel/VBoxContainer/IP as LineEdit
@onready var _port_input := $Panel/VBoxContainer/Port as SpinBox
@onready var _btn := $Panel/VBoxContainer/Btn as Button
@onready var _status := $Panel/VBoxContainer/Status as Label

var _ws_client: Node = null
var _connected := false


func _ready() -> void:
	_ip_input.text = "10.100.80.220"
	_port_input.value = 9090
	_status.text = "未连接"
	_btn.text = "连接"
	_btn.pressed.connect(_toggle)


func _toggle() -> void:
	if _connected:
		_disconnect()
	else:
		_connect()


func _connect() -> void:
	var ip := _ip_input.text.strip_edges()
	var port: int = int(_port_input.value)
	var url := "ws://%s:%d" % [ip, port]

	_ws_client = ws_client_scene.instantiate()
	_ws_client.name = "WebSocketClient"
	_ws_client.set("_url", url)  # 在 add_child 前设好，_ready() 会读取
	get_parent().add_child(_ws_client)

	_connected = true
	_status.text = "已连接"
	_btn.text = "断开"
	_ip_input.editable = false
	_port_input.editable = false


func _disconnect() -> void:
	if _ws_client:
		_ws_client.queue_free()
		_ws_client = null
	_connected = false
	_status.text = "未连接"
	_btn.text = "连接"
	_ip_input.editable = true
	_port_input.editable = true
