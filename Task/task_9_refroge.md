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

### 架构调整：Renderer2D 拆分数据层 + 渲染层

目标结构：

```
Renderer2D
├── MapData2D (Node)              ← 独立数据节点，纯数据层
│   ├── Chunk 分块存储（Array）
│   ├── set_full / set_delta
│   └── signal: chunk_updated
├── MapContainer2D (Node2D)       ← 纯渲染层，不持有地图数据
│   ├── GroundLayer / WallLayer
│   └── 订阅 MapData2D.chunk_updated → 局部重绘
└── VehicleContainer (Node2D)
```

- [ ] 创建 `src/renderer_2d/map_data_2d.gd` + `map_data_2d.tscn`
  - Chunk 固定大小（如 16×16），Array 存储
  - SparseChunkMap: Dictionary{chunk_coord → Chunk}，按需分配
  - `set_delta` 只更新受影响的 Chunk
  - signal `chunk_updated(chunk_coord)`
- [ ] `MapContainer2D` 剥离数据存储，改为接收 `chunk_updated` 信号驱动渲染
- [ ] 后续 `MapData3D` 同理

## 状态

- [x] 进行中
