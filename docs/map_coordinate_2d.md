# Map Coordinate (2D)

## 坐标系

- **原点 (0, 0)**：0号车启动时的位置
- **X 轴**：东（右），**Z 轴**：南（下），**Y 轴**：高度（2D 模式恒为 0）
- 右手坐标系，Z-up

## 网格坐标

世界坐标 (x, z) 通过网格大小 `cell_size` 转换为网格坐标 (gx, gz)：

```
gx = floor(x / cell_size)
gz = floor(z / cell_size)
```

默认 `cell_size = 0.1`（10cm 精度）。

## 存储结构

使用两层嵌套 Dictionary：

```gdscript
# map: Dictionary[int, Dictionary[int, Dictionary]]
# map[gx][gz] = {"state": int, "conf": float, "ts": float, "source": String}

var _map := {}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `state` | int | 0=未知, 1=空闲, 2=占用 |
| `conf` | float | 置信度 0.0~1.0 |
| `ts` | float | 更新时间戳 |
| `source` | String | 传感器来源（"lidar", "camera", "radar"） |

## 操作

### 全量更新（voxel_full）
```gdscript
func set_full(voxels: Array) -> void:
    _map.clear()
    for v in voxels:
        set_cell(v.gx, v.gz, v.state, v.conf, v.ts, v.source)
```

### 增量更新（voxel_delta）
```gdscript
func set_delta(voxels: Array) -> void:
    for v in voxels:
        set_cell(v.gx, v.gz, v.state, v.conf, v.ts, v.source)
```

### 单格更新
```gdscript
func set_cell(gx: int, gz: int, state: int, conf: float, ts: float, source: String) -> void:
    if not _map.has(gx):
        _map[gx] = {}
    _map[gx][gz] = {"state": state, "conf": conf, "ts": ts, "source": source}
```

### 查询
```gdscript
func get_cell(gx: int, gz: int) -> Dictionary:
    if _map.has(gx) and _map[gx].has(gz):
        return _map[gx][gz]
    return {"state": 0, "conf": 0.0}  # 未知
```

### 遍历所有非空格子
```gdscript
func get_all_cells() -> Array:
    var cells := []
    for gx in _map:
        for gz in _map[gx]:
            cells.append({"gx": gx, "gz": gz, "data": _map[gx][gz]})
    return cells
```

## 集群多车对齐

其他车加入时，通过 0号车广播的位姿进行坐标变换：

```
offset_x = car0.x - self.x
offset_z = car0.z - self.z

本地坐标 → 全局坐标：
global_gx = local_gx + offset_x
global_gz = local_gz + offset_z
```
