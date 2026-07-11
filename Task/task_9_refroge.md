# Task 9: Refroge

## 目标

重构项目入口，逐步恢复并修复 2D 渲染，并将地图存储从固定范围 Dictionary 改为 Chunk 分块系统。

## 已完成

- [x] `main.tscn` — 清理所有子节点，挂载 `renderer_2d_scene` export
- [x] `main.gd` — 简化为启动直接挂载 2D Renderer，移除 Menu 逻辑
- [x] `map_container_2d` — `_ready()` 铺满 [-100,100] ground + 随机墙壁
- [x] `tile_set.tres` — 补充孤立墙 tile (11,6)，autotile 恢复正常
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
  - `chunk_x = floor(gx / 256)`, `chunk_y = floor(gz / 256)`
  - Chunk `(0, 0)` 覆盖全局 `[0, 255] × [0, 255]`
  - Chunk 内局部坐标：`local_x = gx - chunk_x * 256`, `local_y = gz - chunk_y * 256`
- SparseChunkMap: `Dictionary{Vector2i(chunk_x, chunk_y) → Chunk}`，仅加载被访问的 Chunk
- 持久化路径：`user://map_data_2d/map_chunk_{x}_{y}.tres`

## 状态

- [x] 进行中
