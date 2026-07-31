# wb_15_protocol

## meta
- task: task_15_protocol
- start: 2026-07-29
- end: 2026-07-29
- status: completed
## changes
- created: src/websocket/protocol/protocol_def.gd (枚举/常量)
- created: src/websocket/protocol/message_parser.gd (上行解析)
- created: src/websocket/protocol/message_builder.gd (下行构造)
- modified: websocket_client.gd (接入 MessageParser)
- modified: control_master.gd (接入 MessageBuilder)
- modified: vehicle_panel.gd (接入 MessageBuilder)
- modified: vehicle_panel_manager.gd (接入 MessageBuilder)
- modified: input_handler.gd (接入 MessageBuilder)
- modified: docs/websocket_protocol.md (添加引用)
