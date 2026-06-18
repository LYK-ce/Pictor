extends Control
## Present by KeJi
## Date: 2026-06-18
##
## WebSocketManager — 管理多个 WebSocket 连接
## 点击"创建连接" → 输入 IP/端口 → 新建 WebSocketClient

@export var ws_client_scene: PackedScene

@onready var _list := $Panel/VBoxContainer/Scroll/List as VBoxContainer
@onready var _btn_create := $Panel/VBoxContainer/BtnCreate as Button
@onready var _input_ip := $Panel/VBoxContainer/InputRow/IP as LineEdit
@onready var _input_port := $Panel/VBoxContainer/InputRow/Port as SpinBox
@onready var _btn_confirm := $Panel/VBoxContainer/InputRow/BtnConfirm as Button
@onready var _input_row := $Panel/VBoxContainer/InputRow as HBoxContainer

var _connections: Array = []  # [{ws: Node, label: Label, btn: Button}]


func _ready() -> void:
	_btn_create.pressed.connect(_show_input)
	_btn_confirm.pressed.connect(_create_connection)
	_input_row.hide()


func _show_input() -> void:
	_input_row.show()
	_input_ip.text = "10.100.80.220"
	_input_port.value = 9090
	_input_ip.grab_focus()


func _create_connection() -> void:
	var ip := _input_ip.text.strip_edges()
	var port: int = int(_input_port.value)
	if ip.is_empty():
		return

	var url := "ws://%s:%d" % [ip, port]

	# 创建 WebSocketClient
	var ws: Node = ws_client_scene.instantiate()
	ws.name = "WS-%s:%d" % [ip, port]
	ws.set("_url", url)
	add_child(ws)

	# 添加行到列表
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s:%d — 连接中" % [ip, port]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var btn := Button.new()
	btn.text = "断开"
	btn.pressed.connect(func():
		ws.queue_free()
		row.queue_free()
	)
	row.add_child(btn)

	_list.add_child(row)
	_connections.append({"ws": ws, "label": label, "btn": btn})

	# 更新状态
	_check_status(label, ws)

	_input_ip.text = ""
	_input_row.hide()


func _process(_delta: float) -> void:
	for conn in _connections:
		var ws: Node = conn.ws
		if not is_instance_valid(ws):
			continue
		var label: Label = conn.label
		var btn: Button = conn.btn
		_check_status(label, ws)
		if label.text.begins_with("已连接"):
			btn.hide()


func _check_status(label: Label, ws: Node) -> void:
	var state = ws.get("_state") if ws.get("_state") != null else 0
	match state:
		2:  label.text = label.text.replace("连接中", "已连接").replace("未连接", "已连接")
		1:  label.text = label.text.replace("已连接", "连接中").replace("未连接", "连接中")
		_:  pass
