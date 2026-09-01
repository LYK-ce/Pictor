## Presented by KeJi
## Date ： 2026-09-01
##
## Vehicle2D — 车辆 2D Sprite 节点
## 持有 yaw_offset 校准值，负责将小车姿态应用到自身 transform。

extends Node2D

## 小车 yaw 与 Godot rotation 坐标系之间的偏移量（弧度）
## 默认 -PI/2：小车 yaw=0（朝北）对齐 Godot rotation=-PI/2（朝上）
@export var yaw_offset: float = -PI / 2.0


## 应用姿态：position 来自 CoordUtils.real_to_game 的转换结果，
## rotation 在小车原始 yaw 基础上加 yaw_offset 校准
func apply_pose(game_pos: Vector2, yaw: float) -> void:
	position = game_pos
	rotation = yaw + yaw_offset


## 设置车身颜色（modulate 乘法，作用于所有动画帧；用于多车区分）
## 直接 $AnimatedSprite2D 取节点：instantiate 后即可用，不依赖 @onready（避免 add_child 前调用时序问题）
func set_color(c: Color) -> void:
	$AnimatedSprite2D.modulate = c
