## Present by KeJi
## Date: 2026-06-08
##
## CoordUtils — 真实世界 ↔ 游戏世界坐标转换
class_name CoordUtils
extends RefCounted

const SCALE := 32.0


## 真实世界 (x, z) 米 → 游戏世界 Vector2
static func real_to_game(x: float, z: float) -> Vector2:
	return Vector2(x * SCALE, z * SCALE)


## 游戏世界 Vector2 → 真实世界 (x, z) 米 — 暂未使用，预留
static func game_to_real(pos: Vector2) -> Dictionary:
	return {"x": pos.x / SCALE, "z": pos.y / SCALE}


## 真实世界 (x, y, z) 米 → 游戏世界 Vector3（3D 使用）
static func real_to_game_3d(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * SCALE, y * SCALE, z * SCALE)
