## Presented by KeJi
## Date ： 2026-09-01
## Modified Date ： 2026-10-23
##
## Vehicle2D — 车辆 2D Sprite 节点
## 持有 yaw_offset 校准值，负责将小车姿态应用到自身 transform。

extends Node2D

## 小车 yaw 与 Godot rotation 坐标系之间的偏移量（弧度）
##
## 约定（与 Pleiades 世界坐标一致，见 CoordUtils.real_to_game）：
## - 屏幕 x = 世界 x（东）、屏幕 y = 世界 y（南）→ yaw 从 +x 起、向 +y 增大（屏幕上顺时针）
## - 贴图（Car_classic_blue / Helicopter）在 rotation=0 时**车头朝上**（屏幕 -Y）＝ -90°
## - 所以 rotation = yaw + PI/2 时车头才指向 yaw 方向
##
## 2026-10-23 修正：原值 `-PI/2` 让车头恒偏 180°（贴图车尾朝前，实机车头朝后）；
## 按上面的推导改为 `+PI/2`。UGV 与直升机共用本脚本，两者贴图同朝向，一处修两处生效。
@export var yaw_offset: float = PI / 2.0


## 应用姿态：position 来自 CoordUtils.real_to_game 的转换结果，
## rotation 在小车原始 yaw 基础上加 yaw_offset 校准
func apply_pose(game_pos: Vector2, yaw: float) -> void:
	position = game_pos
	rotation = yaw + yaw_offset


## 设置车身颜色（modulate 乘法，作用于所有动画帧；用于多车区分）
## 直接 $AnimatedSprite2D 取节点：instantiate 后即可用，不依赖 @onready（避免 add_child 前调用时序问题）
func set_color(c: Color) -> void:
	$AnimatedSprite2D.modulate = c
