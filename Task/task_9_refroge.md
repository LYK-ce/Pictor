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
│   ├── Chunk 分块存储（Array）
│   ├── set_full / set_delta
│   └── signal: chunk_updated
└── Renderer2D (Node2D)           ← 纯渲染，不持有地图数据
    ├── MapContainer2D            ← 订阅 MapData2D.chunk_updated
    │   ├── GroundLayer
    │   └── WallLayer
    └── VehicleContainer
```

- MapData2D 挂在 Main 下，与 Renderer2D 平级
- 可独立单元测试，外部组件可直接查询
- 后续 MapData3D 同理

## 状态

- [x] 进行中
