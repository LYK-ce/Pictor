# wb_13_camera

## meta
- task: task_13_camera
- start: 2026-07-22
- end:
- status: in-progress

## created / modified
- src/camera/ — new directory
- src/camera/camera_2d.gd — new: 中键拖拽 + 边缘滚动 + 滚轮缩放(以鼠标为中心)
- src/camera/camera_2d.tscn — new: Camera2D scene
- src/main/main.tscn — +Camera2D node (instance from camera_2d.tscn)
- src/renderer_2d/Vehicle/vehicle_2d.tscn — -Camera2D child
- src/test/test_ws_server.gd — 速度驱动移动(动量) + 命名/头修复

## design decisions
- Camera 独立于 Vehicle，挂载在 Main 下
- 移动: 中键拖拽(_unhandled_input) + 边缘滚动(_process)
- 缩放: 滚轮，以鼠标位置为中心（position += (pos - anchor) * (new/old - 1)）
- 所有参数 @export: edge_margin, edge_speed, zoom_step, zoom_min, zoom_max
- 跟踪车辆、zoom_slider、边界限制: 人工处理