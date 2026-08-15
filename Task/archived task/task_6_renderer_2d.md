# Task 6: Renderer2D

## 目标

实现 2D 俯视渲染器，包含体素地图、车辆标记、路径线条三个独立子组件。通过 EventBus 接收数据并实时更新画面。

## 文件位置

```
src/renderer_2d/
├── renderer_2d.gd           # 父组件，组装子组件 + EventBus 订阅
├── renderer_2d.tscn
├── map_container_2d.gd      # TileMapLayer 体素渲染
├── map_container_2d.tscn
├── vehicle_marker_2d.gd     # 车辆三角形标记
├── vehicle_marker_2d.tscn
├── path_line_2d.gd          # 路径线条
└── path_line_2d.tscn
```

## 场景结构

```
Renderer2D (Node2D, renderer_2d.gd)
├── MapContainer2D    (Node2D, map_container_2d.gd)
│   └── TileMapLayer  ← 预挂，世界坐标固定
├── VehicleMarker2D   (Node2D, vehicle_marker_2d.gd)
│   └── Camera2D      ← 预挂，跟随车辆，始终居中
└── PathLine2D        (Node2D, path_line_2d.gd)
    └── Line2D        ← 预挂，世界坐标路径
```

## 功能

### Renderer2D（父组件）

- `_ready()`：创建三个子组件，订阅 EventBus 信号
- `pose_received` → 转发给 VehicleMarker2D + MapContainer2D（重新定位）
- `voxel_received` → 转发给 MapContainer2D
- `path_received` → 转发给 PathLine2D

### MapContainer2D

- 维护 `_map` Dictionary（两层嵌套 `_map[gx][gz]`）
- 运行时动态创建 TileSet（3 个纯色 tile）
- `set_full(voxels)` / `set_delta(voxels)` / `set_cell(gx, gz, state, conf)`
- 在 `_map` 有更新的格子对应的 TileMapLayer 坐标上 `set_cell()`
- TileMapLayer 固定在世界坐标系，格子增删不改已有 tile 位置
- 当前实现不设 view_radius 过滤（全量渲染，后续优化）

### VehicleMarker2D

- 蓝色三角形，尖端指向 `yaw` 方向（`_draw()`）
- 预挂 Camera2D（`current = true`），自动跟随车辆居中
- `update(x, z, yaw)`：`position = Vector2(x, z)` + `rotation = yaw`
- 坦克式操纵：A/D → yaw 变化 → 三角原地旋转，W/S → position 沿朝向移动

### PathLine2D

- 黄色 Line2D 节点
- `set_points(points)`：直接使用世界坐标 (x, z) 作为 Line2D.points
- 与 TileMap、Vehicle 在同一世界坐标系，自然对齐

## 颜色映射

| state | 颜色 | 说明 |
|------|------|------|
| 0 未知 | 灰色 `#404040` | 不渲染（跳过） |
| 1 空闲 | 黑色 `#000000` | 可通过 |
| 2 占用 | 白色 `#ffffff` | 障碍物 |

置信度 → alpha 通道：`modulate.a = conf`

## 配置项

在 `project.godot` 中添加：

```ini
[renderer_2d]
cell_size=0.1
```

## 实施步骤

1. 创建 `map_container_2d.gd`
   - 实现 `_map` Dict + CRUD 操作
   - 实现 TileSet 动态创建
   - 实现 `update_visible(car_x, car_z)` 半径过滤 + TileMapLayer.set_cell()

2. 创建 `vehicle_marker_2d.gd`
   - 使用 `_draw()` 画三角形
   - 实现 `update(x, z, yaw)`

3. 创建 `path_line_2d.gd`
   - 使用 Line2D 节点
   - 实现 `set_points(points)`

4. 创建 `renderer_2d.gd`
   - `_ready()` 组装子组件 + 订阅 EventBus
   - 信号转发

5. 创建 `renderer_2d.tscn`

## 测试

每个子组件独立测试，可单独运行：

| 测试文件 | 测试对象 | 用例数 |
|------|------|------|
| `test/renderer_2d/test_map_container.gd` | MapContainer2D | 存储、全量、增量、坐标转换、渲染范围 |
| `test/renderer_2d/test_vehicle_marker.gd` | VehicleMarker2D | update 参数传递、_draw 三角形 |
| `test/renderer_2d/test_path_line.gd` | PathLine2D | set_points、坐标转换 |

运行方式：
```bash
godot --headless --display-driver headless --path . --script test/renderer_2d/test_map_container.gd
```

### 测试用例详情

#### test_map_container.gd

1. **set_cell → get_cell 数据一致**：写入后读出，state/conf/ts/source 全匹配
2. **set_full 覆盖旧数据**：先写旧地图 → set_full 新地图 → 旧格子被清除
3. **set_delta 不覆盖其他格子**：set_full 10格 → set_delta 1格 → 总数=11
4. **world_to_tile 坐标转换**：(1.23, 4.56) → (12, 45) at cell_size=0.1
5. **get_all_cells 遍历正确**：写入 N 个 → 遍历返回 N 个

#### test_vehicle_marker.gd

1. **update 设置 position + rotation**：update(1.5, 3.2, 0.785) → position=(1.5, 3.2), rotation=0.785
2. **Camera2D 存在**：VehicleMarker2D 下有 Camera2D 子节点且 current=true

#### test_path_line.gd

1. **set_points 传递**：set_points([{x:0,z:0}, {x:1,z:1}]) → Line2D.points 包含 2 个点
2. **空路径**：set_points([]) → Line2D.points 为空，不崩溃

## 依赖

- [x] EventBus (task_2)
- [x] docs/map_coordinate_2d.md
- [x] docs/renderer_2d.md

## 状态

- [x] 已完成 (2026-06-08)
