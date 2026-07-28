## Presented by KeJi
## Date ： 2026-07-28
##
## CoordUtils — 真实世界 ↔ 游戏世界坐标转换，纯静态函数

class_name CoordUtils
extends RefCounted

const SCALE := 32.0          # 1 米 = 32 像素
const TILE_SIZE := 16.0      # 1 tile = 16 像素


## 真实世界 (x, z) 米 → 游戏世界 Vector2
static func real_to_game(x: float, z: float) -> Vector2:
	return Vector2(x * SCALE, z * SCALE)


## 游戏世界 Vector2 → 真实世界 (x, z) 米 — 暂未使用，预留
static func game_to_real(pos: Vector2) -> Dictionary:
	return {"x": pos.x / SCALE, "z": pos.y / SCALE}


## 真实世界 (x, y, z) 米 → 游戏世界 Vector3（3D 使用）
static func real_to_game_3d(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * SCALE, y * SCALE, z * SCALE)


## 游戏世界坐标 (px) → tile 网格坐标
static func game_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))


## tile 网格坐标 → tile 中心游戏世界位置 (px)
static func tile_to_game(gx: int, gy: int) -> Vector2:
	return Vector2(gx * TILE_SIZE + TILE_SIZE / 2.0, gy * TILE_SIZE + TILE_SIZE / 2.0)


## tile 网格坐标 → 真实世界坐标 (x, y) 米，取 tile 中心点
static func tile_to_real(gx: int, gy: int) -> Vector2:
	return Vector2((gx + 0.5) * 0.5, (gy + 0.5) * 0.5)
