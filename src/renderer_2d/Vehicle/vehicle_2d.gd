## Presented by KeJi
## Date ： 2026-07-22
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
