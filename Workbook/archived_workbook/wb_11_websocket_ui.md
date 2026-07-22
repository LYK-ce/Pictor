# wb_11_websocket_ui

## meta
- task: task_11_websocket_ui
- start: 2026-07-20
- end: 2026-07-22
- status: done

## created / modified
- event_bus.gd — +vehicle_registered, vehicle_unregistered, ws_disconnect_requested; pose_received +vehicle_id; map_full_received → binary
- websocket_client.gd — hello parse → vehicle_registered; binary frame → map_full; text/binary dispatch
- websocket_manager.gd — _vehicles Dict, url temp key → vehicle_id on hello; disconnect → vehicle_unregistered
- renderer_2d.gd — _vehicles Dict multi-sprite; vehicle_registered/unregistered signals
- renderer_3d.gd — pose_received signature sync
- vehicle_panel.gd — Update() impl; disconnect → ws_disconnect_requested
- vehicle_panel_manager.gd — _panels Dict; 3 signals
- map_data_2d.gd — set_full(chunk_x, chunk_y, PackedByteArray) direct
- map_container_2d.gd — skip state=2 unknown
- test_ws_server.gd — @export vehicle_id/port/send_map; hello; 10Hz pose; binary map_full
- websocket_menu.tscn — VehiclePanelManager export
- websocket_protocol.md — hello+address; binary map_full; map_delta; 0.5m/cell

## findings
- 1.5MB JSON → 64KB binary: 23x smaller, no stutter
- disconnect 需手动 emit vehicle_unregistered (close_connection 原来漏了)
- AABB vs Circle 检测比 cell-center 准确，但 r=0.5 时只有相邻格能检测到
- map_full 先于 hello 到达时丢弃 → _identified flag 保护
- 3 车测试: car_a(9090,map) + car_b(9091) + car_c(9092) 全部正常
