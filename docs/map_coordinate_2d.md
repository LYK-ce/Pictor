# Map Coordinate (2D)

## 坐标系

| 轴 | 方向 | 说明 |
|------|------|------|
| X | 东（右） | 世界坐标，1 单位 = 1m |
| Y | 南（下） | 世界坐标，1 单位 = 1m |
| Z | 高度 | 2D 模式恒为 0 |

与 Godot 2D 坐标系统一：`Vector2(x * 16, y * 16)`。

## 网格坐标

网格坐标 `(gx, gy)` 与世界坐标一一对应，每格 1m×1m：

```
gx = floor(x)
gy = floor(y)
```

## Chunk 分块

地图以 256×256 格为一个 Chunk 存储：

```
chunk_x = floor(gx / 256)
chunk_y = floor(gy / 256)
local_x = gx - chunk_x * 256
local_y = gy - chunk_y * 256
```

## 存储结构

```gdscript
# ChunkData2D (Resource)
@export var cells: PackedByteArray  # 256×256 = 65536 bytes

# MapData2D
var _chunks: Dictionary = {}  # Vector2i(chunk_x, chunk_y) → ChunkData2D
```

| cell 值 | 含义 |
|------|------|
| 0 | 可通行 (free) |
| 1 | 不可通行 (wall) |

## 坐标转换

```gdscript
# CoordUtils
const SCALE := 16.0

# 世界 → Godot
static func real_to_game(x: float, z: float) -> Vector2:
    return Vector2(x * SCALE, z * SCALE)
```
