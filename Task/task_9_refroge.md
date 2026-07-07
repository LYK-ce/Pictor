# Task 9: Refroge — 2D TileMap 重构 & 纹理化

## 目标

将代码生成的纯色 TileMap 替换为基于纹理资源的双层 autotile 系统，提升地图渲染品质。

## 已完成

### TileSet 配置
- `Assets/2D/tile_set.tres` — Godot 编辑器配置的 TileSet
- 2 个 terrain：`Walls`(0) + `ground`(1)
- 8 方向墙 tile + 地面 tile，全部 16×16px
- Bitmask 对齐：north/south/east/west/northeast/northwest/southeast/southwest

### MapContainer2D 重构
- 双层 TileMapLayer：`GroundLayer`(底层全铺) + `WallLayer`(顶层障碍物)
- `@export var tile_set: TileSet` → tscn 直接加载 `tile_set.tres`
- `set_full()` → GroundLayer batch set + WallLayer batch set（`set_cells_terrain_connect` autotile）
- `set_delta()` → 逐格增量更新两层
- 删除代码生成 Image/Color 逻辑，精简至 100 行

### Renderer2D 适配
- Camera2D 改为动态创建挂 VehicleContainer
- 修复 `_ready` 中 emit zoom 时序（Camera 先创建）

## 文件清单

| 文件 | 变更 |
|------|------|
| `Assets/2D/tile_set.tres` | 新增 |
| `Assets/2D/ground.png` | 新增 |
| `Assets/2D/north.png ~ southwest.png` | 新增（8 张墙方向） |
| `Assets/2D/tilemap_2.png` | 新增（tileset 大图） |
| `src/renderer_2d/map_container_2d.gd` | 重写 |
| `src/renderer_2d/map_container_2d.tscn` | GroundLayer + WallLayer |
| `src/renderer_2d/renderer_2d.gd` | Camera 时序修复 |

## 待完成

- [ ] 3D Renderer 集成到 Main
- [ ] 3D 方向纹理支持

## 状态

- [x] 进行中
