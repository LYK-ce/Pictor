# wb_12_control

## meta
- task: task_12_control
- start: 2026-07-22
- end: 2026-07-22
- status: done

## created / modified
- src/control/ — renamed from input_handler/
- src/control/control_master.gd — new: 监听 vehicle_control_changed/vehicle_unregistered, 中转 ctrl_input → cmd_send
- src/control/control.tscn — new: ControlMaster + InputHandler
- src/control/input_handler.gd — signal ctrl_input(cmd) 替代 EventBus.ctrl_send
- event_bus.gd — +vehicle_control_changed, +cmd_send, +cells_changed
- vehicle_panel.gd — Take Control toggle button: +take_control_toggled signal, +set_selected(), +set_pressed()
- vehicle_panel.tscn — +TakeControl Button (toggle_mode), -Control_Area connection
- vehicle_panel_manager.gd — take_control_toggled 信号 → 切换+高亮, emit vehicle_control_changed
- websocket_manager.gd — +_on_cmd_send → send JSON
- main.tscn — +ControlMaster, WebSocketMenu 包入 CanvasLayer
- renderer_2d.gd — pose.y 修复; +cells_changed → update_cells
- map_data_2d.gd — save_chunk 注释; set_chunk_delta emit cells_changed 替代 chunk_updated
- map_container_2d.gd — 双清 GroundLayer/WallLayer; state>=2 不渲染; +update_cells() 增量
- vehicle_2d.tscn — +Camera2D
- vehicle_marker_2d.gd/.tscn/.uid — 删除（死代码）

## design decisions
- 选中: Take Control toggle button 替代 Control_Area 点击；Panel 自己监听发信号 → PanelManager 决策
- cmd 链路: InputHandler→ControlMaster→cmd_send→WebSocketManager→WS.send()
- 地图渲染: map_delta → cells_changed 增量更新 (N 个 cell)；map_full → chunk_updated 全量渲染
- 注释 _save_chunk 消除 delta 磁盘 IO 卡顿
- pose.y 替代 pose.z（2D 地图用 y 而非高度 z）
- CanvasLayer 隔离 UI，避免 Camera2D 拖动
