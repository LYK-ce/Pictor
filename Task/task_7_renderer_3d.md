# Task 7: Renderer3D

## 目标

实现 3D 透视渲染器，包含体素地图、车辆标记、路径线条、自由相机。与 Renderer2D 保持相同信号接口。

## 文件位置

```
src/renderer_3d/
├── renderer_3d.gd           # 父组件，组装子组件 + EventBus 订阅
├── renderer_3d.tscn
├── map_container_3d.gd      # MultiMeshInstance3D 体素渲染
├── map_container_3d.tscn
├── vehicle_marker_3d.gd     # 车辆 3D 模型 + 自由相机
├── vehicle_marker_3d.tscn
├── camera_rig.gd            # 鼠标环顾/缩放/平移（挂在 Vehicle 下）
├── path_line_3d.gd          # 3D 路径线条
└── path_line_3d.tscn
```

## 场景结构

```
Renderer3D (Node3D, renderer_3d.gd)
├── MapContainer3D    (Node3D, map_container_3d.gd)
│   └── MultiMeshInstance3D  ← 预挂
├── VehicleMarker3D   (Node3D, vehicle_marker_3d.gd)
│   └── CameraRig     (Node3D, camera_rig.gd)
│       └── Camera3D  ← 自由视角相机
└── PathLine3D        (Node3D, path_line_3d.gd)
```

## 功能

### Renderer3D（父组件）
- 同 Renderer2D：订阅 EventBus → 转发子组件

### MapContainer3D
- 维护 `_map[gx][gy][gz]` 三层 Dictionary
- 一个 `BoxMesh`(1,1,1) + 3 个 `StandardMaterial3D`（灰/黑/白）
- MultiMeshInstance3D：`multimesh.instance_count = N`，逐个 `set_instance_transform()`
- `set_full` / `set_delta` / `set_cell` 接口与 2D 一致

### VehicleMarker3D
- 3D 车辆模型（初期用 `BoxMesh` 或 `CylinderMesh` 占位）
- `update_pose(x, y, z, yaw)`：`position = CoordUtils.real_to_game_3d(x, y, z)`
- 挂载 CameraRig

### CameraRig
- 鼠标左键拖拽旋转
- 滚轮缩放
- 中键平移
- 围绕车辆旋转（target = vehicle position）

### PathLine3D
- 使用 `draw_line_3d()` 或 ImmediateMesh 绘制路径线条
- 黄色 `#ffd040`

## 与 2D 的差异

| | Renderer2D | Renderer3D |
|------|------|------|
| 根节点 | Node2D | Node3D |
| 地图渲染 | TileMapLayer | MultiMeshInstance3D |
| 存储 | `_map[gx][gz]` | `_map[gx][gy][gz]` |
| 车辆 | `_draw()` 三角形 | BoxMesh/CylinderMesh |
| 相机 | Camera2D（自动跟随） | CameraRig（手动环顾） |
| 坐标转换 | `Vector2(x*16, z*16)` | `Vector3(x*16, y*16, z*16)` |
| 路径 | Line2D | ImmediateMesh 线段 |

## 坐标转换扩展

`CoordUtils` 新增 3D 方法：

```gdscript
static func real_to_game_3d(x: float, y: float, z: float) -> Vector3:
    return Vector3(x * SCALE, y * SCALE, z * SCALE)
```

## 实施步骤

1. 扩展 `CoordUtils` 增加 `real_to_game_3d()`
2. 实现 `map_container_3d.gd` + tscn
3. 实现 `vehicle_marker_3d.gd` + tscn
4. 实现 `camera_rig.gd`
5. 实现 `path_line_3d.gd` + tscn
6. 实现 `renderer_3d.gd` + tscn
7. 更新 `Main` 支持 `mode="3d"` 时实例化 Renderer3D

## 测试

每个子组件独立测试，headless 模式（跳过需要鼠标的 CameraRig）：

| 测试文件 | 测试对象 |
|------|------|
| `test/renderer_3d/test_map_container.gd` | MapContainer3D 存储 + 实例更新 |
| `test/renderer_3d/test_vehicle_marker.gd` | VehicleMarker3D update_pose |
| `test/renderer_3d/test_path_line.gd` | PathLine3D set_points |

## 依赖

- [x] EventBus (task_2)
- [x] Renderer2D (task_6) — 参考实现
- [x] CoordUtils

## 状态

- [x] 已完成 (2026-06-08)
