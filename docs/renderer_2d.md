# Renderer 2D (TileMap)

## 渲染方式

使用 Godot 内置 `TileMapLayer`，以小车为中心展示周围一定范围的体素地图。

## 核心参数

| 参数 | 默认值 | 说明 |
|------|------|------|
| `cell_size` | 0.1m | 每格对应世界 10cm |
| `view_radius` | 50 格 | 小车周围渲染半径（5m） |

## Tile 颜色映射

| state | 颜色 | 说明 |
|------|------|------|
| 0 未知 | 灰色 `#404040` | 未探索 |
| 1 空闲 | 黑色 `#000000` | 可通过 |
| 2 占用 | 白色 `#ffffff` | 障碍物 |

置信度控制透明度：`alpha = conf`（0.5 → 半透明，1.0 → 完全不透明）

## 实现方案

### 1. TileSet 配置

运行时动态创建 TileSet，3 个 Atlas Tile，对应 3 种 state：

```gdscript
var _tileset := TileSet.new()
var _tile_layer: TileMapLayer
var _atlas_id: int
```

每个 tile 是一个 1×1 纯色矩形。

### 2. 坐标转换

世界坐标 → TileMap 格子坐标：

```gdscript
func world_to_tile(x: float, z: float) -> Vector2i:
    return Vector2i(floor(x / cell_size), floor(z / cell_size))
```

### 3. 以车为中心，只渲染范围内

```gdscript
func update_visible(car_x: float, car_z: float) -> void:
    var center := world_to_tile(car_x, car_z)
    var r := view_radius

    # 清除上一帧所有旧 tile
    _tile_layer.clear()

    # 遍历地图 Dict，只渲染范围内的格子
    for gx in _map:
        if abs(gx - center.x) > r: continue
        for gz in _map[gx]:
            if abs(gz - center.y) > r: continue
            var data = _map[gx][gz]
            _tile_layer.set_cell(
                Vector2i(gx - center.x + r, gz - center.y + r),
                _atlas_id,
                _get_tile_coord(data.state),
            )
```

### 4. TileMapLayer 固定不动，车在屏幕中央

TileMapLayer 的格子始终以车为中心偏移。相机固定在 TileMapLayer 上方俯视。

## 数据流

```
voxel_received → Map dict 更新
pose_received  → 触发 update_visible(car_x, car_z)
               → TileMapLayer.set_cell() 重绘范围内所有 tile
```

## 与 Renderer2D 集成

`Renderer2D` 挂载三个子组件：

```
Renderer2D (Node2D)
├── MapContainer2D       ← TileMapLayer 体素渲染
│   └── TileMapLayer     ← 预挂节点，世界坐标固定
├── VehicleMarker2D      ← 车辆位置 + 朝向（_draw 三角形）
│   └── Camera2D         ← 跟随车辆，current=true
└── PathLine2D           ← 规划路径线条
    └── Line2D           ← 预挂节点
```

### VehicleMarker2D

- **形状**：蓝色三角形（`_draw()`），尖端指向 `yaw` 方向
- **跟随**：预挂 Camera2D (`current = true`)，自动居中
- **更新**：`pose_received` → `position = Vector2(x, z)` + `rotation = yaw`

### PathLine2D

显示规划路径：

- **实现**：`Line2D` 节点，`points` 为路径点序列（世界坐标）
- **颜色**：黄色 `#ffd040`
- **更新**：`path_received` → `Line2D.points = path_array`
