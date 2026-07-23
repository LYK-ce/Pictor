# wb_13_camera

## meta
- task: task_13_camera
- start: 2026-07-22
- end:
- status: in-progress

## created / modified
- src/app_state/ — new directory
- src/app_state/app_state.gd — new: AppStateResource class, selected_id
- src/app_state/app_state.tres — new: Resource 实例
- src/event_bus/event_bus.gd — +camera_follow_requested signal
- src/camera/ — new directory
- src/camera/camera_2d.gd — new: 中键拖拽 + 边缘滚动 + 滚轮缩放 + 跟车模式(lerp)
- src/camera/camera_2d.tscn — new: Camera2D scene (+app_state export)
- src/main/main.tscn — +Camera2D node (instance from camera_2d.tscn)
- src/renderer_2d/Vehicle/vehicle_2d.tscn — -Camera2D child
- src/ui/button_list.gd — emit camera_follow_requested
- src/ui/WebSocket/vehicle_panel_manager.gd — +app_state export, 选中/断开时写 selected_id
- src/control/control_master.gd — +app_state export
- src/test/test_ws_server.gd — 速度驱动移动(动量) + 命名/头修复

## design decisions
- Camera 独立于 Vehicle，挂载在 Main 下
- 移动: 中键拖拽(_unhandled_input) + 边缘滚动(_process)
- 缩放: 滚轮，以鼠标位置为中心（position += (pos - anchor) * (new/old - 1)）
- 所有参数 @export: edge_margin, edge_speed, zoom_step, zoom_min, zoom_max
- 共享状态: AppStateResource (.tres)，非 Autoload，消费者 @export 拖入
- 跟车: button_list → EventBus.camera_follow_requested → Camera 自切 _following
- 跟车时禁拖拽/边缘，缩放保留；lerp 平滑；车辆断开自动退出
- zoom_slider、边界限制: 人工处理