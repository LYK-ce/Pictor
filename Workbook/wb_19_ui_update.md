# wb_19_ui_update

开始时间: 2026-08-06（实现） / 2026-08-07（归档）

## 任务
task_19_ui_update：棋盘式坐标辅助 UI —— Excel 表头式 X/Y 轴标尺（每 8 格标数字 + 密度保护）+ 左下角状态栏实时鼠标 tile 坐标。已接入 main.tscn（UI/Scale 节点）。

## 实现（2026-08-06 完成，2026-08-07 核查确认）
- 目录：`src/ui/scaler/`（scale.gd + axis_ruler.gd + scale.tscn）—— 与任务约定 `coordinate_ruler/` 命名不符，功能等效
- `scale.gd`（Scale extends Control）：自动获取 `get_viewport().get_camera_2d()`；_process 缓存相机 center/zoom 变化 → queue_redraw；状态栏 `game_to_tile(get_global_mouse_position())` 显示 "格子: (gx, gy) 世界: (x, y)"
- `axis_ruler.gd`（AxisRuler extends Control）：_draw 用 `camera.get_canvas_transform()` 映射世界→屏幕；每格小刻度，每 8 格主刻度+数字；密度保护 `_step=8; while _step*tile*zoom < 40px: _step*=2`（上限 64）；负坐标 floori 正确
- 相机判空兜底（printerr + _process 重查），无崩溃
- 文件头 `Presented by KeJi` ✅；常数 UPPER_SNAKE ✅

## 核查发现（2026-08-07 子 agent 报告）
- 子任务④（headless 验证 + 缩放/平移/负坐标测试）缺失
- 缺陷（中）：x_axis/y_axis 未设 mouse_filter=IGNORE → 顶部/左侧 24px 条带吞鼠标事件（滚轮缩放/中键拖拽/贴边滚动失效）
- 缺陷（低）：状态栏 PanelContainer offset_right=76 固定宽，长坐标裁剪；左上角 24×24 重叠；_step 上限 64 与设计 32 不符（zoom_min=0.2 时实际只到 16）
- 无 wb_19 记录（本次补建）

## 决策
- 2026-08-07 用户决定直接归档 task_19（缺陷与验证未补齐，留待后续修复/新任务处理）

结束时间: 2026-08-07（归档）
