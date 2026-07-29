# Task 15: Protocol

## 目标

将散落在项目各处的 Protocol 实现整合到 `src/websocket/protocol/` 目录下。

## 架构

```
src/websocket/
├── protocol/
│   ├── protocol_def.gd       ← 枚举/常量（消息 type、cmd、action、state 等）
│   ├── message_builder.gd    ← 下行消息构造（mode / manual / auto push）
│   └── message_parser.gd     ← 上行消息解析（hello / pose / map_delta / map_full 二进制）
├── websocket_client.gd       ← 改为调用 message_parser
└── websocket_manager.gd      ← 不变
```

## 边界

| 组件 | 归属 | 原因 |
|------|------|------|
| CoordUtils | `utils/` 保持 | 通用坐标工具，多模块共用 |
| InputHandler 按键映射 | `control/` 保持 | 输入层逻辑，protocol 只定义 cmd schema |
| map_full 二进制解析 | 提取到 `message_parser` | 所有消息解析统一 |
| websocket_protocol.md | `docs/` 保持 | 文档与代码分离 |

## 各文件提取清单

### → message_parser.gd（上行解析）

| 来源 | 内容 |
|------|------|
| `websocket_client.gd` | hello 消息解析 + vehicle_registered emit |
| `websocket_client.gd` | pose 消息解析 + pose_received emit |
| `websocket_client.gd` | map_delta 消息解析 + map_delta_received emit |
| `websocket_client.gd` | map_full 二进制帧解析 (type=0) + map_full_received emit |

### → message_builder.gd（下行构造）

| 来源 | 内容 |
|------|------|
| `control_master.gd` | `{"cmd": "manual", "action": "stop"}` |
| `control_master.gd` | `{"cmd": "auto", "action": "push", "missions": [...]}` |
| `vehicle_panel.gd` | `{"cmd": "mode", "action": "switch_to_manual/auto"}` |
| `vehicle_panel_manager.gd` | `{"cmd": "mode", "action": "switch_to_auto"}` |
| `input_handler.gd` | `{"cmd": "manual", "action": "forward/backward/..."}` |

### → protocol_def.gd（常量/枚举）

| 内容 |
|------|
| message type 常量: `hello`, `pose`, `map_delta`, `map_full` |
| cmd type 常量: `mode`, `manual`, `auto` |
| mode action 常量: `switch_to_manual`, `switch_to_auto` |
| manual action 常量: `forward`, `backward`, `spin_left`, `spin_right`, `stop` |
| auto action 常量: `push`, `cancel` |
| mission type 常量: `goto` |
| cell state 常量: `FREE=0`, `WALL=1`, `UNKNOWN=2` |
| 二进制帧常量: `MAP_FULL_TYPE=0`, `MAP_FULL_SIZE=65545` |

### websocket_client.gd 改造后

仅保留 WebSocket 连接管理（connect/disconnect/send），消息到达后交给 `message_parser.parse()`，获得结构化结果后 emit EventBus 信号。

## 子任务

- [ ] 1. 创建 `src/websocket/protocol/` 目录
- [ ] 2. `protocol_def.gd` — 提取所有魔法字符串/数字为命名常量
- [ ] 3. `message_parser.gd` — 提取上行消息解析逻辑
- [ ] 4. `message_builder.gd` — 提取下行消息构造逻辑
- [ ] 5. `websocket_client.gd` — 接入 message_parser
- [ ] 6. `control_master.gd` — 接入 message_builder
- [ ] 7. `vehicle_panel.gd` — 接入 message_builder
- [ ] 8. `vehicle_panel_manager.gd` — 接入 message_builder
- [ ] 9. `input_handler.gd` — 接入 message_builder
- [ ] 10. 更新 `docs/websocket_protocol.md` 同步变动

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/websocket/protocol/protocol_def.gd` | 新建 | 枚举/常量 |
| `src/websocket/protocol/message_builder.gd` | 新建 | 下行消息构造 |
| `src/websocket/protocol/message_parser.gd` | 新建 | 上行消息解析 |
| `src/websocket/websocket_client.gd` | 修改 | 接入 parser |
| `src/control/control_master.gd` | 修改 | 接入 builder |
| `src/ui/WebSocket/vehicle_panel.gd` | 修改 | 接入 builder |
| `src/ui/WebSocket/vehicle_panel_manager.gd` | 修改 | 接入 builder |
| `src/control/input_handler.gd` | 修改 | 接入 builder |
| `docs/websocket_protocol.md` | 修改 | 同步 |

## 依赖

- task_14 (AppState / mode_transited / cmd 格式)
- 无其他阻塞依赖
