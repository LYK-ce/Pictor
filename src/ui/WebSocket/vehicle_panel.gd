extends PanelContainer

@onready var id = $VBoxContainer/ID
@onready var address = $VBoxContainer/Address
@onready var pose = $VBoxContainer/Pose
@onready var pos = $VBoxContainer/Position
@onready var velocity = $VBoxContainer/Velocity

# 更新vehicle panel使用的方法
func Update(_id, _addres, _pose, _pos, _velocity):
	pass


# 按下此按钮发出断开连接信号。
func _on_disconnect_pressed() -> void:
	pass # Replace with function body.
