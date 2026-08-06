# Task 19: UI update — 坐标标尺 + 鼠标格子定位

## 目标

实现棋盘式坐标辅助 UI：

1. **屏幕上方显示 X 轴标尺**，**屏幕左侧显示 Y 轴标尺**（Excel 表头式：固定屏幕边缘，刻度随相机平移/缩放实时变化），刻度数字标注 tile 网格坐标
2. **鼠标在地图上移动时**，在角落状态栏实时显示鼠标所在 tile 格子坐标

## 设计决策（2026-08-06 与用户确认）

| 项 | 决定 |
|------|------|
| 标尺跟随方式 | Excel 表头式：标尺条固定屏幕边缘，刻度数字随相机变换实时重绘 |
| 刻度密度 | 每 8 格标一个数字（tile 尺寸 16px）；缩放过小时启用密度保护（自动跳 16/32 格） |
| 坐标显示 | Tile 格子坐标 `(gx, gy)`（与 MapData2D cell 坐标系一致） |
| 鼠标定位显示 | 固定角落状态栏（非 tooltip） |
| 网格线 | 不画（用户未选） |
| 坐标转换 | `CoordUtils.game_to_tile()`（world px → tile）；鼠标世界坐标用 `Camera2D.get_global_mouse_position()` |
| 渲染 | CanvasLayer + Control 覆写 `_draw()`（draw_line + draw_string） |

## 架构

```
main.tscn
└── UI (CanvasLayer)
    └── CoordinateRuler (CanvasLayer / Control)
        ├── 上方 X 轴标尺条  ← _draw: 刻度线 + gx 数字（每 8 格）
        ├── 左侧 Y 轴标尺条  ← _draw: 刻度线 + gy 数字（每 8 格）
        └── 角落状态栏 Label ← _process: 鼠标 world → game_to_tile → "格子: (gx, gy)"

相机变换 → 可视世界区域 → tile 范围 → 刻度/数字绘制
```

## 子任务

- [ ] 1. `coordinate_ruler.gd` — 标尺条绘制（上 X / 左 Y，每 8 格标数字，密度保护）
- [ ] 2. 状态栏 — 实时显示鼠标 tile 坐标
- [ ] 3. 接入 `main.tscn`（@export camera 注入）
- [ ] 4. headless 验证 + 运行测试（缩放/平移/负坐标区域）

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/ui/coordinate_ruler/coordinate_ruler.gd` | 新建 | 标尺 + 状态栏逻辑 |
| `src/ui/coordinate_ruler/coordinate_ruler.tscn` | 新建 | 组件场景 |
| `src/main/main.tscn` | 修改 | 实例化 CoordinateRuler |
| `src/utils/coords.gd` | 只读 | 依赖 `game_to_tile` |

## 依赖

- Camera2D（变换读取）
- CoordUtils（坐标转换）
