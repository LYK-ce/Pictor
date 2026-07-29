# wb_14_goto

## meta
- task: task_14_goto
- start: 2026-07-23
- end: 2026-07-29
- status: done

## created / modified
- src/app_state/app_state.gd — +Mode enum, selected_id/mode setter
- src/event_bus/event_bus.gd — +selection_changed, +mode_transited, -camera_follow_requested, -vehicle_control_changed
- src/camera/camera_2d.gd — IDLE/FOLLOW 状态机
- src/ui/button_list.gd — Lock Camera/Goto 写 app_state.mode
- src/ui/WebSocket/vehicle_panel.gd — +Manual CheckButton, set_manual_checked
- src/ui/WebSocket/vehicle_panel_manager.gd — 统一 app_state.selected_id, 模式切换修正
- src/control/control_master.gd — Node→Node2D, +Goto _input 点击下发
- src/utils/coords.gd — +game_to_tile, tile_to_game, tile_to_real
- src/renderer_2d/input_indicator.gd — 新建, tile 高亮框
- src/test/test_ws_server.gd — Robot Controller 模拟 (Manual/Auto + Executor)
- docs/websocket_protocol.md — 对齐 Orion mode/manual/auto 三层

## design decisions
- AppState 双层状态机: 全局 mode + 各组件内部状态机
- mode/selected_id setter → EventBus 信号, 不轮询
- Manual CheckButton 控制模式, Take Control 只负责选中
- ControlMaster(Node2D) 统一 WASD+Goto 输入
- InputIndicator 只做高亮, 不碰输入
- test_ws_server: _turn_rate 持续旋转, MANUAL 位置积分
