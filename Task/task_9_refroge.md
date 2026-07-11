# Task 9: Refroge

## 目标

重构项目入口，逐步恢复并修复 2D 渲染，并将地图存储从固定范围 Dictionary 改为 Chunk 分块系统。

## 已完成

- [x] `main.tscn` — 清理所有子节点，挂载 `renderer_2d_scene` export
- [x] `main.gd` — 简化为启动直接挂载 2D Renderer，移除 Menu 逻辑
- [x] `renderer_2d` — 移除 PathLine2D

## 待完成

### 架构调整：MapData2D 独立于 Renderer2D

```
Main
├── MapData2D (Node)              ← 独立数据节点，与 Renderer 平级
│   ├── Chunk: 256×256 格，每 Chunk 一个 .tres 持久化
│   ├── SparseChunkMap: Dictionary{chunk_coord → Chunk}，按需懒加载
│   ├── set_full / set_delta → 定位 Chunk → 局部更新
│   └── signal: chunk_updated(chunk_coord)
└── Renderer2D (Node2D)           ← 纯渲染，不持有地图数据
    ├── MapContainer2D            ← 订阅 MapData2D.chunk_updated
    │   ├── GroundLayer
    │   └── WallLayer
    └── VehicleContainer
```

- MapData2D 挂在 Main 下，与 Renderer2D 平级
- 可独立单元测试，外部组件可直接查询
- 后续 MapData3D 同理

### Chunk 命名与坐标

- 文件命名：`map_chunk_{x}_{y}.tres`
- Chunk 尺寸：256×256 格
- `x`/`y` 方向与 Godot 坐标一致：+X 右、+Y 下

```
map_chunk_-1_-1    map_chunk_0_-1    map_chunk_1_-1      ← 上排
map_chunk_-1_0     map_chunk_0_0     map_chunk_1_0       ← 原点
map_chunk_-1_1     map_chunk_0_1     map_chunk_1_1       ← 下排
```

- 全局坐标 ↔ Chunk 换算：
  - `chunk_x = floor(gx / 256)`, `chunk_y = floor(gy / 256)`
  - Chunk `(0, 0)` 覆盖全局 `[0, 255] × [0, 255]`
  - Chunk 内局部坐标：`local_x = gx - chunk_x * 256`, `local_y = gy - chunk_y * 256`
- SparseChunkMap: `Dictionary{Vector2i(chunk_x, chunk_y) → Chunk}`，仅加载被访问的 Chunk
- 持久化路径：`user://map_data_2d/map_chunk_{x}_{y}.tres`

### Chunk 数据格式

`.tres` 中存储 `PackedByteArray`，一维数组表示 256×256 网格：

```gdscript
# Chunk 内部
var cells: PackedByteArray  # 65536 bytes
# index = local_y * 256 + local_x
# cells[index] = 0  → 可通行
# cells[index] = 1  → 不可通行
```

### MapData2D API

```gdscript
# ── 全局入口（供 WebSocket 数据接入） ──

# 全量更新（体素格式: [{gx, gy, state}, ...]）
func set_full(voxels: Array) -> void
# 内部：按坐标分组到 Chunk → set_chunk_full → save → emit chunk_updated

# 增量更新
func set_delta(voxels: Array) -> void
# 内部：按坐标分组到 Chunk → set_chunk_delta → save → emit chunk_updated

# ── Chunk 级操作 ──

# 全量覆盖某个 Chunk（65536 bytes）
func set_chunk_full(chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void

# 增量更新某个 Chunk（只传变化的格子）
func set_chunk_delta(chunk_x: int, chunk_y: int, updates: Array) -> void
# updates = [{lx: 10, ly: 20, state: 0}, {lx: 11, ly: 20, state: 1}, ...]

# 查询单格
func get_cell(gx: int, gy: int) -> int

# 获取 Chunk 数据（供 Renderer2D 调用）
func get_chunk_cells(chunk_x: int, chunk_y: int) -> PackedByteArray

# 从磁盘加载已有 Chunk
func load_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray

# 信号
signal chunk_updated(chunk_x: int, chunk_y: int)
```

- MapData2D 挂在 Main 下，设置 `unique_name_in_owner = true`
- 全场景通过 `%MapData2D` 唯一访问，不依赖路径
- 所有写入操作后自动 `ResourceSaver.save()` 持久化
- `set_full` / `set_delta` 是全局入口，内部按坐标分组到各 Chunk
- `load_chunk` 从磁盘读 `.tres`，Chunk 不存在返回空 PackedByteArray

### Renderer2D 适配

- [ ] `_ready()` — 移除 `voxel_received` 订阅，改为订阅 `chunk_updated`
- [ ] 删除 `_on_voxel` 方法
- [ ] 新增 `_on_chunk_updated(chunk_x, chunk_y)`：
  - `%MapData2D.get_chunk_cells(cx, cy)` → `_map.render_chunk(cx, cy, cells)`

### MapContainer2D 重构

- [ ] 删除旧的数据存储逻辑：`_map` Dictionary、`set_full`/`set_delta`/`set_cell`/`get_cell`/`get_all_cells`、`_ready()` 中的初始填充
- [ ] 新增 `render_chunk(chunk_x, chunk_y, cells: PackedByteArray)`：
  - 遍历 cells → 分 ground_cells / wall_cells
  - 分别 `set_cells_terrain_connect`

### EventBus 信号变更

新增：

```gdscript
signal chunk_updated(chunk_x: int, chunk_y: int)
```

流向：`MapData2D → EventBus.chunk_updated → Renderer2D`

现有信号适配：

| 信号 | 变更 |
|------|------|
| `voxel_received` | 订阅者改为 MapData2D（原为 Renderer2D） |
| `path_received` | 删除（PathLine2D 已移除，无订阅者） |
| `pose_received`, `ctrl_send`, `zoom_changed`, `ws_connected` | 不变 |

### 下一步：Chunk 渲染验证

- [ ] 创建 `ChunkData2D` Resource 类（`extends Resource`, `@export var cells: PackedByteArray`）
- [ ] 创建 `MapData2D` 节点脚本（`src/renderer_2d/map_data_2d.gd`），实现 API
- [ ] 用脚本生成 `map_chunk_0_0.tres`（随机 0/1），放到 `user://map_data_2d/`
- [ ] `main.gd._ready()` 挂载 MapData2D → `load_chunk(0,0)` → emit `chunk_updated`
- [ ] `Renderer2D` 订阅 `chunk_updated`，调用 `MapContainer2D.render_chunk()`
- [ ] `MapContainer2D` 实现 `render_chunk`，旧数据逻辑全部删除

## 状态

- [x] 进行中
