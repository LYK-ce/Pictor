# wb_5_test_tool

## meta
- task: task_5_test_tool
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- test/test_tool/mock_car_server.py — Python asyncio WebSocket server
- test/test_tool/requirements.txt — websockets>=12.0

## design
- CarState: 完整小车运动模型（前进/后退/转向/急停）
- 10×10 voxel_world：四周围墙，内部空地
- 10Hz pose 发送 + 5s 间隔随机障碍物
- asyncio.create_task 并行 recv/send
- Ctrl-C 优雅退出

## verify
- Python 3.13.2, websockets installed
- Syntax check passed
- Port 9001 bind OK (pre-existing process caused addr-in-use, expected)

## deps resolved
- task_2 EventBus, task_3 InputHandler, task_4 WebSocketClient
- docs/protocol.md
