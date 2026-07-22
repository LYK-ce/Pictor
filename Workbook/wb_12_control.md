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
- src/control/input_handler.tscn — script path 更新
- event_bus.gd — +vehicle_control_changed(vehicle_id), +cmd_send(vehicle_id, cmd)
- vehicle_panel.gd — -_on_control_area_gui_input, +set_selected(bool) StyleBoxFlat 切换
- vehicle_panel.tscn — -gui_input connection
- vehicle_panel_manager.gd — +_selected_id, +Control_Area.gui_input connect, +toggle logic, +_update_selection()
- websocket_manager.gd — +_on_cmd_send → send JSON
- main.tscn — +ControlMaster node
- Architecture/architecture.md — updated scene structure, 11 signals, cmd+selection data flows

## design decisions
- 选中三层职责: Panel(纯UI) → PanelManager(唯一真相源+高亮) → ControlMaster(消费)
- cmd 链路: InputHandler→ControlMaster→cmd_send→WebSocketManager→WS.send()
- vehicle_control_changed 空字符串 = 取消选中
- Control_Area.gui_input 由 PanelManager 动态 connect，不在 tscn 中预连
